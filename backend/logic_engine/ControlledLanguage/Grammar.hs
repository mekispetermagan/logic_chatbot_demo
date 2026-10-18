{-# LANGUAGE RankNTypes #-}
module ControlledLanguage.Grammar (Backend(..), entryGrammar) where

import Control.Applicative (Alternative(..), some, many, optional)
import Control.Monad (when)
import Data.List (nub, sortOn)
import qualified Domain as Domain
import qualified Ontology as Ontology
import ControlledLanguage.Domain
import qualified Domains.Network.Patterns as Pattern
import Ontology (ValueId(..))
import ControlledLanguage.Syntax

-- One grammar, two backends: exhaustive surface parsing and strict canonical parsing.
-- Each surface reading is rendered with explicit delimiters and checked by the latter.
data Backend p = Backend
  { whitespace :: p ()
  , punctuation :: String -> p String
  , keyword :: String -> p ()
  , number :: Bool -> p Int
  , objectIdentifier :: p Int
  , position :: p (Int,Int)
  , boardRow :: p Int
  , boardColumn :: p Int
  , attempt :: forall a. p a -> p a
  , end :: p ()
  }

entryGrammar :: (Alternative p, MonadFail p) => Domain.Domain -> Backend p -> Bool -> p Entry
entryGrammar domain backend surface = entry
  where
    symbol = punctuation backend
    word = keyword backend
    integer = number backend
    identifier = objectIdentifier backend
    cell = position backend
    rowNumber = boardRow backend
    columnNumber = boardColumn backend
    try p = attempt backend p
    choice = foldr (<|>) empty
    choose = choice . map pure
    phrase = mapM_ word . words
    parens = between (symbol "(") (symbol ")")
    wrapped p = if surface then parens p <|> p else parens p
    brackets = between (symbol "[") (symbol "]")
    between open close p = open *> p <* close
    sepBy1 p separator = (:) <$> p <*> many (separator *> p)
    option fallback p = p <|> pure fallback
    options = choice . map (\(text,value) -> value <$ try (phrase text))

    network p = if isNetwork domain then p else empty
    attrs = if isNetwork domain then ["color"] else appearanceAttributes
    color = vocabulary "color"
    size = vocabulary "size"
    shape = vocabulary "shape"
    attribute = options [(s,s) | s <- attrs]
    component = attribute <|> ("appearance" <$ word "appearance") <|> network ("pattern" <$ word "pattern") <|> network portComponent
    stored = attribute <|> ("position" <$ word "position")
    comparison = stored <|> network ("pattern" <$ word "pattern") <|> network portComponent <|> options [(s,s) | s <- ["row","column"]]
    vocabulary name = options [(v,v) | definition <- Domain.domainAttributes domain,
      Domain.attributeId definition == Ontology.AttributeId name,
      item <- Domain.attributeValues definition, let Ontology.ValueId v = Domain.valueId item]
    value "color" = color
    value "size" = size
    value "shape" = shape
    value _ = fail "Not an appearance attribute"
    exactPattern = options [(text,text) | text <- exactPatterns]
    portComponent = do d <- direction; word "port"; pure (directionName d)
    field = (do a <- attribute; v <- value a; pure (a,v)) <|> network ((,) "pattern" <$> (word "pattern" *> exactPattern))
    description = wrapped $ do
      fields <- field `sepBy1` word "and"
      let names = map fst fields
          order name = case lookup name (zip (attrs ++ ["pattern"]) [0::Int ..]) of Just n -> n; _ -> 9
      when (length names /= length (nub names) || fields /= sortOn (order . fst) fields)
        (fail "Description fields must be unique and ordered color, size, shape")
      pure fields
    appearance = wrapped $ if isNetwork domain then do
      c <- entry "color" color; symbol ","; word "pattern"; p <- exactPattern
      pure (c : patternFields p)
      else sequence [entry "color" color <* symbol ",", entry "size" size <* symbol ",", entry "shape" shape]
      where entry a p = do word a; v <- (Nothing <$ word "none") <|> (Just <$> p); pure (a,v)
    site = (Just <$> (word "on" *> square)) <|> (Nothing <$ phrase "off the board")
    directionName d = case d of North -> "north"; East -> "east"; South -> "south"; West -> "west"
    patternFields p = [(directionName d, if c == '-' then Nothing else Just (directionName d)) | (d,c) <- zip [North,East,South,West] p]
    graph = wrapped $ choice $ map try
      [ NetworkGraph <$ phrase "the network"
      , Component <$> (phrase "the component of" *> ref) <*> optionalGraph
      , Induced <$> (phrase "the subgraph of" *> graph) <*> (phrase "induced by objects matching" *> wrapped (condition True)) ]
    optionalGraph = optional (word "within" *> graph)
    endpoint = (EndpointIt <$ word "it") <|> (SquareEndpoint <$> try (nonPronounSquare)) <|> (do r <- ref; when (r == It) (fail "Use the endpoint pronoun"); pure (ObjectEndpoint r))
    direction = options [("north",North),("east",East),("south",South),("west",West)]
    baseRef = choice [Ident <$> identifier, It <$ word "it",
                      At <$> try (phrase "the object at" *> ((Cell <$> cell) <|> (SquareIt <$ word "it"))),
                      Anaphoric <$> (phrase "the object with" *> description)]
    relativeSquare = Neighbor <$> (phrase "the square" *> direction) <*> (word "of" *> baseRef)
    square = (SquareIt <$ word "it") <|> nonPronounSquare
    nonPronounSquare = (Cell <$> cell) <|> relativeSquare
    ref = network (parens refBody) <|> refBody
    refBody = network (Described <$> try (phrase "the object matching" *> wrapped (condition True))) <|> try baseRef <|> (At <$> try (phrase "the object at" *> relativeSquare))
          <|> (Unique <$> (phrase "the unique object matching" *> wrapped (condition True)))
    collection = choice [network (InGraph <$> try (phrase "objects in" *> graph)), AtSquares <$> try (phrase "objects at" *> brackets (square `sepBy1` symbol ",")),
                         Matching <$> try (phrase "objects matching" *> wrapped (condition True)),
                         Objects <$> (word "objects" *> brackets (ref `sepBy1` symbol ","))]
    targets = (Many <$> collection) <|> (One <$> ref)

    condition object = boolean (if object then objectAtom else squareAtom)
    graphCondition = boolean graphAtom
    linkCondition = boolean (GraphProperty "bridge" Nothing <$ word "bridge")
    graphAtom = choice [GraphProperty "monochromatic" <$> try (phrase "monochromatic with color" *> (Just <$> color)),
      GraphProperty <$> options [(s,s) | s <- ["connected","tree","forest","cyclic","monochromatic","properly colored"]] <*> pure Nothing]
    boolean atom
      | surface = do
          first <- surfacePrimary
          rest <- many ((,) <$> operator <*> surfacePrimary)
          choose (groupings (first : map snd rest) (map fst rest))
      | otherwise = chain (chain neg (word "and" $> And)) (word "or" $> Or)
      where
        chain p op = do first <- p; rest <- many ((,) <$> op <*> p); pure (foldl (\a (f,b) -> f a b) first rest)
        neg = (Not <$> (word "not" *> primary)) <|> primary
        primary = parens (boolean atom) <|> atom
        -- Without a delimiter, negation may scope over any following condition.
        surfacePrimary = parens (boolean atom) <|> (Not <$> (word "not" *> boolean atom)) <|> atom
        operator = (True <$ word "and") <|> (False <$ word "or")
        ($>) p result = result <$ p

    objectAtom = choice $ map try
      [ network (PatternIs <$> (phrase "pattern is" *> exactPattern))
      , network (do a <- portComponent; phrase "is present"; pure (Present a True))
      , network (do a <- portComponent; phrase "is absent"; pure (Present a False))
      , network (NetworkRelation <$> options [("linked to","linked"),("connected to","connected")] <*> ref <*> optionalGraph)
      , network (NetworkRole <$> options [(name,name) | name <- ["dot","tip","straight","bend","tee","cross","isolated","endpoint","junction","unmatched","on a cycle","articulation"]] <*> optionalGraph)
      , Truth <$ word "true"
      , PositionIs <$> (phrase "position is" *> cell)
      , IdentifierIs <$> (phrase "identifier is" *> identifier)
      , do a <- stored; phrase "is present"; pure (Present a True)
      , do a <- stored; phrase "is absent"; pure (Present a False)
      , do a <- attribute; word "is"; ValueIs a <$> value a
      , do a <- comparison; phrase "equals that of"; EqualAttribute a <$> baseRef <*> pure False
      , do a <- comparison; phrase "shares a present value with"; EqualAttribute a <$> baseRef <*> pure True
      , SameObject <$> (phrase "same object as" *> baseRef)
      , Adjacent <$> (phrase "next to" *> baseRef)
      , Directed <$> (phrase "one square" *> direction) <*> (word "of" *> baseRef)
      , Edge <$ phrase "at the edge", Corner <$ phrase "in a corner"
      , Coordinate "row" <$> (phrase "row is" *> rowNumber)
      , Coordinate "column" <$> (phrase "column is" *> columnNumber)
      , OnSquare <$> (phrase "on a square matching" *> wrapped (condition False)) ]
    squareOnlyAtom = choice $ map try
      [Occupied <$ word "occupied", Shading <$> (phrase "shading is" *> options [("light",True),("dark",False)])]
    squareAtom = squareOnlyAtom <|> choice (map try
      [Truth <$ word "true", Edge <$ phrase "at the edge", Corner <$ phrase "in a corner",
       Coordinate "row" <$> (phrase "row is" *> rowNumber), Coordinate "column" <$> (phrase "column is" *> columnNumber)])

    command = choice $ map try
      [ network (do open <- options [("open",True),("close",False)]; d <- direction; phrase "port of"; PortState <$> targets <*> pure d <*> pure open)
      , network (do phrase "set pattern of"; t <- targets; word "to"; SetPattern t <$> exactPattern)
      , network (do phrase "clear pattern of"; SetPattern <$> targets <*> pure "----")
      , network (do mode <- options [("link",True),("unlink",False)]; a <- ref; word (if mode then "to" else "from"); Link a <$> ref <*> pure mode)
      , network (Extend <$> (word "extend" *> ref) <*> direction)
      , network (Trim <$> (phrase "close unmatched ports of" *> targets))
      , network (BuildConnection <$> (phrase "build shortest connection from" *> endpoint) <*> (word "to" *> endpoint) <*> optional (phrase "with route color" *> color))
      , network (do word "rotate"; phrase "ports of"; t <- targets; word "by"; TransformPorts t . Rotate <$> turn)
      , network (do word "reflect"; phrase "ports of"; t <- targets; word "across"; TransformPorts t . Reflect <$> options [("vertical",True),("horizontal",False)])
      , network (do word "rotate"; phrase "drawing of"; c <- collection; word "by"; t <- turn; word "about"; TransformDrawing c (Rotate t) <$> pivot)
      , network (do word "reflect"; phrase "drawing of"; c <- collection; word "across"; a <- options [("vertical",True),("horizontal",False)]; word "through"; TransformDrawing c (Reflect a) <$> pivot)
      , Create <$> (phrase "create object" *> (option [] (word "with" *> description))) <*> site
      , DeleteAll <$ phrase "delete every object"
      , Delete <$> (word "delete" *> targets)
      , do phrase "set appearance of"; t <- targets; word "to"; SetAppearance t <$> appearance
      , do word "set"; a <- attribute; word "of"; t <- targets; word "to"; SetAttribute t a . Just <$> value a
      , do phrase "clear appearance of"; t <- targets; pure (SetAppearance t [(a,Nothing) | a <- appearanceAttributesFor domain])
      , do word "clear"; a <- attribute; word "of"; t <- targets; pure (SetAttribute t a Nothing)
      , ExchangePositions <$> (phrase "exchange positions of" *> ref) <*> (word "and" *> ref)
      , do word "exchange"; a <- component; word "of"; l <- ref; word "and"; CopyComponent Exchange a l <$> ref
      , Unplace <$> (word "unplace" *> targets)
      , MoveNextTo <$> (word "move" *> ref) <*> (phrase "next to" *> ref)
      , Move <$> (word "move" *> ref) <*> (word "to" *> square)
      , Step <$> (word "step" *> ref) <*> direction
      , do mode <- options [("copy",Copy),("transfer",Transfer)]; a <- component; word "from"; l <- ref; word "to"; CopyComponent mode a l <$> ref
      , Clone <$> (phrase "clone appearance of" *> ref <* phrase "into a new object") <*> site
      , Shift <$> (phrase "shift positions of" *> collection) <*> (word "by" *> wrapped ((,) <$> (word "east" *> integer True <* symbol ",") <*> (word "north" *> integer True)))
      , Rearrange <$> (phrase "rearrange positions by" *> brackets (((,) <$> ref <*> (word "to" *> square)) `sepBy1` symbol ","))
      , Permute <$> (phrase "permute appearance by" *> brackets (((,) <$> ref <*> (word "to" *> ref)) `sepBy1` symbol ","))
      , do word "rotate"; positions <- transformComponent; word "of"; c <- collection; word "by"; t <- turn; word "about"; Transformation positions c (Rotate t) <$> pivot
      , do word "reflect"; positions <- transformComponent; word "of"; c <- collection; word "across"; axis <- options [("vertical",True),("horizontal",False)]; word "through"; Transformation positions c (Reflect axis) <$> pivot ]
    transformComponent = options [("positions",True),("appearance",False)]
    turn = options [("90 degrees clockwise",Clockwise),("180 degrees",HalfTurn),("90 degrees counterclockwise",Counterclockwise)]
    pivot = do
      phrase "the center of rectangle"; a@(x,y) <- cell; word "to"; b@(u,v) <- cell
      when (x > u || y > v) (fail "Rectangle requires bottom-left then top-right")
      pure (a,b)
    question = choice $ map try
      [ network (do word "does"; g <- graph; word "satisfy"; CheckGraph g <$> wrapped graphCondition)
      , network (do phrase "does the link between"; a <- ref; word "and"; b <- ref; g <- optionalGraph; word "satisfy"; CheckLink a b g <$> wrapped linkCondition)
      , network (do phrase "how many"; a <- options [(s,s) | s <- ["components","links","objects"]]; word "in"; GraphNumber a <$> graph)
      , network (do phrase "what is the degree of"; a <- ref; NetworkQuery "degree" a Nothing <$> optionalGraph)
      , network (do mode <- options [("what is the distance from","distance"),("what is a shortest path from","path")]; a <- ref; word "to"; b <- ref; NetworkQuery mode a (Just b) <$> optionalGraph)
      , do phrase "does it satisfy"; c <- wrapped (boolean (try objectAtom <|> squareOnlyAtom))
           when (null (conditionKinds c)) (fail "Predicate mixes object and square types")
           pure (CheckIt c)
      , Exists <$> (word "does" *> identifier <* word "exist")
      , do word "does"; r <- ref; when (r == It) (fail "Use the pronoun check"); word "satisfy"; CheckObject r <$> wrapped (condition True)
      , CheckSquare <$> (word "does" *> nonPronounSquare) <*> (word "satisfy" *> wrapped (condition False))
      , do phrase "what is the"; a <- options [(s,s) | s <- (if isNetwork domain then ["color","pattern","position","identifier","row","column","appearance"] else ["color","size","shape","position","identifier","row","column","appearance"])]; word "of"; Query a <$> ref
      , Occupant <$> (phrase "which object occupies" *> square)
      , do word "which"; object <- universe; word "match"; Select object <$> wrapped (condition object)
      , do phrase "how many"; object <- universe; word "match"; Count object <$> wrapped (condition object)
      , do word "does"; every <- options [("every",True),("some",False)]; object <- options [("object",True),("square",False)]; word "matching"; a <- wrapped (condition object); word "satisfy"; Quantified every object a <$> wrapped (condition object) ]
    universe = options [("objects",True),("squares",False)]
    sentence = try (Command <$> command <* symbol ".") <|> (Question <$> question <* symbol "?")
    entry = whitespace backend *> (try (Undo <$ (word "undo" *> symbol "."))
           <|> (Batch <$> (word "atomically" *> between (symbol "{") (symbol "}") (some (command <* symbol "."))) <* symbol ".")
           <|> (Sequence <$> some sentence)) <* end backend

-- Enumerate meaningful scope choices, collapsing associative chains locally.
-- Parenthesized operands have already been parsed as units and cannot be split here.
groupings :: [Condition] -> [Bool] -> [Condition]
groupings [atom] [] = [normalize atom]
groupings atoms operators
  | all id operators = [normalize (foldl1 And atoms)]
  | all not operators = [normalize (foldl1 Or atoms)]
  | otherwise = nub
      [ normalize ((if operators !! (split-1) then And else Or) left right)
      | split <- [1 .. length atoms-1]
      , left <- groupings (take split atoms) (take (split-1) operators)
      , right <- groupings (drop split atoms) (drop split operators)
      ]

normalize :: Condition -> Condition
normalize (And a b) = foldl1 And (andTerms (normalize a) ++ andTerms (normalize b))
  where andTerms (And x y) = andTerms x ++ andTerms y; andTerms x = [x]
normalize (Or a b) = foldl1 Or (orTerms (normalize a) ++ orTerms (normalize b))
  where orTerms (Or x y) = orTerms x ++ orTerms y; orTerms x = [x]
normalize (Not c) = Not (normalize c)
normalize c = c

exactPatterns :: [String]
exactPatterns = sequence [[c,'-'] | c <- "nesw"]

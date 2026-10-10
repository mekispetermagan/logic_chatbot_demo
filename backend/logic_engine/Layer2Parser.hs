module Layer2Parser (parseSentence, parseSentences, isUndoEntry) where

import Control.Applicative (some, (<|>))
import Data.Char (isSpace, toLower, ord, isDigit)
import Data.List (isPrefixOf)
import Data.Maybe (mapMaybe)
import Data.Void (Void)
import Text.Read (readMaybe)
import Text.Megaparsec (Parsec, parse, eof, errorBundlePretty, takeWhile1P, oneOf)
import Text.Megaparsec.Char (space)
import Ontology
import AtomicPerformative (RemovableAttribute(..))
import AtomicPropertyQuery
import Layer2Syntax

-- Undo is an entry-level request: all text following the prefix is ignored.
isUndoEntry :: String -> Bool
isUndoEntry = isPrefixOf "undo" . map toLower . dropWhile isSpace

type Parser = Parsec Void String

-- Megaparsec handles entry boundaries and locations; the finite sentence grammar
-- enumerates legal subject boundaries and rejects multiple complete parses.
entry :: Parser [([String], Maybe Char)]
entry = space *> some sentenceTokens <* eof
  where
    word = map toLower <$> takeWhile1P (Just "word") (\c -> not (isSpace c) && c /= '.' && c /= '?') <* space
    sentenceTokens = do
      words' <- some word
      mark <- (Just <$> oneOf ".?" <* space) <|> (Nothing <$ eof)
      pure (words', mark)

parseSentences :: String -> Either String [Sentence]
parseSentences input = case parse entry "controlled English" input of
  Left message -> Left (errorBundlePretty message)
  Right chunks -> traverse parseChunk chunks

parseSentence :: String -> Either String Sentence
parseSentence input = do
  sentences <- parseSentences input
  case sentences of
    [sentence] -> Right sentence
    _ -> Left "Expected exactly one sentence"

descriptor :: String -> Maybe Property
descriptor word = lookup word
  [("red", C Red), ("blue", C Blue), ("green", C Green), ("yellow", C Yellow),
   ("small", S Small), ("medium", S Medium), ("large", S Large),
   ("cube", Sh Cube), ("sphere", Sh Sphere), ("pyramid", Sh Pyramid)]

attribute :: String -> Maybe Attribute
attribute word = lookup word
  [("color", ColorAttribute), ("size", SizeAttribute), ("shape", ShapeAttribute),
   ("position", PositionAttribute), ("row", RowAttribute), ("column", ColumnAttribute)]

square :: String -> Maybe Position
square [column, row] | column >= 'a' && column <= 'h' && row >= '1' && row <= '8' =
  Just (ord column - ord 'a', ord row - ord '1')
square _ = Nothing

reference :: String -> Maybe ObjectReference
reference ('#':digits) | not (null digits) && all isDigit digits = do
  number <- readMaybe digits :: Maybe Integer
  if number >= 0 && number <= toInteger (maxBound :: Int)
    then Just (ById (Id (fromInteger number))) else Nothing
reference word = AtSquare <$> square word

subject :: [String] -> Maybe Subject
subject ["it"] = Just It
subject [word] | Just ref <- reference word = Just (Reference ref)
subject ("the":words') = Definite <$> description words'
subject ("a":words') = Indefinite <$> description words'
subject words' = Indefinite <$> description words'

description :: [String] -> Maybe [Property]
description words' = case stripOne words' of
  [] -> Nothing
  descriptors -> traverse descriptor descriptors
  where
    stripOne tokens | not (null tokens) && last tokens == "one" = init tokens
    stripOne tokens = tokens

dropWord :: String -> [String] -> [String]
dropWord word (first:rest) | word == first = rest
dropWord _ words' = words'

destination :: [String] -> Maybe Property
destination words' = case dropWord "on" (dropWord "to" words') of
  [position] -> P <$> square position
  _ -> Nothing

-- A destination can occur once, only at the end of a predicate.
predicate :: [String] -> Maybe [Property]
predicate words' = let tokens = dropWord "a" (dropWord "to" (dropWord "is" words')) in
  case destination tokens of
    Just position -> Just [position]
    Nothing -> case span (\word -> descriptor word /= Nothing) tokens of
      ([], _) -> Nothing
      (descriptors, rest) -> do
        properties <- traverse descriptor descriptors
        case rest of
          [] -> Just properties
          _ -> (properties ++) . (:[]) <$> destination rest

splits :: [a] -> [([a], [a])]
splits tokens = [splitAt index tokens | index <- [1 .. length tokens - 1]]

isIndefinite :: Subject -> Bool
isIndefinite (Indefinite _) = True
isIndefinite _ = False

hasBoundary :: [String] -> Bool
hasBoundary (word:_) = word == "is" || word == "to"
hasBoundary _ = False

isPosition :: Property -> Bool
isPosition (P _) = True
isPosition _ = False

attribution :: [String] -> [Sentence]
attribution words' = mapMaybe candidate (splits tokens)
  where
    (verb, tokens) = case words' of
      "move":rest -> ("move", rest)
      "turn":rest -> ("turn", rest)
      _ -> ("", words')
    candidate (before, after) = do
      who <- subject before
      properties <- predicate after
      let positional = all isPosition properties
          namedBoundary = case who of
            Definite _ -> positional || hasBoundary after
            Indefinite _ -> positional || hasBoundary after
            _ -> True
      if not namedBoundary || (isIndefinite who && not (any isPosition properties))
        || (verb == "move" && not positional) || (verb == "turn" && positional)
        then Nothing else Just (Attribution who properties)

-- Structural operands must denote existing objects. Description boundaries
-- are enumerated just like attribution boundaries, with optional 'and'.
structural :: [String] -> [Sentence]
structural ("remove":tokens) = unary Removal (stripFromBoard tokens)
  where
    stripFromBoard words' = case reverse words' of
      "board":"from":rest -> reverse rest
      _ -> words'
structural ("erase":tokens) = unary Deletion tokens
structural ("delete":tokens) = unary Deletion tokens
structural ("swap":tokens) = mapMaybe candidate (splits tokens)
  where
    candidate (before, after) = Swapping <$> existingSubject before
                                          <*> existingSubject (dropWord "and" after)
structural tokens = mapMaybe candidate (splits tokens)
  where
    candidate (before, ["remove", name]) = do
      who <- existingSubject before
      attr <- lookup name [("color", RemoveColor), ("size", RemoveSize),
                           ("shape", RemoveShape), ("square", RemoveSquare)]
      pure (AttributeRemoval who attr)
    candidate _ = Nothing

existingSubject :: [String] -> Maybe Subject
existingSubject tokens = do
  who <- subject tokens
  if isIndefinite who then Nothing else Just who

unary :: (Subject -> Sentence) -> [String] -> [Sentence]
unary constructor tokens = maybe [] ((:[]) . constructor) (existingSubject tokens)

questions :: [String] -> [Sentence]
questions words' = valueQueries ++ checks
  where
    valueTokens = case words' of
      "what":"is":rest -> dropWord "the" rest
      _ -> words'
    valueQueries = case valueTokens of
      name:"of":rest -> maybe [] (:[]) $ do
        attr <- attribute name
        who <- subject rest
        if isIndefinite who then Nothing else Just (Query attr who)
      _ -> mapMaybe shorthand (splits words')
    shorthand (before, after) = do
      who <- subject before
      attr <- case dropWord "is" after of [name] -> attribute name; _ -> Nothing
      if isIndefinite who then Nothing else Just (Query attr who)
    (inverted, tokens) = case words' of "is":rest -> (True, rest); _ -> (False, words')
    checks = mapMaybe check (splits tokens)
    check (before, after) = do
      who <- subject before
      if isIndefinite who then Nothing else pure ()
      properties <- predicate after
      property <- case properties of [value] -> Just value; _ -> Nothing
      -- Preserve the core rule that positional 'to' is performative-only.
      if isPosition property && "to" `elem` after then Nothing else pure ()
      let boundary = case who of Definite _ -> inverted || hasBoundary after; _ -> True
      if boundary then Just (Check who property) else Nothing

parseChunk :: ([String], Maybe Char) -> Either String Sentence
parseChunk (tokens, mark) = case (if mark == Just '?' then questions tokens ++ derivedQuestions tokens else structural tokens ++ attribution tokens ++ derivedPerformatives tokens) of
  [sentence] -> Right sentence
  [] -> Left ("Unsupported syntax: " ++ unwords tokens ++ maybe "" (:[]) mark)
  _ -> Left ("Ambiguous subject/predicate boundary: " ++ unwords tokens)

-- Layer 3 uses explicit relation words to separate existing-object subjects.
removable :: String -> Maybe RemovableAttribute
removable name = lookup name [("color", RemoveColor), ("size", RemoveSize),
                             ("shape", RemoveShape), ("square", RemoveSquare)]

comparisonAttribute :: String -> Maybe Attribute
comparisonAttribute "square" = Just PositionAttribute
comparisonAttribute name = attribute name

direction :: String -> Maybe Direction
direction name = lookup name [("up", Up), ("down", Down), ("left", Leftward), ("right", Rightward)]

relative :: [String] -> Maybe (Direction, [String])
relative tokens = case dropWord "just" tokens of
  "above":rest -> Just (Up, rest)
  "under":rest -> Just (Down, rest)
  "right":"of":rest -> Just (Rightward, rest)
  "left":"of":rest -> Just (Leftward, rest)
  _ -> Nothing

derivedPerformatives :: [String] -> [Sentence]
derivedPerformatives ("move":tokens) = mapMaybe candidate (splits tokens)
  where
    candidate (before, after) = do
      who <- existingSubject before
      case after of
        [name] -> StepMove who <$> direction name
        "next":"to":rest -> NeighborMove who <$> existingSubject rest
        _ -> do
          (whereTo, rest) <- relative after
          RelativeMove who whereTo <$> existingSubject rest
derivedPerformatives ("make":tokens) = mapMaybe candidate (splits tokens)
  where
    candidate (before, after) = do
      who <- existingSubject before
      case dropWord "the" after of
        "same":name:"as":rest -> do
          attr <- removable name
          if attr == RemoveSquare then Nothing else CopyAttribute who attr <$> existingSubject rest
        _ -> Nothing
derivedPerformatives _ = []


derivedQuestions :: [String] -> [Sentence]
derivedQuestions ("how":"many":tokens) = squareCounts ++ objectCounts
  where
    stripped = dropWord "are" (dropWord "squares" tokens)
    squareCounts = case stripped of
      [name] | name `elem` ["empty", "free", "occupied", "taken"] ->
        [CountSquares (name `elem` ["occupied", "taken"])]
      _ -> []
    objectTokens = dropWord "are" (dropWord "objects" tokens)
    objectCounts = case objectTokens of
      "next":"to":rest -> maybe [] ((:[]) . CountObjects . Neighboring) (existingSubject rest)
      ["at", "the", "edge"] -> [CountObjects AtEdge]
      ["in", "a", "corner"] -> [CountObjects InCorner]
      _ -> maybe [] ((:[]) . CountObjects . Described) (traverse descriptor objectTokens)
derivedQuestions words' = quantified ++ relations
  where
    tokens = case words' of
      "is":rest -> rest
      "does":rest -> rest
      _ -> words'
    quantifierTokens = dropWord "are" words'
    quantified = case quantifierTokens of
      quantifier:rest | quantifier `elem` ["all", "some"] ->
        mapMaybe (quantifiedCandidate (quantifier == "all")) (splits rest)
      _ -> []
    quantifiedCandidate universal (before, after) = do
      -- At least one separator is mandatory. Consume 'objects are' together.
      following <- case after of
        "objects":rest -> Just (dropWord "are" rest)
        "are":rest -> Just rest
        _ -> Nothing
      first <- description before
      second <- description following
      pure (Quantified universal first second)
    relations = mapMaybe relation (splits tokens)
    relation (before, after) = do
      who <- existingSubject before
      case after of
        ["on", "board"] -> Just (SpatialQuestion who OnBoard Nothing)
        ["on", "the", "board"] -> Just (SpatialQuestion who OnBoard Nothing)
        ["at", "the", "edge"] -> Just (SpatialQuestion who Edge Nothing)
        ["in", "a", "corner"] -> Just (SpatialQuestion who Corner Nothing)
        "next":"to":rest -> SpatialQuestion who NextTo . Just <$> existingSubject rest
        _ -> sameOrHas who after
    sameOrHas who after = case dropWord "the" (dropWord "have" after) of
      ["a", name] -> do
        attr <- removable name
        if take 1 after == ["have"] then Just (SpatialQuestion who (Has attr) Nothing) else Nothing
      "same":name:"as":rest -> do
        attr <- comparisonAttribute name
        SpatialQuestion who (Same attr) . Just <$> existingSubject rest
      _ -> case dropWord "the" (dropWord "in" after) of
        "same":name:"as":rest | name `elem` ["square", "row", "column"] -> do
          attr <- comparisonAttribute name
          SpatialQuestion who (Same attr) . Just <$> existingSubject rest
        _ -> Nothing

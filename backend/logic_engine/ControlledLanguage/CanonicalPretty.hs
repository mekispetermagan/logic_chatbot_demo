module ControlledLanguage.CanonicalPretty where

import Data.List (intercalate)
import Ontology (prettyPosition)
import ControlledLanguage.Syntax

descriptionText :: [(String,String)] -> String
descriptionText values = "(" ++ intercalate " and " [a ++ " " ++ v | (a,v) <- values] ++ ")"
appearanceText :: [(String,Maybe String)] -> String
appearanceText original = "(" ++ intercalate ", " [a ++ " " ++ maybe "none" id v | (a,v) <- values] ++ ")"
  where
    values = if any ((`elem` portNames) . fst) original then
      [("color", maybe Nothing id (lookup "color" original)), ("pattern", Just (patternText original))]
      else original
portNames :: [String]
portNames = ["north","east","south","west"]
patternText :: [(String,Maybe String)] -> String
patternText fields = [if lookup name fields == Just (Just name) then c else '-' | (name,c) <- zip portNames "nesw"]
componentText :: String -> String
componentText a = a ++ if a `elem` portNames then " port" else ""

refText :: Ref -> String
refText (Ident n) = "#" ++ show n
refText It = "it"
refText (At p) = "the object at " ++ squareText p
refText (Anaphoric d) = "the object with " ++ descriptionText d
refText (Described c) = "the object matching " ++ conditionClause c
refText (Unique c) = "the unique object matching (" ++ conditionText c ++ ")"
refOperandText :: Ref -> String
refOperandText r = case r of
  Unique _ -> "(" ++ refText r ++ ")"
  Described _ -> "(" ++ refText r ++ ")"
  _ -> refText r
squareText :: Square -> String
squareText (Cell p) = prettyPosition p
squareText SquareIt = "it"
squareText (Neighbor d r) = "the square " ++ directionText d ++ " of " ++ refText r
directionText :: Direction -> String
directionText North = "north"
directionText East = "east"
directionText South = "south"
directionText West = "west"
conditionText :: Condition -> String
conditionText Truth = "true"
conditionText (ValueIs a v) = a ++ " is " ++ v
conditionText (Present a b) = componentText a ++ if b then " is present" else " is absent"
conditionText (PositionIs p) = "position is " ++ prettyPosition p
conditionText (IdentifierIs n) = "identifier is #" ++ show n
conditionText Occupied = "occupied"
conditionText (Shading b) = "shading is " ++ if b then "light" else "dark"
conditionText (Coordinate "row" n) = "row is " ++ show (n+1)
conditionText (Coordinate _ n) = "column is " ++ [toEnum (fromEnum 'A'+n)]
conditionText (EqualAttribute a r present) = componentText a ++ (if present then " shares a present value with " else " equals that of ") ++ refText r
conditionText (SameObject r) = "same object as " ++ refText r
conditionText (Adjacent r) = "next to " ++ refText r
conditionText (Directed d r) = "one square " ++ directionText d ++ " of " ++ refText r
conditionText Edge = "at the edge"
conditionText Corner = "in a corner"
conditionText (PatternIs p) = "pattern is " ++ p
conditionText (NetworkRole role scope) = "(" ++ role ++ scopeText scope ++ ")"
conditionText (NetworkRelation relation r scope) = "(" ++ relation ++ " to " ++ refOperandText r ++ scopeText scope ++ ")"
conditionText (GraphProperty name hue) = name ++ maybe "" (" with color " ++) hue

conditionText (OnSquare c) = "(on a square matching (" ++ conditionText c ++ "))"
conditionText (Not c) = "(not (" ++ conditionText c ++ "))"
conditionText (And a b) = "(" ++ conditionText a ++ " and " ++ conditionText b ++ ")"
conditionText (Or a b) = "(" ++ conditionText a ++ " or " ++ conditionText b ++ ")"
conditionClause :: Condition -> String
conditionClause c = "(" ++ conditionText c ++ ")"
scopeText :: Maybe GraphExpr -> String
scopeText = maybe "" ((" within " ++) . graphText)
graphText :: GraphExpr -> String
graphText expression = "(" ++ body ++ ")"
  where
    body = case expression of
      NetworkGraph -> "the network"
      Component r scope -> "the component of " ++ refOperandText r ++ scopeText scope
      Induced source c -> "the subgraph of " ++ graphChild source ++ " induced by objects matching " ++ conditionClause c
    graphChild source = graphText source
endpointText :: Endpoint -> String
endpointText EndpointIt = "it"
endpointText (SquareEndpoint p) = squareText p
endpointText (ObjectEndpoint r) = refText r

collectionText :: Collection -> String
collectionText (Objects refs) = "objects [" ++ intercalate ", " (map refText refs) ++ "]"
collectionText (AtSquares squares) = "objects at [" ++ intercalate ", " (map squareText squares) ++ "]"
collectionText (InGraph g) = "objects in " ++ graphText g
collectionText (Matching c) = "objects matching (" ++ conditionText c ++ ")"
targetsText :: Targets -> String
targetsText (One r) = refText r
targetsText (Many c) = collectionText c
siteText :: Maybe Square -> String
siteText = maybe "off the board" (("on " ++) . squareText)
commandText :: Command -> String
commandText command = body ++ "."
  where
    body = case command of
      Create d p -> "create object" ++ (if null d then "" else " with " ++ descriptionText d) ++ " " ++ siteText p
      Delete t -> "delete " ++ targetsText t
      DeleteAll -> "delete every object"
      SetAttribute t a (Just v) -> "set " ++ a ++ " of " ++ targetsText t ++ " to " ++ v
      SetAttribute t a Nothing -> "clear " ++ a ++ " of " ++ targetsText t
      SetAppearance t attrs -> "set appearance of " ++ targetsText t ++ " to " ++ appearanceText attrs
      Move r p -> "move " ++ refText r ++ " to " ++ squareText p
      Unplace t -> "unplace " ++ targetsText t
      ExchangePositions a b -> "exchange positions of " ++ refText a ++ " and " ++ refText b
      Step r d -> "step " ++ refText r ++ " " ++ directionText d
      MoveNextTo a b -> "move " ++ refText a ++ " next to " ++ refText b
      CopyComponent mode a source dest -> case mode of
        Exchange -> "exchange " ++ componentText a ++ " of " ++ refText source ++ " and " ++ refText dest
        _ -> (if mode == Copy then "copy " else "transfer ") ++ componentText a ++ " from " ++ refText source ++ " to " ++ refText dest
      Clone r p -> "clone appearance of " ++ refText r ++ " into a new object " ++ siteText p
      Shift c (x,y) -> "shift positions of " ++ collectionText c ++ " by (east " ++ show x ++ ", north " ++ show y ++ ")"
      Rearrange pairs -> "rearrange positions by [" ++ intercalate ", " [refText r ++ " to " ++ squareText p | (r,p) <- pairs] ++ "]"
      Permute pairs -> "permute appearance by [" ++ intercalate ", " [refText a ++ " to " ++ refText b | (a,b) <- pairs] ++ "]"
      PortState t d open -> (if open then "open " else "close ") ++ directionText d ++ " port of " ++ targetsText t
      SetPattern t p -> "set pattern of " ++ targetsText t ++ " to " ++ p
      Link a b linked -> (if linked then "link " else "unlink ") ++ refText a ++ (if linked then " to " else " from ") ++ refText b
      Extend r d -> "extend " ++ refText r ++ " " ++ directionText d
      Trim t -> "close unmatched ports of " ++ targetsText t
      BuildConnection a b hue -> "build shortest connection from " ++ endpointText a ++ " to " ++ endpointText b ++ maybe "" (" with route color " ++) hue
      TransformPorts t transform -> case transform of
        Rotate angle -> "rotate ports of " ++ targetsText t ++ " by " ++ turnText angle
        Reflect axis -> "reflect ports of " ++ targetsText t ++ " across " ++ (if axis then "vertical" else "horizontal")
      TransformDrawing c transform (a,b) ->
        let center = "the center of rectangle " ++ prettyPosition a ++ " to " ++ prettyPosition b
        in case transform of
          Rotate angle -> "rotate drawing of " ++ collectionText c ++ " by " ++ turnText angle ++ " about " ++ center
          Reflect axis -> "reflect drawing of " ++ collectionText c ++ " across " ++ (if axis then "vertical" else "horizontal") ++ " through " ++ center

      Transformation positions c transformation (a,b) ->
        let what = (if positions then "positions" else "appearance") ++ " of " ++ collectionText c
            center = "the center of rectangle " ++ prettyPosition a ++ " to " ++ prettyPosition b
        in case transformation of
          Rotate t -> "rotate " ++ what ++ " by " ++ turnText t ++ " about " ++ center
          Reflect vertical -> "reflect " ++ what ++ " across " ++ (if vertical then "vertical" else "horizontal") ++ " through " ++ center
turnText :: Turn -> String
turnText Clockwise = "90 degrees clockwise"
turnText HalfTurn = "180 degrees"
turnText Counterclockwise = "90 degrees counterclockwise"
questionText :: Question -> String
questionText q = body ++ "?"
  where
    clause c = "(" ++ conditionText c ++ ")"
    universe b = if b then "objects" else "squares"
    body = case q of
      CheckGraph g c -> "does " ++ graphText g ++ " satisfy " ++ clause c
      CheckLink a b g c -> "does the link between " ++ refText a ++ " and " ++ refText b ++ scopeText g ++ " satisfy " ++ clause c
      GraphNumber a g -> "how many " ++ a ++ " in " ++ graphText g
      NetworkQuery "degree" a _ g -> "what is the degree of " ++ refText a ++ scopeText g
      NetworkQuery mode a (Just b) g -> (if mode == "distance" then "what is the distance from " else "what is a shortest path from ") ++ refText a ++ " to " ++ refText b ++ scopeText g
      NetworkQuery _ _ Nothing _ -> "invalid network query"

      CheckIt c -> "does it satisfy " ++ clause c
      Exists n -> "does #" ++ show n ++ " exist"
      CheckObject r c -> "does " ++ refText r ++ " satisfy " ++ clause c
      CheckSquare p c -> "does " ++ squareText p ++ " satisfy " ++ clause c
      Query a r -> "what is the " ++ a ++ " of " ++ refText r
      Occupant p -> "which object occupies " ++ squareText p
      Select b c -> "which " ++ universe b ++ " match " ++ clause c
      Count b c -> "how many " ++ universe b ++ " match " ++ clause c
      Quantified every b restriction predicate -> "does " ++ (if every then "every " else "some ") ++
        (if b then "object" else "square") ++ " matching " ++ clause restriction ++ " satisfy " ++ clause predicate
sentenceText :: Sentence -> String
sentenceText (Command c) = commandText c
sentenceText (Question q) = questionText q
entryText :: Entry -> String
entryText Undo = "undo."
entryText (Sequence sentences) = unwords (map sentenceText sentences)
entryText (Batch commands) = "atomically { " ++ unwords (map commandText commands) ++ " }."

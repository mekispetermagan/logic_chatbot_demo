module Domains.Cellular.Language.Pretty where

import Data.Char (chr, ord, toLower)
import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Domains.Cellular.Types
import Domains.Cellular.Language.Syntax
import Ontology (Position)

colorText :: Color -> String
colorText = map toLower . show
positionText :: Position -> String
positionText (x,y) = [chr (ord 'A'+x)] ++ show (y+1)
listText :: (a -> String) -> [a] -> String
listText f xs = "[" ++ intercalate ", " (map f xs) ++ "]"
conditionText :: (a -> String) -> Condition a -> String
conditionText f (Atom a) = f a
conditionText f (Not a) = "(not " ++ conditionText f a ++ ")"
conditionText f (And a b) = "(" ++ conditionText f a ++ " and " ++ conditionText f b ++ ")"
conditionText f (Or a b) = "(" ++ conditionText f a ++ " or " ++ conditionText f b ++ ")"
referenceText :: Reference -> String
referenceText (Cell p) = positionText p
referenceText It = "it"
referenceText (WithColor c) = "the cell with color " ++ colorText c
referenceText (Matching unique c) = "the " ++ (if unique then "unique " else "") ++ "cell matching " ++ conditionText predicateText c
referenceText (Relative d r) = "the cell " ++ d ++ " of " ++ referenceText r
predicateText :: CellPredicate -> String
predicateText Always = "true"
predicateText (ColorIs c) = "color is " ++ colorText c
predicateText (RowIs y) = "row is " ++ show (y+1)
predicateText (ColumnIs x) = "column is " ++ [chr (ord 'A'+x)]
predicateText (SameCell r) = "same cell as " ++ referenceText r
predicateText (SameColor r) = "color equals that of " ++ referenceText r
predicateText (NeighborOf r) = "neighbor of " ++ referenceText r
predicateText (ConnectedTo r) = "connected to " ++ referenceText r
predicateText (NeighborCount c ns) = "neighbor count for color " ++ colorText c ++ " is in " ++ listText show ns
predicateText Changes = "changes in the next generation"
boardPredicateText :: BoardPredicate -> String
boardPredicateText (Monochromatic Nothing) = "monochromatic"
boardPredicateText (Monochromatic (Just c)) = "monochromatic with color " ++ colorText c
boardPredicateText FixedPoint = "fixed point"
collectionText :: Collection -> String
collectionText (Cells [r]) = referenceText r
collectionText (Cells rs) = "cells " ++ listText referenceText rs
collectionText (Filter c) = "cells matching " ++ conditionText predicateText c
collectionText (Component r) = "cells connected to " ++ referenceText r
collectionText (Rectangle p q) = "cells in rectangle " ++ positionText p ++ " to " ++ positionText q
neighborhoodText :: Neighborhood -> String
neighborhoodText Moore = "moore"
neighborhoodText Orthogonal = "von neumann"
ruleText :: Rule -> String
ruleText r = "target " ++ colorText (targetColor r) ++ ", counts " ++ listText show (Set.toAscList (neighborCounts r)) ++ ", enabled " ++ if enabled r then "true" else "false"
rulesetText :: Ruleset -> String
rulesetText r = "palette " ++ listText colorText (Set.toAscList (palette r)) ++ ", neighborhood " ++ neighborhoodText (neighborhood r) ++ ", rules " ++ listText (\(c,v) -> colorText c ++ ": " ++ ruleText v) (Map.toAscList (rules r))
generationsText :: Int -> String
generationsText n = show n ++ if n == 1 then " generation" else " generations"
commandText :: Command -> String
commandText (Paint xs c) = "set color of " ++ collectionText xs ++ " to " ++ colorText c
commandText (Advance n) = "advance " ++ generationsText n
commandText (SetRule c r) = "set rule for " ++ colorText c ++ " to " ++ ruleText r
commandText (ClearRule c) = "clear rule for " ++ colorText c
commandText (ToggleRule c yes) = (if yes then "enable" else "disable") ++ " rule for " ++ colorText c
commandText (SetNeighborhood n) = "set neighborhood to " ++ neighborhoodText n
commandText (ReplaceRuleset r refill) = "replace ruleset with " ++ rulesetText r ++ ", " ++ if refill then "randomly refilling the board if required" else "preserving the board"
commandText Initialize = "initialize the board randomly"
commandText (Copy a b) = "copy color from " ++ referenceText a ++ " to " ++ referenceText b
commandText (Exchange a b) = "exchange color of " ++ referenceText a ++ " and " ++ referenceText b
commandText (ReplaceColors pairs) = "replace colors by " ++ listText (\(r,c) -> referenceText r ++ " to " ++ colorText c) pairs
commandText (Permute pairs) = "permute colors by " ++ listText (\(r,s) -> referenceText r ++ " to " ++ referenceText s) pairs
commandText (Shift x y) = "shift colors of the board by east " ++ show x ++ ", north " ++ show y
commandText (Spatial xs t p q) = case t of
  Rotation n -> "rotate colors of " ++ collectionText xs ++ " by " ++ angle n ++ " about " ++ pivot
  Reflection v -> "reflect colors of " ++ collectionText xs ++ " across " ++ (if v then "vertical" else "horizontal") ++ " through " ++ pivot
  where
    pivot = "the center of rectangle " ++ positionText p ++ " to " ++ positionText q
    angle 90 = "90 degrees clockwise"
    angle 180 = "180 degrees"
    angle _ = "90 degrees counterclockwise"
questionText :: Question -> String
questionText (ColorOf r) = "what is the color of " ++ referenceText r
questionText (Check r c) = "does " ++ referenceText r ++ " satisfy " ++ conditionText predicateText c
questionText (Meta m) = "what is the " ++ case m of
  Generation -> "generation"; Palette -> "palette"; NeighborhoodName -> "neighborhood"; Revision -> "ruleset revision"; CompleteRuleset -> "ruleset"
questionText (RuleOf c) = "what is the rule for " ++ colorText c
questionText (Select count seed c) = (if count then "how many " else "which ") ++ maybe "cells" (\r -> "neighbors of " ++ referenceText r) seed ++ " match " ++ conditionText predicateText c
questionText (Quantify every p q) = "does " ++ (if every then "every" else "some") ++ " cell matching " ++ conditionText predicateText p ++ " satisfy " ++ conditionText predicateText q
questionText (CheckBoard c) = "does the board satisfy " ++ conditionText boardPredicateText c
questionText (Transition r) = "what is the next transition of " ++ referenceText r
questionText (Forecast n q) = "after " ++ generationsText n ++ ", " ++ questionText q
questionText (ReturnTime n) = "what is the least return time of the board within " ++ generationsText n
questionText (FirstCell n r c) = "what is the first generation offset within " ++ generationsText n ++ " at which " ++ referenceText r ++ " satisfies " ++ conditionText predicateText c
questionText (FirstBoard n c) = "what is the first generation offset within " ++ generationsText n ++ " at which the board satisfies " ++ conditionText boardPredicateText c
questionText (Stabilization yes n) = (if yes then "does the board reach a fixed point within " else "what is the stabilization time of the board within ") ++ generationsText n
questionText (CountReaches c target n) = "does the count of cells matching " ++ conditionText predicateText c ++ " reach " ++ show target ++ " within " ++ generationsText n
sentenceText :: Sentence -> String
sentenceText (Command c) = commandText c ++ "."
sentenceText (Question q) = questionText q ++ "?"
entryText :: Entry -> String
entryText Undo = "undo."
entryText (Sequence xs) = intercalate " " (map sentenceText xs)
entryText (Batch xs) = "atomically { " ++ intercalate " " [commandText c ++ "." | c <- xs] ++ " }."

module Domains.Cellular.Language.Syntax where

import Domains.Cellular.Types
import Ontology (Position)

data Condition a = Atom a | Not (Condition a) | And (Condition a) (Condition a) | Or (Condition a) (Condition a)
  deriving (Eq, Ord, Read, Show)
data Reference = Cell Position | It | WithColor Color | Matching Bool (Condition CellPredicate) | Relative String Reference
  deriving (Eq, Ord, Read, Show)
data CellPredicate = Always | ColorIs Color | RowIs Int | ColumnIs Int | SameCell Reference
  | SameColor Reference | NeighborOf Reference | ConnectedTo Reference | NeighborCount Color [Int] | Changes
  deriving (Eq, Ord, Read, Show)
data BoardPredicate = Monochromatic (Maybe Color) | FixedPoint deriving (Eq, Ord, Read, Show)
data Collection = Cells [Reference] | Filter (Condition CellPredicate) | Component Reference | Rectangle Position Position
  deriving (Eq, Read, Show)
data Transform = Rotation Int | Reflection Bool deriving (Eq, Read, Show)
data Command = Paint Collection Color | Advance Int | SetRule Color Rule | ClearRule Color | ToggleRule Color Bool
  | SetNeighborhood Neighborhood | ReplaceRuleset Ruleset Bool | Initialize
  | Copy Reference Reference | Exchange Reference Reference | ReplaceColors [(Reference,Color)]
  | Permute [(Reference,Reference)] | Shift Int Int | Spatial Collection Transform Position Position
  deriving (Eq, Read, Show)
data Metadata = Generation | Palette | NeighborhoodName | Revision | CompleteRuleset deriving (Eq, Read, Show)
data Question = ColorOf Reference | Check Reference (Condition CellPredicate) | Meta Metadata | RuleOf Color
  | Select Bool (Maybe Reference) (Condition CellPredicate) | Quantify Bool (Condition CellPredicate) (Condition CellPredicate)
  | CheckBoard (Condition BoardPredicate) | Transition Reference | Forecast Int Question | ReturnTime Int
  | FirstCell Int Reference (Condition CellPredicate) | FirstBoard Int (Condition BoardPredicate) | Stabilization Bool Int
  | CountReaches (Condition CellPredicate) Int Int
  deriving (Eq, Read, Show)
data Sentence = Command Command | Question Question deriving (Eq, Read, Show)
data Entry = Undo | Sequence [Sentence] | Batch [Command] deriving (Eq, Read, Show)

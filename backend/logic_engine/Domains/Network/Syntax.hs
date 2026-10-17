{-# LANGUAGE DeriveFoldable #-}
module Domains.Network.Syntax where

import Ontology
import Pretty

-- Kept independent of the shared Subject type to avoid coupling domain syntax
-- to reference resolution. Foldable lists explicit object operands in order.
data Port = North | East | South | West deriving (Eq, Ord, Show, Enum, Bounded)
data GraphRelation = Linked | Connected (Maybe ValueId) deriving (Eq, Show)
-- Literal squares need not contain objects. Only Existing operands participate
-- in reference resolution and pending clarification.
data ConnectionEndpoint subject = Square Position | Existing subject
  deriving (Eq, Show, Foldable)
data NetworkSentence subject
  = Rotate subject Bool | Reflect subject Bool | CopyPattern subject subject
  | LinkDirection subject Port Bool | LinkPair subject subject Bool
  | TrimUnmatched subject | ColorComponent subject ValueId
  | Connect (ConnectionEndpoint subject) (ConnectionEndpoint subject) (Maybe ValueId)
  | ConnectionCount subject | Distance subject subject | ComponentCount
  deriving (Eq, Show, Foldable)

portName :: Port -> String
portName port = case port of North -> "north"; East -> "east"; South -> "south"; West -> "west"

instance PrettyShow Port where pretty = portName
instance PrettyShow GraphRelation where
  pretty Linked = "linked to"
  pretty (Connected _) = "connected to"

instance PrettyShow subject => PrettyShow (ConnectionEndpoint subject) where
  pretty (Square position) = prettyPosition position
  pretty (Existing subject) = pretty subject

instance PrettyShow subject => PrettyShow (NetworkSentence subject) where
  pretty sentence = case sentence of
    Rotate subject clockwise -> "rotate " ++ pretty subject ++ if clockwise then " clockwise." else " counterclockwise."
    Reflect subject horizontal -> "flip " ++ pretty subject ++ if horizontal then " horizontally." else " vertically."
    CopyPattern subject target -> "make " ++ pretty subject ++ " the same pattern as " ++ pretty target ++ "."
    LinkDirection subject port connect -> (if connect then "link " else "disconnect ") ++ pretty subject ++ " " ++ pretty port ++ "."
    LinkPair subject target connect -> (if connect then "link " else "disconnect ") ++ pretty subject ++ (if connect then " to " else " from ") ++ pretty target ++ "."
    TrimUnmatched subject -> "remove unmatched ports from " ++ pretty subject ++ "."
    ColorComponent subject color -> "color the component of " ++ pretty subject ++ " " ++ pretty color ++ "."
    Connect subject target color -> "connect " ++ pretty subject ++ " to " ++ pretty target ++
      maybe "" ((" with " ++) . pretty) color ++ "."
    ConnectionCount subject -> "how many connections does " ++ pretty subject ++ " have?"
    Distance subject target -> "distance " ++ pretty subject ++ " to " ++ pretty target ++ "?"
    ComponentCount -> "how many components?"

module Layer2Syntax where

import Ontology
import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import AtomicSentence
import Pretty

data Subject = Reference ObjectReference | It
             | Indefinite [Property] | Definite [Property]
             deriving (Eq, Show)

data Direction = Up | Down | Leftward | Rightward deriving (Eq, Show)
data SpatialCheck = OnBoard | Has RemovableAttribute | NextTo | Same Attribute | Edge | Corner
  deriving (Eq, Show)
data ObjectFilter = Described [Property] | Neighboring Subject | AtEdge | InCorner
  deriving (Eq, Show)

instance PrettyShow Direction where
  pretty Up = "up"
  pretty Down = "down"
  pretty Leftward = "left"
  pretty Rightward = "right"

relativeName :: Direction -> String
relativeName Up = "above"
relativeName Down = "under"
relativeName Leftward = "left of"
relativeName Rightward = "right of"

instance PrettyShow ObjectFilter where
  pretty (Described properties) = unwords (map pretty properties)
  pretty (Neighboring subject) = "next to " ++ pretty subject
  pretty AtEdge = "at the edge"
  pretty InCorner = "in a corner"

spatialName :: SpatialCheck -> String
spatialName OnBoard = "on the board"
spatialName (Has attribute) = "have a " ++ pretty attribute
spatialName NextTo = "next to"
spatialName (Same attribute) = "have the same " ++ (if attribute == PositionAttribute then "square" else pretty attribute) ++ " as"
spatialName Edge = "at the edge"
spatialName Corner = "in a corner"

data Sentence = Attribution Subject [Property]
              | AttributeRemoval Subject RemovableAttribute
              | Removal Subject
              | Swapping Subject Subject
              | Deletion Subject
              | StepMove Subject Direction
              | RelativeMove Subject Direction Subject
              | NeighborMove Subject Subject
              | CopyAttribute Subject RemovableAttribute Subject
              | SpatialQuestion Subject SpatialCheck (Maybe Subject)
              | CountObjects ObjectFilter
              | CountSquares Bool
              | Quantified Bool [Property] [Property]
              | Check Subject Property
              | Query Attribute Subject
              deriving (Eq, Show)

instance PrettyShow Subject where
  pretty (Reference reference) = pretty reference
  pretty It = "it"
  pretty (Indefinite descriptors) = "a " ++ unwords (map pretty descriptors)
  pretty (Definite descriptors) = "the " ++ unwords (map pretty descriptors)

instance PrettyShow Sentence where
  pretty (Attribution subject properties) = pretty subject ++ " is " ++ unwords (map pretty properties) ++ "."
  pretty (AttributeRemoval subject attribute) = pretty subject ++ " remove " ++ pretty attribute ++ "."
  pretty (Removal subject) = "remove " ++ pretty subject ++ "."
  pretty (Swapping first second) = "swap " ++ pretty first ++ " and " ++ pretty second ++ "."
  pretty (Deletion subject) = "delete " ++ pretty subject ++ "."
  pretty (StepMove subject direction) = "move " ++ pretty subject ++ " " ++ pretty direction ++ "."
  pretty (RelativeMove subject direction target) = "move " ++ pretty subject ++ " " ++ relativeName direction ++ " " ++ pretty target ++ "."
  pretty (NeighborMove subject target) = "move " ++ pretty subject ++ " next to " ++ pretty target ++ "."
  pretty (CopyAttribute subject attribute target) = "make " ++ pretty subject ++ " the same " ++ pretty attribute ++ " as " ++ pretty target ++ "."
  pretty (SpatialQuestion subject relation target) = pretty subject ++ " " ++ spatialName relation ++ maybe "" ((" " ++) . pretty) target ++ "?"
  pretty (CountObjects predicate) = "how many objects are " ++ pretty predicate ++ "?"
  pretty (CountSquares occupied) = "how many squares are " ++ (if occupied then "occupied" else "empty") ++ "?"
  pretty (Quantified universal before after) = (if universal then "all " else "some ") ++ unwords (map pretty before) ++ " objects are " ++ unwords (map pretty after) ++ "?"
  pretty (Check subject property) = pretty subject ++ " is " ++ pretty property ++ "?"
  pretty (Query attribute subject) = pretty attribute ++ " of " ++ pretty subject ++ "?"

-- Compatibility conversion only: no description/pronoun resolution or compound
-- evaluation is attempted here. All descriptors and their order remain intact.
toAtomicSentence :: Sentence -> Maybe AtomicSentence
toAtomicSentence (Attribution (Reference reference) [property]) = Just (Performative (AP reference property))
toAtomicSentence (AttributeRemoval (Reference reference) attribute) = Just (Performative (RemoveAttribute reference attribute))
toAtomicSentence (Removal (Reference reference)) = Just (Performative (Remove reference))
toAtomicSentence (Swapping (Reference first) (Reference second)) = Just (Performative (Swap first second))
toAtomicSentence (Deletion (Reference reference)) = Just (Performative (Delete reference))
toAtomicSentence (Check (Reference reference) property) = Just (PropertyCheck (APC reference property))
toAtomicSentence (Query attribute (Reference reference)) = Just (PropertyQuery (APQ attribute reference))
toAtomicSentence _ = Nothing

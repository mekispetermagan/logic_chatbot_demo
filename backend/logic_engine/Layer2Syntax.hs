module Layer2Syntax where

import qualified Domains.Network.Syntax as Network
import Data.List (intercalate)
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
data SpatialCheck = OnBoard | Has RemovableAttribute | NextTo | Same Attribute | Edge | Corner | NetworkRelation Network.GraphRelation
  deriving (Eq, Show)
-- A quantified conjunction shares one bound object and fixed reference targets.
data QuantifiedPredicate = PropertyPredicate [Property]
                         | RelationPredicate SpatialCheck (Maybe Subject)
  deriving (Eq, Show)

predicateSubjects :: QuantifiedPredicate -> [Subject]
predicateSubjects (PropertyPredicate _) = []
predicateSubjects (RelationPredicate _ target) = maybe [] (:[]) target

instance PrettyShow QuantifiedPredicate where
  pretty (PropertyPredicate properties) = unwords (map pretty properties)
  pretty (RelationPredicate relation target) = spatialName relation ++ maybe "" ((" " ++) . pretty) target ++ relationSuffix relation

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
spatialName (NetworkRelation relation) = pretty relation
spatialName OnBoard = "on the board"
spatialName (Has attribute) = "have a " ++ pretty attribute
spatialName NextTo = "next to"
spatialName (Same attribute) = "have the same " ++ (if attribute == PositionAttribute then "square" else pretty attribute) ++ " as"
spatialName Edge = "at the edge"
spatialName Corner = "in a corner"

relationSuffix :: SpatialCheck -> String
relationSuffix (NetworkRelation (Network.Connected (Just color))) = " by a " ++ pretty color ++ " path"
relationSuffix _ = ""

data Sentence = Attribution Subject [Property]
              | AttributeRemoval Subject RemovableAttribute
              | Removal Subject
              | Swapping Subject Subject
              | Deletion Subject
              | ClearingWorld
              | StepMove Subject Direction
              | RelativeMove Subject Direction Subject
              | NeighborMove Subject Subject
              | CopyAttribute Subject RemovableAttribute Subject
              | SpatialQuestion Subject SpatialCheck (Maybe Subject)
              | CountObjects ObjectFilter
              | CountMatching [Property] [QuantifiedPredicate]
              | Network (Network.NetworkSentence Subject)
              | CountSquares Bool
              | Quantified Bool [Property] [QuantifiedPredicate]
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
  pretty ClearingWorld = "clear the world."
  pretty (StepMove subject direction) = "move " ++ pretty subject ++ " " ++ pretty direction ++ "."
  pretty (RelativeMove subject direction target) = "move " ++ pretty subject ++ " " ++ relativeName direction ++ " " ++ pretty target ++ "."
  pretty (NeighborMove subject target) = "move " ++ pretty subject ++ " next to " ++ pretty target ++ "."
  pretty (CopyAttribute subject attribute target) = "make " ++ pretty subject ++ " the same " ++ pretty attribute ++ " as " ++ pretty target ++ "."
  pretty (SpatialQuestion subject relation target) = pretty subject ++ " " ++ spatialName relation ++ maybe "" ((" " ++) . pretty) target ++ relationSuffix relation ++ "?"
  pretty (Network sentence) = pretty sentence
  pretty (CountMatching properties predicates) = "how many " ++ unwords (map pretty properties) ++
    (if null properties then "objects" else " objects") ++
    (if null predicates then "" else " are " ++ intercalate " and " (map pretty predicates)) ++ "?"
  pretty (CountObjects predicate) = "how many objects are " ++ pretty predicate ++ "?"
  pretty (CountSquares occupied) = "how many squares are " ++ (if occupied then "occupied" else "empty") ++ "?"
  pretty (Quantified universal before after) = (if universal then "every " else "some ") ++ unwords (map pretty before) ++ (if universal then " object is " else " objects are ") ++ intercalate " and " (map pretty after) ++ "?"
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

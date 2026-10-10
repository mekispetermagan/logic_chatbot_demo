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

data Sentence = Attribution Subject [Property]
              | Removal Subject
              | Swapping Subject Subject
              | Deletion Subject
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
  pretty (Removal subject) = "remove " ++ pretty subject ++ "."
  pretty (Swapping first second) = "swap " ++ pretty first ++ " and " ++ pretty second ++ "."
  pretty (Deletion subject) = "delete " ++ pretty subject ++ "."
  pretty (Check subject property) = pretty subject ++ " is " ++ pretty property ++ "?"
  pretty (Query attribute subject) = pretty attribute ++ " of " ++ pretty subject ++ "?"

-- Compatibility conversion only: no description/pronoun resolution or compound
-- evaluation is attempted here. All descriptors and their order remain intact.
toAtomicSentence :: Sentence -> Maybe AtomicSentence
toAtomicSentence (Attribution (Reference reference) [property]) = Just (Performative (AP reference property))
toAtomicSentence (Removal (Reference reference)) = Just (Performative (Remove reference))
toAtomicSentence (Swapping (Reference first) (Reference second)) = Just (Performative (Swap first second))
toAtomicSentence (Deletion (Reference reference)) = Just (Performative (Delete reference))
toAtomicSentence (Check (Reference reference) property) = Just (PropertyCheck (APC reference property))
toAtomicSentence (Query attribute (Reference reference)) = Just (PropertyQuery (APQ attribute reference))
toAtomicSentence _ = Nothing

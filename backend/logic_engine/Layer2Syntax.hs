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
  pretty (Check subject property) = pretty subject ++ " is " ++ pretty property ++ "?"
  pretty (Query attribute subject) = pretty attribute ++ " of " ++ pretty subject ++ "?"

-- Compatibility conversion only: no description/pronoun resolution or compound
-- evaluation is attempted here. All descriptors and their order remain intact.
toAtomicSentence :: Sentence -> Maybe AtomicSentence
toAtomicSentence (Attribution (Reference reference) [property]) = Just (Performative (AP reference property))
toAtomicSentence (Check (Reference reference) property) = Just (PropertyCheck (APC reference property))
toAtomicSentence (Query attribute (Reference reference)) = Just (PropertyQuery (APQ attribute reference))
toAtomicSentence _ = Nothing

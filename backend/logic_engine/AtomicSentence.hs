module AtomicSentence where

import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import Pretty

data AtomicSentence = Performative AtomicPerformative
                    | PropertyCheck AtomicPropertyCheck
                    | PropertyQuery AtomicPropertyQuery
                    deriving (Eq, Show)

instance PrettyShow AtomicSentence where
  pretty (Performative performative) = pretty performative
  pretty (PropertyCheck propertyCheck) = pretty propertyCheck
  pretty (PropertyQuery propertyQuery) = pretty propertyQuery

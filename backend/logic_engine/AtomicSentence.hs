module AtomicSentence where

import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import AtomicSquareCheck
import Pretty

data AtomicSentence = Performative AtomicPerformative
                    | PropertyCheck AtomicPropertyCheck
                    | PropertyQuery AtomicPropertyQuery
                    | SquareCheck AtomicSquareCheck
                    deriving (Eq, Show)

instance PrettyShow AtomicSentence where
  pretty (Performative performative) = pretty performative
  pretty (PropertyCheck propertyCheck) = pretty propertyCheck
  pretty (PropertyQuery propertyQuery) = pretty propertyQuery
  pretty (SquareCheck squareCheck) = pretty squareCheck

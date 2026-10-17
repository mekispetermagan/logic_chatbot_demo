module AtomicSquareCheck where

import Domain
import Domains.Objects.Definition (objectsDomain)
import Ontology
import Pretty
import Result

newtype AtomicSquareCheck = ASC { squarePosition :: Position }
  deriving (Eq, Show)

instance PrettyShow AtomicSquareCheck where
  pretty (ASC position) = "is the square " ++ prettyPosition position ++ " occupied?"

evaluateAtomicSquareCheckWith :: Domain -> World -> AtomicSquareCheck -> Result Bool
evaluateAtomicSquareCheckWith domain (World objects) (ASC position)
  | not (inDomainBounds domain position) = Message "Outside board"
  | otherwise = Result (any ((== Just position) . positionOf) objects)

evaluateAtomicSquareCheck :: World -> AtomicSquareCheck -> Result Bool
evaluateAtomicSquareCheck = evaluateAtomicSquareCheckWith objectsDomain

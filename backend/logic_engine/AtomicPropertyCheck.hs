module AtomicPropertyCheck where

import Domain
import Domains.Objects.Definition (objectsDomain)
import Ontology
import Pretty
import Result
import ReferenceResolution

data AtomicPropertyCheck = APC
                        { checkSubject :: ObjectReference
                        , checkPropPart :: Property
                        }
                        deriving (Eq, Show)

instance PrettyShow AtomicPropertyCheck where
  pretty (APC identifier property) =
    pretty identifier ++ " " ++ pretty property ++ "?"

evaluateAtomicPropertyCheckWith :: Domain -> World -> AtomicPropertyCheck -> Result Bool
evaluateAtomicPropertyCheckWith domain world (APC identifier property)
  | not (validProperty domain property) = Message "Invalid property"
  | otherwise = case resolveReference world identifier of
    Message message -> Message message
    Result object -> Result (holdsProperty object property)

-- Current-domain convenience entry points.
evaluateAtomicPropertyCheck :: World -> AtomicPropertyCheck -> Result Bool
evaluateAtomicPropertyCheck = evaluateAtomicPropertyCheckWith objectsDomain

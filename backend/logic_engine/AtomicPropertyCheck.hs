module AtomicPropertyCheck where

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

evaluateAtomicPropertyCheck :: World -> AtomicPropertyCheck -> Result Bool
evaluateAtomicPropertyCheck world (APC identifier property) =
  case resolveReference world identifier of
    Message message -> Message message
    Result object -> Result $ case property of
      C color -> colorOf object == Just color
      S size -> sizeOf object == Just size
      Sh shape -> shapeOf object == Just shape
      P position -> positionOf object == Just position

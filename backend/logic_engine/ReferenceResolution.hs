module ReferenceResolution where

import Ontology
import Pretty
import Result

-- Questions resolve without creation, and never select an ambiguous referent.
resolveReference :: World -> ObjectReference -> Result Object
resolveReference (World objects) reference = case filter matches objects of
  [] -> Message ("No object at " ++ pretty reference)
  [object] -> Result object
  _ -> Message ("Ambiguous " ++ pretty reference)
  where
    matches object = case reference of
      ById identifier -> idOf object == identifier
      AtSquare position -> positionOf object == Just position

-- Creation is part of performative resolution, before property validation.
resolvePerformativeReference :: World -> ObjectReference -> Result (World, Object, Bool)
resolvePerformativeReference world@(World objects) reference =
  case filter matches objects of
    [] -> case reference of
      AtSquare position | not (inBounds position) -> Message "Outside board"
      _ -> let object = case reference of
                 ById identifier -> emptyObject identifier
                 AtSquare position -> (emptyObject (nextId world)) { positionOf = Just position }
           in Result (World (object : objects), object, True)
    [object] -> Result (world, object, False)
    _ -> Message ("Ambiguous " ++ pretty reference)
  where
    matches object = case reference of
      ById identifier -> idOf object == identifier
      AtSquare position -> positionOf object == Just position

inBounds :: Position -> Bool
inBounds (x, y) = x >= 0 && x < 8 && y >= 0 && y < 8

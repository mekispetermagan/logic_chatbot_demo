module ReferenceResolution where

import Domain
import Domains.Objects.Definition (objectsDomain)
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
resolvePerformativeReferenceWith :: Domain -> World -> ObjectReference -> Result (World, Object, Bool)
resolvePerformativeReferenceWith domain world@(World objects) reference =
  case filter matches objects of
    [] -> case reference of
      AtSquare position | not ((inBoundsWith domain) position) -> Message "Outside board"
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

inBoundsWith :: Domain -> Position -> Bool
inBoundsWith domain = inDomainBounds domain

-- Current-domain convenience entry points.
resolvePerformativeReference :: World -> ObjectReference -> Result (World, Object, Bool)
resolvePerformativeReference = resolvePerformativeReferenceWith objectsDomain
inBounds :: Position -> Bool
inBounds = inBoundsWith objectsDomain

module WorldEditor where

import AtomicPerformative
import Ontology
import Pretty
import ReferenceResolution
import Result

data EditorAction = ApplyProperty Position Property
                  | PlaceObject Identifier Position
                  | EraseSquare Position
                  | ClearWorld
                  deriving (Eq, Show)

-- Visual edits share atomic performative semantics; placement never creates.
evaluateEditorAction :: World -> EditorAction -> (World, String)
evaluateEditorAction world action = case action of
  ApplyProperty position property
    | not (inBounds position) -> (world, "Outside board")
    | otherwise -> let (updated, feedback) =
                        evaluateAtomicPerformative world (AP (AtSquare position) property)
                   in (updated, case feedback of
                        Result change -> pretty change
                        Message message -> message)
  PlaceObject identifier position
    | not (inBounds position) -> (world, "Outside board")
    | otherwise -> case resolveReference world (ById identifier) of
        Message message -> (world, message)
        Result object -> case positionOf object of
          Just _ -> (world, pretty identifier ++ " already placed")
          Nothing -> let (updated, feedback) =
                           evaluateAtomicPerformative world (AP (ById identifier) (P position))
                     in (updated, case feedback of
                          Result change -> pretty change
                          Message message -> message)
  EraseSquare position
    | not (inBounds position) -> (world, "Outside board")
    | otherwise -> case resolveReference world (AtSquare position) of
        Message _ -> (world, "No change")
        Result object -> let World objects = world
                         in (World (filter ((/= idOf object) . idOf) objects),
                             "Erased " ++ pretty (idOf object))
  ClearWorld -> case world of
    World [] -> (world, "No change")
    _ -> (World [], "World cleared")

module WorldEditor where

import qualified Data.Map.Strict as Map
import AtomicPerformative
import Domain
import Domains.Objects.Definition (objectsDomain)
import Ontology
import Pretty
import ReferenceResolution
import Result

data EditorAction = ApplyProperty Position Property
                  | ReplaceAttributes Position [AttributeId] [Property]
                  | PlaceObject Identifier Position
                  | EraseSquare Position
                  | ClearWorld
                  deriving (Eq, Show)

-- Visual edits share atomic performative semantics; placement never creates.
evaluateEditorActionWith :: Domain -> World -> EditorAction -> (World, String)
evaluateEditorActionWith domain world action = case action of
  ApplyProperty position property
    | not ((inBoundsWith domain) position) -> (world, "Outside board")
    | otherwise -> let (updated, feedback) =
                        (evaluateAtomicPerformativeWith domain) world (AP (AtSquare position) property)
                   in (updated, case feedback of
                        Result change -> pretty change
                        Message message -> message)
  ReplaceAttributes position names properties
    | not (inBoundsWith domain position) -> (world, "Outside board")
    | any (`notElem` map attributeId (domainAttributes domain)) names ||
      any (\property -> not (validProperty domain property) || case property of
             AttributeValue name _ -> name `notElem` names; _ -> True) properties -> (world, "Invalid attributes")
    | otherwise ->
        let (placed, _) = evaluateAtomicPerformativeWith domain world (AP (AtSquare position) (P position))
        in case resolveReference placed (AtSquare position) of
          Message message -> (world, message)
          Result target ->
            let stripped = foldr Map.delete (attributesOf target) names
                stored = foldr (\property attrs -> case property of AttributeValue name value -> Map.insert name value attrs; _ -> attrs) stripped properties
                updated = target {attributesOf = stored}
                World objects = placed
                result = World [if idOf item == idOf target then updated else item | item <- objects]
            in (result, if result == world then "No change" else "Updated " ++ pretty (idOf target))
  PlaceObject identifier position
    | not ((inBoundsWith domain) position) -> (world, "Outside board")
    | otherwise -> case resolveReference world (ById identifier) of
        Message message -> (world, message)
        Result object -> case positionOf object of
          Just _ -> (world, pretty identifier ++ " already placed")
          Nothing -> let (updated, feedback) =
                           (evaluateAtomicPerformativeWith domain) world (AP (ById identifier) (P position))
                     in (updated, case feedback of
                          Result change -> pretty change
                          Message message -> message)
  EraseSquare position
    | not ((inBoundsWith domain) position) -> (world, "Outside board")
    | otherwise -> case resolveReference world (AtSquare position) of
        Message _ -> (world, "No change")
        Result object -> let World objects = world
                         in (World (filter ((/= idOf object) . idOf) objects),
                             "Erased " ++ pretty (idOf object))
  ClearWorld -> case world of
    World [] -> (world, "No change")
    _ -> (World [], "World cleared")

-- Current-domain convenience entry points.
evaluateEditorAction :: World -> EditorAction -> (World, String)
evaluateEditorAction = evaluateEditorActionWith objectsDomain

module Domains.Network.Evaluation where

import Data.List (find)
import Ontology
import Pretty
import Domain
import DomainLibrary
import Layer2Syntax
import Discourse (subjectsOf, descriptorsOf)
import AtomicPerformative
import AtomicEvaluation
import AtomicSentence
import qualified Domains.Objects.Evaluation as Core
import Domains.Network.Definition
import Domains.Network.Patterns
import Domains.Network.Graph
import qualified Domains.Network.Pathfinding as Pathfinding
import qualified Domains.Network.Syntax as N

networkSpatial :: World -> SpatialCheck -> Object -> Maybe Object -> (Bool, String)
networkSpatial world (NetworkRelation relation) object target = (case target of
  Nothing -> False
  Just other -> case relation of
    N.Linked -> any ((== idOf other) . idOf) (neighbors world object)
    N.Connected color -> distance world color object other /= Nothing, "")
networkSpatial _ relation object target = Core.spatialTruthWith networkDomain relation object target

evaluateNetwork :: World -> [Identifier] -> Sentence -> Maybe Position -> Maybe DerivedResult
evaluateNetwork world@(World objects) identifiers sentence chosen = case sentence of
  Attribution subject properties | any defined (descriptorsOf subject ++ properties) -> unary $ \object ->
    let initial = case subject of Indefinite descriptors -> descriptors; _ -> []
        step (current, answers) property = case property of
          Defined name -> case patternPorts name of
            Nothing -> (current, answers ++ ["Pattern cannot be assigned"])
            Just (selected,exact) ->
              let before = objectIn current (idOf object)
                  after = setPorts (if exact then selected else filter (\port -> port `elem` selected || hasPort before port) ports) before
                  updated = replace current [after]
              in (updated, answers ++ [changeMessage before after])
          _ -> let (updated, feedback) = evaluateAtomicSentenceWith networkDomain current (Performative (AP (ById (idOf object)) property))
               in (updated, answers ++ [pretty (feedbackAnswer feedback)])
        (updated, feedback) = foldl step (world,[]) (initial ++ properties)
    in finish updated feedback [descriptorsOf subject ++ properties]
  Check subject property@(Defined _) -> unary $ \object ->
    finish world [if networkHolds world object property then "true" else "false"] [descriptorsOf subject ++ [property]]
  Network operation -> case operation of
    N.Connect source target color -> Just (connection source target color)
    N.Rotate _ clockwise -> unary $ \object -> changePorts object
      [toEnum ((fromEnum port + if clockwise then 1 else 3) `mod` 4) | port <- openPorts object]
    N.Reflect _ horizontal -> unary $ \object -> changePorts object
      [if (horizontal && port `elem` [N.East,N.West]) || (not horizontal && port `elem` [N.North,N.South])
        then opposite port else port | port <- openPorts object]
    N.CopyPattern _ _ -> binary $ \object target -> changePorts object (openPorts target)
    N.LinkDirection _ port connect -> unary $ \object -> case positionOf object of
      Nothing -> unchanged "Object is not on the board"
      Just position -> directionalLink object port (shiftPort port position) connect
    N.LinkPair _ _ connect -> binary $ \object target -> case (positionOf object, positionOf target) of
      (Just source, Just destination) -> case find (\port -> shiftPort port source == destination) ports of
        Nothing -> unchanged "Objects are not adjacent"
        Just port -> linkObjects object target port connect world
      _ -> unchanged "Object is not on the board"
    N.TrimUnmatched _ -> unary $ \object -> case positionOf object of
      Nothing -> unchanged "Object is not on the board"
      Just _ -> changePorts object (filter (`notElem` unmatchedPorts world object) (openPorts object))
    N.ColorComponent _ color -> unary $ \object -> case positionOf object of
      Nothing -> unchanged "Object is not on the board"
      Just _ -> let group = component world object
                    updated = replace world [setAttribute (AttributeId "color") (Just color) item | item <- group]
                in finish updated [if updated == world then "No change" else "Colored " ++ show (length group) ++ " objects " ++ pretty color]
                  (associations updated)
    N.ConnectionCount _ -> unary $ \object -> onBoard object (show (length (neighbors world object)))
    N.Distance _ _ -> binary $ \object target ->
      if positionOf object == Nothing || positionOf target == Nothing then unchanged "Object is not on the board"
      else unchanged (maybe "no path" show (distance world Nothing object target))
    N.ComponentCount -> Just (unchanged (show (length (components world))))
  _ -> Core.evaluateDerivedUsing networkDomain networkHolds (networkSpatial world) world identifiers sentence chosen
  where
    defined (Defined _) = True
    defined _ = False
    resolved = [object | identifier <- identifiers, object <- objects, idOf object == identifier]
    unary action = Just $ case resolved of [object] -> action object; _ -> unchanged "Expected one object"
    binary action = Just $ case resolved of [object,target] -> action object target; _ -> unchanged "Expected two objects"
    finish updated feedback associated = DerivedComplete updated feedback associated
    associations updated = [descriptorsOf subject ++
      case sentence of
        Network (N.ColorComponent _ _) -> maybe [] (\value -> [AttributeValue (AttributeId "color") value]) (attributeOf (AttributeId "color") item)
        Network operation | mutates operation -> portMentions item
        _ -> []
      | (identifier,subject) <- zip identifiers (subjectsOf sentence),
        item <- worldObjects updated, idOf item == identifier]
    portMentions item = map portProperty (openPorts item)
    mutates operation = case operation of
      N.ConnectionCount _ -> False; N.Distance _ _ -> False; N.ComponentCount -> False; _ -> True
    unchanged message = finish world [message] (associations world)
    changePorts object selected = let after = setPorts selected object
                                 in finish (replace world [after]) [changeMessage object after] (associations (replace world [after]))
    onBoard object message = unchanged (if positionOf object == Nothing then "Object is not on the board" else message)
    connection source target color = case endpoints [source,target] identifiers of
      Nothing -> DerivedCompleteWithMentions world ["Invalid connection endpoints"] []
      Just references -> case [position | (_,_,position) <- references] of
        [Just from, Just to] -> case Pathfinding.createConnection world from to color of
          Nothing -> connectionResult world "No path" references
          Just (updated,path) -> connectionResult updated
            (if updated == world then "No change" else
              "Connected " ++ prettyPosition from ++ " to " ++ prettyPosition to ++
              " (" ++ show (length path - 1) ++ " steps)") references
        _ -> connectionResult world "Object is not on the board" references
      where
        endpoints [] [] = Just []
        endpoints (N.Square position:rest) ids =
          ((Left position, [], Just position) :) <$> endpoints rest ids
        endpoints (N.Existing subject:rest) (identifier:ids) = do
          object <- find ((== identifier) . idOf) objects
          ((Right identifier, descriptorsOf subject, positionOf object) :) <$> endpoints rest ids
        endpoints _ _ = Nothing
        connectionResult updated@(World updatedObjects) message references =
          DerivedCompleteWithMentions updated [message]
            [(idOf object, properties ++ [P position | Just position <- [positionOf object]] ++
                [AttributeValue (AttributeId "color") value | Just value <- [color]])
            | (reference,properties,_) <- references
            , Just object <- [case reference of
                Left position -> atPosition updated position
                Right identifier -> find ((== identifier) . idOf) updatedObjects]]
    directionalLink object port destination connect
      | connect && not (inDomainBounds networkDomain destination) = unchanged "Outside board"
      | otherwise = case atPosition world destination of
          Just target -> linkObjects object target port connect world
          Nothing | not connect -> changePorts object (filter (/= port) (openPorts object))
          Nothing -> let target = (emptyObject (nextId world)) {positionOf = Just destination}
                         colored = setAttribute (AttributeId "color") (attributeOf (AttributeId "color") object) target
                         created = World (colored : objects)
                     in linkObjects object colored port True created
    linkObjects object target port connect initial =
      let adjust item direction = setPorts
            (filter (\p -> p /= direction || connect) (openPorts item ++ [direction | connect, not (hasPort item direction)])) item
          updated = replace initial [adjust object port, adjust target (opposite port)]
      in finish updated [if updated == world then "No change" else (if connect then "Linked " else "Disconnected ") ++ pretty (idOf object) ++ " and " ++ pretty (idOf target)] (associations updated)

worldObjects :: World -> [Object]
worldObjects (World objects) = objects

-- Callers resolve operands before mutation; replacements preserve stable identities.
replace :: World -> [Object] -> World
replace (World objects) changes = World [maybe object id (find ((== idOf object) . idOf) changes) | object <- objects]

objectIn :: World -> Identifier -> Object
objectIn (World objects) identifier = case find ((== identifier) . idOf) objects of
  Just object -> object
  Nothing -> emptyObject identifier

changeMessage :: Object -> Object -> String
changeMessage before after
  | before == after = "No change"
  | otherwise = pretty (idOf after) ++ ": " ++ patternName before ++ " -> " ++ patternName after
  where patternName object = [if hasPort object port then "nesw" !! fromEnum port else '-' | port <- ports]

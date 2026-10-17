module Domains.Network.Graph where

import Data.List (find)
import qualified Data.Set as Set
import Ontology
import Domains.Network.Patterns
import Domains.Network.Syntax

atPosition :: World -> Position -> Maybe Object
atPosition (World objects) position = find ((== Just position) . positionOf) objects

neighbors :: World -> Object -> [Object]
neighbors world object = case positionOf object of
  Nothing -> []
  Just position -> [target | port <- openPorts object,
    Just target <- [atPosition world (shiftPort port position)], hasPort target (opposite port)]

unmatchedPorts :: World -> Object -> [Port]
unmatchedPorts world object = case positionOf object of
  Nothing -> []
  Just position -> [port | port <- openPorts object,
    maybe True (not . (`hasPort` opposite port)) (atPosition world (shiftPort port position))]

distance :: World -> Maybe ValueId -> Object -> Object -> Maybe Int
distance world color source target
  | positionOf source == Nothing || positionOf target == Nothing = Nothing
  | not (allowed source && allowed target) = Nothing
  | otherwise = search Set.empty [(source,0)]
  where
    allowed object = maybe True (\value -> attributeOf (AttributeId "color") object == Just value) color
    search _ [] = Nothing
    search visited ((object,steps):rest)
      | idOf object `Set.member` visited = search visited rest
      | idOf object == idOf target = Just steps
      | otherwise = search (Set.insert (idOf object) visited)
          (rest ++ [(neighbor,steps+1) | neighbor <- neighbors world object, allowed neighbor])

component :: World -> Object -> [Object]
component world object = walk Set.empty [object]
  where
    walk _ [] = []
    walk visited (current:rest)
      | positionOf current == Nothing || idOf current `Set.member` visited = walk visited rest
      | otherwise = current : walk (Set.insert (idOf current) visited) (neighbors world current ++ rest)

components :: World -> [[Object]]
components world@(World objects) = collect [object | object <- objects, positionOf object /= Nothing]
  where
    collect [] = []
    collect (object:rest) = let group = component world object
                          in group : collect [item | item <- rest, idOf item `notElem` map idOf group]

networkHolds :: World -> Object -> Property -> Bool
networkHolds world object (Defined name) = case intrinsic object name of
  Just result -> result
  Nothing | positionOf object == Nothing -> False
          | otherwise -> case name of
      "isolated" -> null (neighbors world object)
      "endpoint" -> length (neighbors world object) == 1
      "junction" -> length (neighbors world object) >= 3
      "unmatched" -> not (null (unmatchedPorts world object))
      _ -> False
networkHolds _ object property = holdsProperty object property

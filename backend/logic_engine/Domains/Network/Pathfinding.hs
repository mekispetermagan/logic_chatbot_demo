module Domains.Network.Pathfinding where

import Domains.Network.Definition
import Domain (inDomainBounds, boardWidth, boardHeight)
import Ontology
import Data.List (foldl')
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Domains.Network.Patterns as Pattern

type PositionIndex = Map.Map Position Object

-- Empty squares are virtual crosses during search. First discovery fixes the
-- predecessor, so ordered frontiers preserve north/east/south/west tie-breaking.
shortestConnectionPath :: World -> Position -> Position -> Maybe [Position]
shortestConnectionPath world source target
  | not (inDomainBounds networkDomain source && inDomainBounds networkDomain target) = Nothing
  | otherwise = search
                  (positionIndexOf $ saturate world)
                  (Set.singleton source)
                  [source]
                  Map.empty
  where
    search positionIndex visited frontier predecessors
      | target `elem` frontier = reconstruct predecessors target []
      | null frontier = Nothing
      | otherwise = search positionIndex newVisited (reverse nextReversed) newPredecessors
      where
        (newVisited, newPredecessors, nextReversed) =
          foldl' discoverFrom (visited, predecessors, []) frontier
        discoverFrom state current = foldl' (discover current) state (accessibleNeighbors positionIndex current)
        discover current state@(seen, previous, next) neighbor
          | Set.member neighbor seen = state
          | otherwise = (Set.insert neighbor seen, Map.insert neighbor current previous, neighbor : next)
    reconstruct predecessors current path
      | current == source = Just (source : path)
      | otherwise = do
          previous <- Map.lookup current predecessors
          reconstruct predecessors previous (current : path)

-- Plan first, then apply the whole route. Existing ports and identities survive;
-- an explicit color is the only permitted change to an existing object.
createConnection :: World -> Position -> Position -> Maybe ValueId -> Maybe (World, [Position])
createConnection world@(World objects) source target color = do
  path <- shortestConnectionPath world source target
  let original = positionIndexOf world
      pathSquares = Set.fromList path
      recolor object = case (color, positionOf object) of
        (Just value, Just position) | Set.member position pathSquares ->
          setAttribute (AttributeId "color") (Just value) object
        _ -> object
      segments = zip3 path (Nothing : map Just path) (map Just (drop 1 path) ++ [Nothing])
      addNode state@(identifier, created) (position, before, after)
        | Map.member position original = state
        | otherwise =
            let required = [port | port <- Pattern.ports, Just neighbor <- [before, after],
                                  Pattern.shiftPort port position == neighbor]
                object = (Pattern.setPorts required (emptyObject identifier)) {positionOf = Just position}
                colored = setAttribute (AttributeId "color") color object
            in (Id (idToInt identifier + 1), colored : created)
      (_, created) = foldl' addNode (nextId world, []) segments
  pure (World (map recolor objects ++ reverse created), path)


neighbors :: Position -> [(Position, AttributeId, AttributeId)]
neighbors (x,y) = [ ((x, y+1), AttributeId "north", AttributeId "south")
                  , ((x+1, y), AttributeId "east", AttributeId "west")
                  , ((x, y-1), AttributeId "south", AttributeId "north")
                  , ((x-1, y), AttributeId "west", AttributeId "east")
                  ]

accessibleNeighbors :: PositionIndex -> Position -> [Position]
accessibleNeighbors positionIndex p = [ p'
                                      | (p', a, a') <- neighbors p
                                      , hasPort positionIndex p a
                                      , hasPort positionIndex p' a' ]

hasPort :: PositionIndex -> Position -> AttributeId -> Bool
hasPort positionIndex pos attr = case Map.lookup pos positionIndex of
  Nothing     -> False
  Just obj    -> case Map.lookup attr (attributesOf obj) of
    Nothing     -> False
    Just _      -> True

saturate :: World -> World
saturate world =  World [ case objectAt world (x, y) of
                          Nothing   -> nesw (x, y)
                          Just obj  -> obj
                        | x <- [0 .. boardWidth networkDomain - 1], y <- [0 .. boardHeight networkDomain - 1] ]

positionIndexOf :: World -> PositionIndex
positionIndexOf (World objects) = Map.fromList [ (p, o)
                                               | o <- objects
                                               , Just p <- [positionOf o]]

objectAt :: World -> Position -> Maybe Object
objectAt (World []) _           = Nothing
objectAt (World (o:os)) p
  | positionOf o == Just p      = Just o
  | otherwise                   = objectAt (World os) p

nesw :: Position -> Object
nesw p = Object
  (Id (-1))
  (Map.fromList
    [ (AttributeId "north", ValueId "north")
    , (AttributeId "east",  ValueId "east")
    , (AttributeId "south",  ValueId "south")
    , (AttributeId "west",  ValueId "west")
    ])
  (Just p)

node :: Int -> String -> [String] -> Position -> Object
node identifier color ports position = Object
  (Id identifier)
  (Map.fromList ((AttributeId "color", ValueId color) :
    [(AttributeId port, ValueId port) | port <- ports]))
  (Just position)

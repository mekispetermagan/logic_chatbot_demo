module Domains.Network.Analysis where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Ontology
import qualified Domains.Network.Graph as G
import qualified Domains.Network.Patterns as P

type Link = (Identifier,Identifier)
placed :: World -> World
placed (World os) = World [o | o <- os, positionOf o /= Nothing]
objects :: World -> [Object]
objects (World os) = os
contains :: World -> Object -> Bool
contains (World os) o = any ((== idOf o) . idOf) os
links :: World -> [Link]
links w = [(idOf o,idOf n) | o <- objects w, n <- G.neighbors w o, idOf o < idOf n]
remove :: World -> Identifier -> World
remove (World os) identifier = World (filter ((/= identifier) . idOf) os)
shortestPath :: World -> Object -> Object -> Maybe [Identifier]
shortestPath w source target
  | not (contains w source && contains w target) = Nothing
  | otherwise = walk (Set.singleton (idOf source)) [source] Map.empty
  where
    walk _ [] _ = Nothing
    walk seen (o:rest) previous
      | idOf o == idOf target = Just (reverse (trace previous (idOf target)))
      | otherwise = let next = [n | n <- G.neighbors w o, Set.notMember (idOf n) seen]
                        updated = foldr (\n -> Map.insert (idOf n) (idOf o)) previous next
                    in walk (foldr (Set.insert . idOf) seen next) (rest ++ next) updated
    trace previous n = n : maybe [] (trace previous) (Map.lookup n previous)
isForest :: World -> Bool
isForest w = length (links w) == length (objects w) - length (G.components w)
isTree :: World -> Bool
isTree w = not (null (objects w)) && length (G.components w) == 1 && isForest w
isArticulation :: World -> Object -> Bool
isArticulation w o = contains w o && length (G.components (remove w (idOf o))) > length (G.components w)
onCycle :: World -> Object -> Bool
onCycle w o = contains w o && or
  [shortestPath (remove w (idOf o)) a b /= Nothing | a <- neighbors, b <- neighbors, idOf a < idOf b]
  where neighbors = G.neighbors w o
withoutLink :: World -> Object -> Object -> World
withoutLink (World os) a b = World [adjust o | o <- os]
  where
    adjust o | idOf o == idOf a = closeToward o b
             | idOf o == idOf b = closeToward o a
             | otherwise = o
    closeToward o other = P.setPorts [p | p <- P.openPorts o, fmap (P.shiftPort p) (positionOf o) /= positionOf other] o
isBridge :: World -> Object -> Object -> Bool
isBridge w a b = length (G.components (withoutLink w a b)) > length (G.components w)
monochromatic :: World -> Maybe String -> Bool
monochromatic w hue = case map (attributeOf (AttributeId "color")) (objects w) of
  Just first:rest -> all (== Just first) rest && maybe True ((== first) . ValueId) hue
  _ -> False
properlyColored :: World -> Bool
properlyColored w = all ((/= Nothing) . attributeOf (AttributeId "color")) (objects w) &&
  and [attributeOf (AttributeId "color") a /= attributeOf (AttributeId "color") b | a <- objects w, b <- G.neighbors w a]
graphProperty :: String -> Maybe String -> World -> Bool
graphProperty name hue w = case name of
  "connected" -> not (null (objects w)) && length (G.components w) == 1
  "tree" -> isTree w
  "forest" -> isForest w
  "cyclic" -> not (isForest w)
  "monochromatic" -> monochromatic w hue
  "properly colored" -> properlyColored w
  _ -> False
role :: String -> World -> Object -> Bool
role name w o = case P.intrinsic o name of
  Just result -> result
  Nothing | not (contains w o) -> False
  Nothing -> case name of
    "isolated" -> null (G.neighbors w o)
    "endpoint" -> length (G.neighbors w o) == 1
    "junction" -> length (G.neighbors w o) >= 3
    "unmatched" -> not (null (G.unmatchedPorts w o))
    "on a cycle" -> onCycle w o
    "articulation" -> isArticulation w o
    _ -> False

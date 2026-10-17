module Domains.Network.Patterns where

import Data.List (subsequences)
import qualified Data.Map.Strict as Map
import Domain
import Ontology
import Domains.Network.Syntax

ports :: [Port]
ports = [minBound .. maxBound]

portProperty :: Port -> Property
portProperty port = AttributeValue (AttributeId (portName port)) (ValueId (portName port))

hasPort :: Object -> Port -> Bool
hasPort object port = holdsProperty object (portProperty port)

openPorts :: Object -> [Port]
openPorts object = filter (hasPort object) ports

setPorts :: [Port] -> Object -> Object
setPorts selected object = object {attributesOf = foldr
  (\port attrs -> if port `elem` selected then Map.insert (AttributeId (portName port)) (ValueId (portName port)) attrs
                 else Map.delete (AttributeId (portName port)) attrs) (attributesOf object) ports}

opposite :: Port -> Port
opposite port = toEnum ((fromEnum port + 2) `mod` 4)

shiftPort :: Port -> Position -> Position
shiftPort port (x,y) = case port of
  North -> (x,y+1); East -> (x+1,y); South -> (x,y-1); West -> (x-1,y)

patternDefinitions :: [DefinedDescriptor]
patternDefinitions =
  [DefinedDescriptor name aliases False | (name,aliases) <-
    [("dot",["empty"]),("tip",[]),("straight",[]),("bend",[]),("tee",[]),("cross",[]),
     ("isolated",[]),("endpoint",["dead-end"]),("junction",[]),("unmatched",[])]] ++
  [DefinedDescriptor (letters selected) [aliases selected] True
    | selected <- drop 1 (subsequences ports)] ++
  [DefinedDescriptor (exact selected "nesw") [exact selected "urdl"] True
    | selected <- subsequences ports]
  where
    letters selected = ["nesw" !! fromEnum port | port <- selected]
    aliases selected = ["urdl" !! fromEnum port | port <- selected]
    exact selected alphabet = [if port `elem` selected then alphabet !! fromEnum port else '-' | port <- ports]

-- Canonical positive shorthand adds ports; four slots specify presence/absence.
patternPorts :: String -> Maybe ([Port], Bool)
patternPorts name
  | length name == 4 && and [c == '-' || c == "nesw" !! fromEnum port | (port,c) <- zip ports name]
    = Just ([port | (port,c) <- zip ports name, c /= '-'], True)
  | name `elem` [["nesw" !! fromEnum port | port <- selected] | selected <- drop 1 (subsequences ports)]
    = Just ([port | port <- ports, "nesw" !! fromEnum port `elem` name], False)
  | otherwise = Nothing

intrinsic :: Object -> String -> Maybe Bool
intrinsic object name = case patternPorts name of
  Just (selected, exact) -> Just (if exact then selected == opened else all (`elem` opened) selected)
  Nothing -> case name of
    "dot" -> Just (null opened)
    "tip" -> Just (length opened == 1)
    "straight" -> Just (length opened == 2 && all ((`elem` opened) . opposite) opened)
    "bend" -> Just (length opened == 2 && not (all ((`elem` opened) . opposite) opened))
    "tee" -> Just (length opened == 3)
    "cross" -> Just (length opened == 4)
    _ -> Nothing
  where opened = openPorts object

-- Positive shorthand is a conjunction of ordinary mentions. Exact patterns also
-- retain their negative information as a computed fact, purged if it becomes false.
expandMention :: Property -> [Property]
expandMention property@(Defined name) = case patternPorts name of
  Just (selected,exact) -> [property | exact] ++ map portProperty selected
  Nothing -> [property]
expandMention property = [property]

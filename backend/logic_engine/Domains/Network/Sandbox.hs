module Domains.Network.Sandbox where

import qualified Data.Map.Strict as Map
import Ontology
import Layer2Parser (parseSentencesWith)
import Layer2Syntax (Sentence)
import Domains.Network.Library

-- A fixed random sample: stable identities and distinct squares across runs.
-- Ports are independent; dangling and outward-facing ports are permitted.
networkWorld :: World
networkWorld = World
  [ node 0 "red"    ["north", "east"] (0,0)
  , node 1 "blue"   ["south", "west"] (1,0)
  , node 2 "green"  ["north", "south"] (3,2)
  , node 3 "yellow" ["east", "west"] (6,4)
  , node 4 "red"    ["north", "east", "south", "west"] (2,6)
  , node 5 "green"  [] (7,7)
  , node 6 "blue"   ["west"] (5,3)
  ]
  where
    node identifier color ports position = Object (Id identifier)
      (Map.fromList ((AttributeId "color", ValueId color) :
        [(AttributeId port, ValueId port) | port <- ports])) (Just position)

networkIntroduction :: Either String [Sentence]
networkIntroduction = parseSentencesWith networkLibrary
  "A1 up. A1 north? A1 remove up. A1 north? The red east is blue. It west. color of it?"

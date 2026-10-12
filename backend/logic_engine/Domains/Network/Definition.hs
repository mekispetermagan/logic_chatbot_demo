module Domains.Network.Definition where

import Domain
import Ontology

networkDomain :: Domain
networkDomain = Domain "network" 8 8
  [ AttributeDefinition (AttributeId "color") []
      [ValueDefinition (ValueId color) [] | color <- ["blue", "green", "red", "yellow"]]
  , port "north" "up"
  , port "east" "right"
  , port "south" "down"
  , port "west" "left"
  ]
  where
    port name alias = AttributeDefinition (AttributeId name) [alias]
      [ValueDefinition (ValueId name) [alias]]

module Domains.Objects.Definition where

import Domain
import Ontology

objectsDomain :: Domain
objectsDomain = Domain "objects" 8 8
  [ finite "color" [("blue",[]),("green",[]),("red",[]),("yellow",[])]
  , finite "size" [("small",[]),("medium",[]),("large",[])]
  , finite "shape" [("bloom",["flower"]),("spark",["star"]),("drop",["tear"]),("loop",["ring"])]
  ]
  where finite name values = AttributeDefinition (AttributeId name) []
          [ValueDefinition (ValueId value) aliases | (value,aliases) <- values]

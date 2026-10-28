module Domains.Network.Language.Examples (examples) where

import ControlledLanguage.Example (ExamplePart(..), ExampleSections)

-- Static concrete examples; reference spans are explicit structured parts.
examples :: ExampleSections
examples =
  [ ("Primitive commands",
      [ [Plain "Create object with color red and pattern ne-- on ", Reference "C4", Plain "."]
      , [Plain "Set color of ", Reference "the object at C4", Plain " to blue."]
      , [Plain "Open north port of ", Reference "the object with color red", Plain "."]
      , [Plain "Close east port of ", Reference "it", Plain "."]
      , [Plain "Move ", Reference "it", Plain " to ", Reference "B2", Plain "."]
      , [Plain "Delete ", Reference "the object at C4", Plain "."]
      ])
  , ("Primitive questions",
      [ [Plain "Does ", Reference "#3", Plain " exist?"]
      , [Plain "What is the color of ", Reference "#3", Plain "?"]
      , [Plain "What is the pattern of ", Reference "it", Plain "?"]
      , [Plain "Does ", Reference "#3", Plain " satisfy north port is present and west port is absent?"]
      , [Plain "Does ", Reference "D4", Plain " satisfy not occupied?"]
      ])
  , ("Conceptual commands",
      [ [Plain "Link ", Reference "#3", Plain " to ", Reference "it", Plain "."]
      , [Plain "Unlink ", Reference "the object at C4", Plain " from ", Reference "#4", Plain "."]
      , [Plain "Extend ", Reference "the object with color red", Plain " north."]
      , [Plain "Copy pattern from ", Reference "it", Plain " to ", Reference "#4", Plain "."]
      , [Plain "Copy appearance from ", Reference "it", Plain " to ", Reference "the object at C4", Plain "."]
      , [Plain "Build shortest connection from ", Reference "A1", Plain " to ", Reference "D1", Plain " with route color blue."]
      , [Plain "Build shortest connection from ", Reference "it", Plain " to ", Reference "the object at D4", Plain "."]
      ])
  , ("Conceptual questions",
      [ [Plain "Does ", Reference "the object at C4", Plain " satisfy connected to ", Reference "it", Plain "?"]
      , [Plain "What is the distance from ", Reference "it", Plain " to ", Reference "the object with color red", Plain "?"]
      , [Plain "Does the component of ", Reference "the object at C4", Plain " satisfy tree and monochromatic with color blue?"]
      , [Plain "Does ", Reference "the object at C4", Plain " satisfy connected to ", Reference "the object with color red", Plain " within the subgraph of the network induced by objects matching color is red?"]
      , [Plain "How many components in the subgraph of the network induced by objects matching color is blue?"]
      , [Plain "Which objects match articulation?"]
      , [Plain "Does every object matching color is red satisfy connected to ", Reference "the object with color red", Plain "?"]
      ])
  ]

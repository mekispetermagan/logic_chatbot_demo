module Domains.Objects.Language.Examples (examples) where

import ControlledLanguage.Example (ExamplePart(..), ExampleSections)

-- Static concrete examples; reference spans are explicit structured parts.
examples :: ExampleSections
examples =
  [ ("Primitive commands",
      [ [Plain "Create object with color red and shape bloom on ", Reference "C4", Plain "."]
      , [Plain "Create object off the board."]
      , [Plain "Set color of ", Reference "the object at C4", Plain " to blue."]
      , [Plain "Set size of ", Reference "it", Plain " to large."]
      , [Plain "Clear shape of ", Reference "the object at C4", Plain "."]
      , [Plain "Move ", Reference "#3", Plain " to ", Reference "A4", Plain "."]
      , [Plain "Delete ", Reference "the object at C4", Plain "."]
      ])
  , ("Primitive questions",
      [ [Plain "Does ", Reference "#3", Plain " exist?"]
      , [Plain "What is the color of ", Reference "it", Plain "?"]
      , [Plain "What is the position of ", Reference "#3", Plain "?"]
      , [Plain "Does ", Reference "A4", Plain " satisfy occupied?"]
      , [Plain "Does ", Reference "the object with shape bloom", Plain " satisfy color is red and shape is bloom?"]
      , [Plain "What is the shape of ", Reference "the object with color red", Plain "?"]
      ])
  , ("Conceptual commands",
      [ [Plain "Step ", Reference "the object at C4", Plain " north."]
      , [Plain "Move ", Reference "it", Plain " next to ", Reference "the object with color red", Plain "."]
      , [Plain "Copy color from ", Reference "#3", Plain " to ", Reference "the object with shape bloom", Plain "."]
      , [Plain "Transfer shape from ", Reference "it", Plain " to ", Reference "the object at C4", Plain "."]
      , [Plain "Exchange positions of ", Reference "it", Plain " and ", Reference "the object at C4", Plain "."]
      , [Plain "Exchange appearance of ", Reference "#3", Plain " and ", Reference "the object at C4", Plain "."]
      , [Plain "Set appearance of ", Reference "#3", Plain " to color red, size none, shape loop."]
      , [Plain "Clone appearance of ", Reference "it", Plain " into a new object on ", Reference "B3", Plain "."]
      , [Plain "Set color of objects matching shape is bloom to red."]
      , [Plain "Shift positions of objects at [", Reference "D4", Plain ", ", Reference "E4", Plain "] by east 0, north 1."]
      , [Plain "Rearrange positions by [", Reference "#3", Plain " to ", Reference "D5", Plain ", ", Reference "#4", Plain " to ", Reference "E5", Plain "]."]
      , [Plain "Rotate positions of objects at [", Reference "D4", Plain ", ", Reference "E4", Plain ", ", Reference "D5", Plain ", ", Reference "E5", Plain "] by 90 degrees clockwise about the center of rectangle ", Reference "D4", Plain " to ", Reference "E5", Plain "."]
      ])
  , ("Conceptual questions",
      [ [Plain "Which objects match color is red and shape is bloom?"]
      , [Plain "How many objects match next to ", Reference "the object with shape bloom", Plain " and size is large?"]
      , [Plain "Does every object matching color is red satisfy at the edge?"]
      , [Plain "Does some object matching shape is spark satisfy size is large and position is present?"]
      , [Plain "Which squares match (not occupied) and shading is light?"]
      , [Plain "How many squares match not occupied?"]
      ])
  ]

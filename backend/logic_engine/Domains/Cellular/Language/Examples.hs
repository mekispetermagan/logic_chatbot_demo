module Domains.Cellular.Language.Examples (examples) where

import ControlledLanguage.Example (ExamplePart(..), ExampleSections)

-- Static concrete examples; reference spans are explicit structured parts.
examples :: ExampleSections
examples =
  [ ("Primitive commands",
      [ [Plain "Set color of ", Reference "it", Plain " to black."]
      , [Plain "Set rule for black to target white, counts [0, 1, 2, 3, 4, 7, 8], enabled true."]
      , [Plain "Disable rule for white."]
      , [Plain "Advance 1 generation."]
      ])
  , ("Primitive questions",
      [ [Plain "What is the color of ", Reference "it", Plain "?"]
      , [Plain "Does ", Reference "the cell north of A16", Plain " satisfy color is black?"]
      , [Plain "What is the next transition of ", Reference "A1", Plain "?"]
      , [Plain "What is the palette?"]
      , [Plain "What is the generation?"]
      ])
  , ("Conceptual commands",
      [ [Plain "Set color of cells in rectangle ", Reference "A1", Plain " to ", Reference "P16", Plain " to white."]
      , [Plain "Set color of cells connected to ", Reference "the cell north of A16", Plain " to white."]
      , [Plain "Exchange color of ", Reference "the cell with color black", Plain " and ", Reference "B2", Plain "."]
      , [Plain "Copy color from ", Reference "A1", Plain " to ", Reference "B2", Plain "."]
      , [Plain "Replace colors by [", Reference "A1", Plain " to black, ", Reference "B2", Plain " to white]."]
      , [Plain "Permute colors by [", Reference "A1", Plain " to ", Reference "B2", Plain ", ", Reference "B2", Plain " to ", Reference "A1", Plain "]."]
      , [Plain "Shift colors of the board by east -1, north 2."]
      , [Plain "Rotate colors of cells in rectangle ", Reference "A1", Plain " to ", Reference "B2", Plain " by 90 degrees clockwise about the center of rectangle ", Reference "A1", Plain " to ", Reference "B2", Plain "."]
      , [Plain "Replace ruleset with preset rgb cycle, randomly refilling the board if required."]
      , [Plain "Initialize the board randomly."]
      ])
  , ("Conceptual questions",
      [ [Plain "How many neighbors of ", Reference "the cell with color black", Plain " match color is black?"]
      , [Plain "Does ", Reference "the cell north of A16", Plain " satisfy connected to ", Reference "it", Plain "?"]
      , [Plain "Does every cell matching color is black satisfy neighbor of ", Reference "A3", Plain "?"]
      , [Plain "Does the board satisfy fixed point?"]
      , [Plain "After 5 generations, which cells match color is black?"]
      , [Plain "What is the first generation offset within 20 generations at which ", Reference "A1", Plain " satisfies color is black?"]
      , [Plain "What is the stabilization time of the board within 100 generations?"]
      , [Plain "What is the least return time of the board within 100 generations?"]
      , [Plain "Does the count of cells matching color is black reach 0 within 70 generations?"]
      ])
  ]

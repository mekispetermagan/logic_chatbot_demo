module Domains.Calendar.Language.Examples (examples) where

import ControlledLanguage.Example (ExamplePart(..), ExampleSections)

-- Static concrete examples; reference spans are explicit structured parts.
examples :: ExampleSections
examples =
  [ ("Primitive commands",
      [ [Plain "Create event from thursday at 09:00 to thursday at 10:00 with title \"Meeting\"."]
      , [Plain "Set title of ", Reference "the event with importance critical", Plain " to \"Meeting with Mr Black\"."]
      , [Plain "Set location of ", Reference "it", Plain " to \"Head office\"."]
      , [Plain "Set description of ", Reference "the event with importance critical", Plain " to \"Review the proposal\"."]
      , [Plain "Set location of ", Reference "it", Plain " to \"\"."]
      , [Plain "Set importance of ", Reference "the event with importance important", Plain " to critical."]
      , [Plain "Set interval of ", Reference "#3", Plain " from thursday at 10:00 to thursday at 11:00."]
      , [Plain "Delete ", Reference "#3", Plain "."]
      ])
  , ("Primitive questions",
      [ [Plain "Does ", Reference "#3", Plain " exist?"]
      , [Plain "What is the title of ", Reference "the event with importance critical", Plain "?"]
      , [Plain "What is the end of ", Reference "the event with title \"Meeting\"", Plain "?"]
      , [Plain "What is the interval of ", Reference "the event with title \"Meeting\"", Plain "?"]
      , [Plain "Does ", Reference "it", Plain " satisfy importance is critical?"]
      , [Plain "Does ", Reference "the event with importance important", Plain " satisfy overlaps event ", Reference "the event with importance critical", Plain "?"]
      ])
  , ("Conceptual commands",
      [ [Plain "Schedule event lasting 30 minutes within thursday morning with title \"Meeting\"."]
      , [Plain "Make room for event lasting 60 minutes within starting at thursday at 09:00, moving up to normal."]
      , [Plain "Make room for event lasting 90 minutes within thursday afternoon, moving up to important, protecting [", Reference "the event with title \"Meeting\"", Plain "], choosing preserve original order."]
      , [Plain "Remove clashes on thursday, moving up to normal."]
      , [Plain "Schedule events jointly [event lasting 90 minutes within any of [monday morning; tuesday morning] with title \"Workshop\"; event lasting 120 minutes within monday morning with title \"Review\"], on different dates, choosing earliest in listed order."]
      , [Plain "Free window interval from thursday at 10:00 to thursday at 11:00, moving up to normal."]
      ])
  , ("Conceptual questions",
      [ [Plain "What is the duration of ", Reference "the event with importance critical", Plain "?"]
      , [Plain "What is the gap between ", Reference "it", Plain " and ", Reference "the event with importance critical", Plain "?"]
      , [Plain "How many events match importance is critical and overlaps thursday?"]
      , [Plain "Which events match starts on monday?"]
      , [Plain "Does every event matching starts on thursday satisfy importance is normal?"]
      , [Plain "Which intervals are free within thursday morning?"]
      , [Plain "Which event pairs clash within thursday?"]
      , [Plain "How many overlaps occur within thursday, counting pairs?"]
      , [Plain "How many overlaps occur within thursday, counting events?"]
      , [Plain "What is the earliest available interval lasting 60 minutes within thursday afternoon?"]
      , [Plain "Can an event lasting 90 minutes within thursday afternoon fit, moving up to normal?"]
      , [Plain "What is the minimum movement cost to fit an event lasting 90 minutes within thursday afternoon, moving up to normal?"]
      , [Plain "Can clashes on thursday be removed, moving up to normal?"]
      , [Plain "Can events [event lasting 60 minutes within monday morning; event lasting 60 minutes within tuesday morning] be scheduled jointly, on different dates?"]
      , [Plain "Can window thursday morning be freed, moving up to normal?"]
      , [Plain "What is the minimum movement cost to free window interval from thursday at 10:00 to thursday at 11:00, moving up to important?"]
      ])
  ]

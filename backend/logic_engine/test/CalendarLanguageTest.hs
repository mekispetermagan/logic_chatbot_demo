module Main where

import Control.Monad (unless, forM_)
import Data.List (isInfixOf)
import Domains.Calendar.Types
import Domains.Calendar.Language.Parser
import Domains.Calendar.Language.Pretty

assert :: String -> Bool -> IO ()
assert label condition = unless condition (error label)

main :: IO ()
main = do
  let examples =
        [ "Create event from thursday at 09:00 to friday at 10:00."
        , "Set title of it to \"\". Set importance of #0 to normal. Delete #0."
        , "Set location of the unique event with title \"Meeting\" and importance important and start date thursday to \"Office\"."
        , "Schedule event."
        , "Schedule event lasting unspecified within unspecified date morning after 09:00."
        , "Schedule event lasting 30 minutes within starting at thursday at one of [05:00, 17:00]."
        , "Make room for event lasting 60 minutes within thursday morning with title \"Meeting\" and importance critical, moving up to normal, protecting [#0], choosing preserve original order."
        , "Remove clashes on unspecified date, protecting unspecified."
        , "Does #0 exist? What is the unspecified of unspecified?"
        , "Does #0 satisfy not (title is \"x\" or importance is critical)?"
        , "How many events match importance is unspecified and overlaps thursday?"
        , "Which events match before event #0 and duration is at least 30 minutes?"
        , "Does every event matching starts on monday satisfy within monday morning?"
        , "What is the gap between #0 and #1?"
        , "Which intervals are free within thursday night?"
        , "How many overlaps occur within unspecified, counting pairs?"
        , "What is the earliest available interval lasting 60 minutes within thursday afternoon?"
        , "Can an event lasting 90 minutes within thursday afternoon fit, moving up to normal?"
        , "What is the minimum movement cost to fit an event lasting 90 minutes within thursday afternoon, moving up to normal?"
        , "Can clashes on thursday be removed, moving up to normal?"
        ]
  forM_ examples $ \source -> case parseEntry source of
    Left message -> error (source ++ ": " ++ message)
    Right ast -> case parseEntry (entryText ast) of
      Left message -> error (entryText ast ++ ": " ++ message)
      Right ast' -> assert ("canonical formatting: " ++ source) (entryText ast' == entryText ast)
  forM_ ["Undo.", "Delete #01.", "Create event from thursday at 24:00 to thursday at 25:00.",
         "Schedule event with title \"x\" and title \"y\".", "How many events match true.", "Create event from monday at ١٠:٠٠ to monday at 11:00."] $ \source ->
    assert ("invalid syntax accepted: " ++ source) (case parseEntries source of Left _ -> True; _ -> False)
  assert "half ticks round down" (roundTime (2*tick + tick `div` 2) == 2*tick)
  assert "above half rounds up" (roundTime (2*tick + tick `div` 2 + 1) == 3*tick)
  assert "scope choices before effects" (case parseEntries "Delete #0. Does #1 satisfy true or true and true?" of Right xs -> length xs == 2; _ -> False)
  putStrLn "All Calendar parser and model checks passed."

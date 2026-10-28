module Main where

import Control.Monad (unless, forM_)
import Data.List (isInfixOf)
import qualified Domains.Objects.Language.Parser as O
import qualified Domains.Network.Language.Parser as N
import qualified Domains.Cellular.Language.Parser as C
import qualified Domains.Cellular.Language.Pretty as CP
import qualified Domains.Calendar.Language.Parser as K

check name yes = unless yes (error name)
rejected label result expected = case result of
  Right _ -> error (label ++ ": invalid input accepted")
  Left message -> do
    check (label ++ ": missing location/caret: " ++ message) ("^" `isInfixOf` message && ":1:" `isInfixOf` message)
    forM_ expected $ \part -> check (label ++ ": missing " ++ show part ++ ": " ++ message) (part `isInfixOf` message)

main = do
  rejected "Calendar missing at" (K.parseEntries "Create event from Thursday 11:00 to Thursday at 11:30.") ["at",":1:28:"]
  rejected "Calendar invalid time" (K.parseEntries "Create event from thursday at 25:00 to thursday at 11:30.") ["hours must be 00"]
  rejected "Calendar duplicate fields" (K.parseEntries "Create event from unspecified to unspecified with title \"a\" and title \"b\".") ["must not be repeated"]
  rejected "Calendar field order" (K.parseEntries "Create event from unspecified to unspecified with importance critical and title \"a\".") ["must be ordered"]
  rejected "Calendar invalid date" (K.parseEntries "Create event from 2026-02-30 at 09:00 to unspecified.") ["Invalid date"]
  rejected "Calendar string" (K.parseEntries "Set title of it to \"Meeting.") ["expecting"]
  rejected "Calendar missing period" (K.parseEntries "Delete #3") ["\".\""]
  rejected "Cellular whole keywords" (C.parseEntry "What is the current palette?") [":1:13:", "current", "palette", "color", "generation", "expecting"]
  rejected "Objects whole keywords" (O.parseEntry "What is the current color of #3?") [":1:13:", "current", "color", "expecting"]
  rejected "Network whole keywords" (N.parseEntry "What is the current pattern of #3?") [":1:13:", "current", "pattern", "expecting"]
  rejected "Calendar whole keywords" (K.parseEntries "What is the current title of #3?") [":1:13:", "current", "title", "duration", "expecting"]
  rejected "Cellular keyword boundary" (C.parseEntry "What is the paletteExtra?") [":1:13:", "paletteExtra", "palette", "expecting"]
  rejected "Cellular range" (C.parseEntry "Advance 257 generations.") ["between 1 and 256"]
  rejected "Cellular duplicates" (C.parseEntry "Set rule for white to target black, counts [3, 3], enabled true.") ["must not be repeated"]
  rejected "Cellular missing to" (C.parseEntry "Set color of A1 black.") ["to"]
  rejected "Objects surface syntax" (O.parseEntry "Create object with color red on C4") ["\".\""]
  rejected "Network missing pattern" (N.parseEntry "Create object with pattern on C4.") ["expecting"]
  -- The second line must be diagnosed in the original entry, not in a canonical rewrite.
  case C.parseEntry "Set color of A1 to black.\nAdvance 1 generation" of
    Left message -> check ("later-line diagnostic: "++message) (":2:21:" `isInfixOf` message)
    Right _ -> error "Missing later punctuation accepted"
  check "Objects Boolean readings retained" (either (const False) ((==2).length) (O.parseEntryAlternatives "Does #3 satisfy color is red or size is large and shape is bloom?"))
  check "Network Boolean readings retained" (either (const False) ((==2).length) (N.parseEntryAlternatives "Does #3 satisfy color is red or color is blue and color is green?"))
  check "Cellular Boolean readings retained" (either (const False) ((==2).length) (C.parseEntryAlternatives "Does A1 satisfy color is red or color is blue and color is green?"))
  check "Calendar Boolean readings retained" (either (const False) ((==2).length) (K.parseEntries "Does #3 satisfy importance is normal or importance is important and importance is critical?"))
  check "Cellular negation choice order retained" (fmap (map CP.entryText) (C.parseEntryAlternatives "Does A1 satisfy not color is white and row is 1?") == Right
    ["does A1 satisfy ((not color is white) and row is 1)?", "does A1 satisfy (not (color is white and row is 1))?"])
  putStrLn "Shared parser diagnostics and ambiguity checks passed."

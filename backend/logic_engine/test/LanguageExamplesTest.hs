module Main where

import Control.Monad (forM_, unless)
import Data.List (isPrefixOf)
import ControlledLanguage.Example (ExamplePart(..), ExampleSections, sentence)
import qualified Domains.Objects.Language.Examples as Objects
import qualified Domains.Network.Language.Examples as Network
import qualified Domains.Cellular.Language.Examples as Cellular
import qualified Domains.Calendar.Language.Examples as Calendar
import qualified Domains.Objects.Language.Parser as OP
import qualified Domains.Network.Language.Parser as NP
import qualified Domains.Cellular.Language.Parser as CP
import qualified Domains.Calendar.Language.Parser as KP

check :: Show a => String -> ExampleSections -> (String -> Either String a) -> IO ()
check domain sections parse = do
  unless (map fst sections == ["Primitive commands", "Primitive questions", "Conceptual commands", "Conceptual questions"])
    (fail (domain ++ ": expected all four help sections"))
  let references = [text | (_, entries) <- sections, example <- entries, Reference text <- example]
  unless ("it" `elem` references && any ("the " `isPrefixOf`) references &&
          any (\text -> "#" `isPrefixOf` text || case text of c:n:_ -> c `elem` ['A'..'P'] && n `elem` ['0'..'9']; _ -> False) references)
    (fail (domain ++ ": expected identifiers/coordinates, pronouns and descriptions"))
  unless (all (not . null) references) (fail (domain ++ ": empty reference span"))
  forM_ sections $ \(title, entries) -> do
    unless (not (null entries)) (fail (domain ++ ": empty " ++ title))
    forM_ entries $ \example -> let source = sentence example in case parse source of
      Left diagnostic -> fail (domain ++ ": " ++ source ++ "\n" ++ diagnostic)
      Right _ -> pure ()

main :: IO ()
main = do
  check "objects" Objects.examples OP.parseEntry
  check "network" Network.examples NP.parseEntry
  check "cellular" Cellular.examples CP.parseEntry
  check "calendar" Calendar.examples KP.parseEntry
  putStrLn "All four domains' help examples parse."

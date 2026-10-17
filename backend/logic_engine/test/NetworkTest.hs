module Main where

import Control.Monad (unless)
import Data.Either (isLeft)
import Data.List (nub, isInfixOf)
import Domain
import Ontology
import Pretty
import AtomicParser
import AtomicSentence
import AtomicPropertyCheck
import AtomicPerformative
import Layer2Parser
import Layer2Evaluation
import Domains.Objects.Definition
import Domains.Network.Definition
import Domains.Network.Library
import Domains.Network.Sandbox

check :: String -> Bool -> IO ()
check name condition = unless condition (fail name)

run :: World -> String -> (World, String)
run world text = case parseSentencesWith networkLibrary text of
  Left error -> errorWithoutStackTrace error
  Right sentences -> let (updated, _, pending, feedback) = evaluateEntryIn networkLibrary world [] sentences
                     in if pending == Nothing then (updated, feedback)
                        else errorWithoutStackTrace "Unexpected clarification"

main :: IO ()
main = do
  check "network validates" (validateDomain networkDomain == Right networkDomain)
  let World seed = networkWorld
  check "seven stable valid placed objects"
    (length seed == 7 && length (nub (map idOf seed)) == 7 &&
     length (nub (map positionOf seed)) == 7 &&
     all (maybe False (inDomainBounds networkDomain) . positionOf) seed &&
     all (maybe False (`elem` map ValueId ["red","blue","green","yellow"]) . attributeOf (AttributeId "color")) seed)
  mapM_ (\(name,alias) -> do
    let expected = Right (PropertyCheck (APC (AtSquare (0,0))
                     (AttributeValue (AttributeId name) (ValueId name))))
    check "port questions are checks in core grammar"
      (parseAtomicSentenceWith networkDomain ("A1 " ++ name ++ "?") == expected &&
       parseAtomicSentenceWith networkDomain ("A1 " ++ alias ++ "?") == expected)
    check "aliases remove the same attribute"
      (parseAtomicSentenceWith networkDomain ("A1 remove " ++ alias ++ ".") ==
        Right (Performative (RemoveAttribute (AtSquare (0,0)) (RemoveStored (AttributeId name))))))
    [("north","up"),("east","right"),("south","down"),("west","left")]
  let (updated, answer) = run (World [])
        "A1 up. A1 right. A1 down. A1 left. A1 red. A1 north? A1 remove up. A1 north? A1 east? color of A1?"
  check "ports are independent, color belongs to object, removal means absence"
    (case updated of { World [item] ->
                      attributeOf (AttributeId "north") item == Nothing &&
                      all (\name -> attributeOf (AttributeId name) item == Just (ValueId name)) ["east","south","west"] &&
                      attributeOf (AttributeId "color") item == Just (ValueId "red"); _ -> False })
  check "Boolean answers and color query" ("false" `isInfixOf` answer && "true" `isInfixOf` answer && "red" `isInfixOf` answer)
  let (described, _) = run (World [])
        "A north east red on A4. The red north is blue. It south. Is it north? color of it?"
  check "indefinite, definite and pronoun resolution use network attributes"
    (case described of { World [item] -> positionOf item == Just (0,3) &&
                      attributeOf (AttributeId "color") item == Just (ValueId "blue") &&
                      attributeOf (AttributeId "south") item == Just (ValueId "south"); _ -> False })
  let (swapped, _) = run (World []) "#0 north on A1. #1 red. Swap #0 and #1."
  check "swap placed and unplaced keeps ports with identities"
    (case swapped of World items -> any (\item -> idOf item == Id 0 && positionOf item == Nothing) items &&
                                   any (\item -> idOf item == Id 1 && positionOf item == Just (0,0)) items)
  check "unplace and delete remain available"
    (fst (run swapped "Remove #1 from board. Delete #0. Delete #1.") == World [])
  check "outward ports are legal" (fst (run (World []) "H8 north. H8 east.") /= World [])
  check "board bounds still enforced" (isLeft (parseSentenceWith networkLibrary "I1 north."))
  check "no size or shape vocabulary" (all (isLeft . parseSentenceWith networkLibrary) ["A1 small.","A1 bloom."])
  check "objects domain stays isolated" (isLeft (parseAtomicSentenceWith objectsDomain "A1 north."))
  check "network derived movement available" (not (isLeft (parseSentenceWith networkLibrary "Move #0 up.")))
  check "network introduction parses" (not (isLeft networkIntroduction))
  check "domain fixture prints" ("north" `isInfixOf` prettyWorldIn networkDomain networkWorld)
  putStrLn "All network core checks passed."

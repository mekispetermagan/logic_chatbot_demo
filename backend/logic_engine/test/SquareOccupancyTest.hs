module Main where

import Control.Monad (forM_, unless)
import Data.Either (isLeft)
import Data.List (isInfixOf)
import AtomicEvaluation
import AtomicParser
import AtomicSentence
import AtomicSquareCheck
import Discourse
import Domain
import DomainLibrary
import Domains.Objects.Library (objectsLibrary)
import Domains.Network.Library (networkLibrary)
import Layer2Evaluation
import Layer2Parser
import qualified Layer2Syntax as L2
import Ontology
import Pretty
import Result

check :: String -> Bool -> IO ()
check label condition = unless condition (fail label)

resultIs :: Eq a => a -> Result a -> Bool
resultIs expected (Result actual) = actual == expected
resultIs _ _ = False

original :: World
original = World [(emptyObject (Id 0)) {positionOf = Just (3,3)}, emptyObject (Id 1)]

main :: IO ()
main = do
  forM_ [objectsLibrary, networkLibrary] $ \library -> do
    let domain = ontology library
        question = SquareCheck (ASC (3,3))
        layer2Question = L2.SquareOccupancy (3,3)
    forM_ ["Is the square D4 occupied?", "IS SQUARE d4 TAKEN?", "the square D4 occupied?",
           "square D4 taken?", " \n Is  the square D4 occupied? \t"] $ \text -> do
      check ("core parsing: " ++ text) (parseAtomicSentenceWith domain text == Right question)
      check ("shared parsing: " ++ text) (parseSentenceWith library text == Right layer2Question)
    forM_ ["Is the square D4 empty?", "Is the square D4 free?", "Is the square D4 occupied.",
           "Is the square D4 occupied", "Is the square #0 taken?", "D4 occupied?",
           "Is the square I1 occupied?", "Is the square A9 taken?", "square A0 taken?"] $ \text -> do
      check ("core rejection: " ++ text) (isLeft (parseAtomicSentenceWith domain text))
      check ("shared rejection: " ++ text) (isLeft (parseSentenceWith library text))
    check "questions cannot parse as performatives"
      (isLeft (parseAtomicPerformativeWith domain "Is the square D4 occupied?"))
    check "core canonical pretty round trip" (parseAtomicSentenceWith domain (pretty question) == Right question)
    check "shared canonical pretty round trip" (parseSentenceWith library (pretty layer2Question) == Right layer2Question)
    check "layer 2 converts to core square check" (L2.toAtomicSentence layer2Question == Just question)
    check "a partial portless object occupies its square"
      (resultIs True (evaluateAtomicSquareCheckWith domain original (ASC (3,3))))
    check "unplaced objects occupy no square"
      (resultIs False (evaluateAtomicSquareCheckWith domain original (ASC (0,0))))
    check "empty world yields false without creating objects"
      (case evaluateAtomicSentenceWith domain (World []) question of
        (World [], AtomicFeedback _ (CheckAnswer False)) -> True
        _ -> False)
    forM_ [(-1,0),(0,-1),(boardWidth domain,0),(0,boardHeight domain)] $ \position ->
      check "out-of-bounds typed checks return a diagnostic"
        (case evaluateAtomicSquareCheckWith domain original (ASC position) of Message _ -> True; _ -> False)
    let text = "Is the square D4 taken? D4 red. Is square D4 occupied? Delete D4. Square D4 occupied?"
        sentences = either error id (parseAtomicSentencesWith domain text)
        (finalWorld, feedback) = evaluateAtomicSentencesWith domain (World []) sentences
    check "square checks see earlier updates and deletion in an atomic sequence"
      (finalWorld == World [] && [answer | AtomicFeedback _ (CheckAnswer answer) <- feedback] == [False,True,False])
    let ranking = [((0,0),Id 0,[])]
        (same, mentions, pending, rendered) = evaluateEntryIn library original ranking [layer2Question]
    check "shared evaluation leaves world intact and adds no object mention"
      (same == original && mentions == [((1,0),Id 0,[])] && pending == Nothing && "\n  true" `isInfixOf` rendered)
    check "square checks have no object resolution operands" (null (subjectsOf layer2Question))
    let shared = either error id (parseSentencesWith library text)
        (after, _, _, answers) = evaluateEntryIn library (World []) [] shared
    check "shared sequence answers occupied and unoccupied without creating references"
      (after == World [] && "\n  false" `isInfixOf` answers && "\n  true" `isInfixOf` answers)
  let small = (ontology objectsLibrary) {boardWidth = 3, boardHeight = 2}
  check "parsing uses domain dimensions" (parseAtomicSentenceWith small "square C2 taken?" == Right (SquareCheck (ASC (2,1))))
  check "smaller domain rejects other squares" (isLeft (parseAtomicSentenceWith small "square D2 taken?"))
  check "network empty retains no-port meaning"
    (parseSentenceWith networkLibrary "D4 empty?" == Right (L2.Check (L2.Reference (AtSquare (3,3))) (Defined "dot")))
  putStrLn "All square occupancy checks passed."

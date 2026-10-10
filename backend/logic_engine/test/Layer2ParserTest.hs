module Main where

import Control.Monad (forM_, unless)
import Data.Either (isLeft)
import AtomicPerformative
import AtomicSentence
import Layer2Parser
import Layer2Syntax
import Ontology
import Pretty

check :: String -> Bool -> IO ()
check name success = unless success (fail name)

main :: IO ()
main = do
  forM_ ["undo", "  UnDo #3 red. garbage?", "\n\tUNDOanything"] $ \input ->
    check ("undo prefix: " ++ show input) (isUndoEntry input)
  forM_ ["", "   ", "und", "#3 red. undo", "do undo"] $ \input ->
    check ("not undo prefix: " ++ show input) (not (isUndoEntry input))
  let accepted =
        [ "H7 REMOVE COLOR", "it remove size.", "the red bloom remove shape.",
          "#3 remove square. color of #3?", "remove #3 from board.", "remove it.", "REMOVE the large bloom FROM BOARD",
          "swap #3 #4.", "swap it and the red bloom", "swap the bloom the spark.",
          "erase the red one.", "delete A1.", "remove A1. swap B1 and #3. delete #4.",
          "It is bloom.", "It to a4.", "The bloom is red.", "A bloom on a4"
        , "#23 is a bloom.", "#23 is a red.", "a red on A3.", "red bloom A3."
        , "a bloom red bloom on A4.", "the red red bloom is large green."
        , "the red bloom red bloom on A4"
        , "the bloom large is green.", "turn the bloom large to green."
        , "Move it to a4", "Move the red bloom on A4.", "Turn it red"
        , "Turn it to a bloom", "a red one on A4.", "the red one is bloom."
        , "the bloom one is red.", "turn a4 to red", "turn a4 a bloom"
        , "turn a4 to a bloom", "turn a4 a red", "A4 is a red bloom"
        , "Turn A4 to a large blue spark.", "A4 is a red bloom on B3."
        , "a red bloom is large on B3.", "#3 on B3. #3 red. #3 medium. #3 is bloom."
        , "Is it red?", "Is the bloom red?", "Is the large bloom red?"
        , "Is the bloom large green?", "the large bloom is red?", "the bloom to red?"
        , "#3 red?", "B3 spark?", "it on A4?", "is #3 on A4?"
        , "What is the shape of the red bloom?", "What is shape of it?"
        , "color of it?", "shape of the red bloom?", "the red bloom color?"
        , "the red one is size?", "#3 red.#3 bloom.#3 red?shape of #3?"
        ]
  forM_ accepted $ \input -> case parseSentences input of
    Left message -> fail (input ++ "\n" ++ message)
    Right sentences -> check ("pretty round trip: " ++ input)
      (parseSentences (unwords (map pretty sentences)) == Right sentences)
  forM_
    [ "", " ", "the bloom large green"
    , "#3 red #4 blue", "#3 red. nonsense", "#3 red?.", "#3 red??"
    , "a bloom red?", "Is a bloom red?", "color of a red bloom?"
    , "what is color of red bloom?", "B3 red green spark?"
    , "the bloom is red green?", "the bloom red?", "#3 to A4?"
    , "turn it red?", "move it to A4?", "a bloom red."
    , "#3 on A4 red.", "#3 red on A4 on B3.", "move it red."
    , "#3 on I1.", "#3 on A9.", "o3 red.", "#3red."
    , "the is red.", "a on A4.", "color of it", "the bloom one one is red."
    ] $ \input -> check ("reject: " ++ input) (isLeft (parseSentences input))
  forM_ ["a bloom remove color.", "bloom remove shape.", "it remove color?",
         "H7 remove square?", "#3 remove row.", "#3 remove position.",
         "#3 remove color it red.", "#3 is remove color.", "remove a bloom.", "swap a bloom and #3.", "swap #3 red bloom.", "delete red.",
         "remove #3?", "swap it and #4?", "erase #3?", "swap the bloom.",
         "remove the bloom from.", "delete #3 remove #4."] $ \input ->
    check ("reject structural: " ++ input) (isLeft (parseSentences input))
  check "descriptor order and repetition preserved"
    (parseSentence "a bloom red bloom on A4" == Right
      (Attribution (Indefinite [Sh Bloom, C Red, Sh Bloom]) [P (0,3)]))
  check "inverted single-property boundary"
    (parseSentence "Is the large bloom red?" == Right
      (Check (Definite [S Large, Sh Bloom]) (C Red)))
  check "compound predicates do not lower to atomic evaluation"
    (toAtomicSentence (Attribution (Reference (AtSquare (0,0))) [C Red, Sh Bloom]) == Nothing)
  check "pronouns do not lower to atomic evaluation"
    (toAtomicSentence (Check It (C Red)) == Nothing)
  check "attribute removal lowers to layer 1"
    (toAtomicSentence (AttributeRemoval (Reference (AtSquare (7,6))) RemoveColor) ==
      Just (Performative (RemoveAttribute (AtSquare (7,6)) RemoveColor)))
  forM_ [("flower","bloom"),("star","spark"),("tear","drop"),("ring","loop")] $ \(alias,canonical) -> do
    let entry word = "A " ++ word ++ " on A1. The " ++ word ++ " is red. " ++
          "Is the " ++ word ++ " red? Shape of the " ++ word ++ "? " ++
          "How many " ++ word ++ "? Is every " ++ word ++ " object a " ++ word ++ "?"
    check ("alias in every description context: " ++ alias)
      (parseSentences (entry alias) == parseSentences (entry canonical))
  forM_ ["Cube A1.", "a sphere on A1.", "the pyramid is red.", "#0 cube?", "How many sphere?"] $ \input ->
    check ("reject old shape: " ++ input) (isLeft (parseSentences input))
  putStrLn "All Layer 2 parser checks passed."

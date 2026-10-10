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
        [ "H7 REMOVE COLOR", "it remove size.", "the red cube remove shape.",
          "#3 remove square. color of #3?", "remove #3 from board.", "remove it.", "REMOVE the large cube FROM BOARD",
          "swap #3 #4.", "swap it and the red cube", "swap the cube the sphere.",
          "erase the red one.", "delete A1.", "remove A1. swap B1 and #3. delete #4.",
          "It is cube.", "It to a4.", "The cube is red.", "A cube on a4"
        , "#23 is a cube.", "#23 is a red.", "a red on A3.", "red cube A3."
        , "a cube red cube on A4.", "the red red cube is large green."
        , "the red cube red cube on A4"
        , "the cube large is green.", "turn the cube large to green."
        , "Move it to a4", "Move the red cube on A4.", "Turn it red"
        , "Turn it to a cube", "a red one on A4.", "the red one is cube."
        , "the cube one is red.", "turn a4 to red", "turn a4 a cube"
        , "turn a4 to a cube", "turn a4 a red", "A4 is a red cube"
        , "Turn A4 to a large blue sphere.", "A4 is a red cube on B3."
        , "a red cube is large on B3.", "#3 on B3. #3 red. #3 medium. #3 is cube."
        , "Is it red?", "Is the cube red?", "Is the large cube red?"
        , "Is the cube large green?", "the large cube is red?", "the cube to red?"
        , "#3 red?", "B3 sphere?", "it on A4?", "is #3 on A4?"
        , "What is the shape of the red cube?", "What is shape of it?"
        , "color of it?", "shape of the red cube?", "the red cube color?"
        , "the red one is size?", "#3 red.#3 cube.#3 red?shape of #3?"
        ]
  forM_ accepted $ \input -> case parseSentences input of
    Left message -> fail (input ++ "\n" ++ message)
    Right sentences -> check ("pretty round trip: " ++ input)
      (parseSentences (unwords (map pretty sentences)) == Right sentences)
  forM_
    [ "", " ", "the cube large green"
    , "#3 red #4 blue", "#3 red. nonsense", "#3 red?.", "#3 red??"
    , "a cube red?", "Is a cube red?", "color of a red cube?"
    , "what is color of red cube?", "B3 red green sphere?"
    , "the cube is red green?", "the cube red?", "#3 to A4?"
    , "turn it red?", "move it to A4?", "a cube red."
    , "#3 on A4 red.", "#3 red on A4 on B3.", "move it red."
    , "#3 on I1.", "#3 on A9.", "o3 red.", "#3red."
    , "the is red.", "a on A4.", "color of it", "the cube one one is red."
    ] $ \input -> check ("reject: " ++ input) (isLeft (parseSentences input))
  forM_ ["a cube remove color.", "cube remove shape.", "it remove color?",
         "H7 remove square?", "#3 remove row.", "#3 remove position.",
         "#3 remove color it red.", "#3 is remove color.", "remove a cube.", "swap a cube and #3.", "swap #3 red cube.", "delete red.",
         "remove #3?", "swap it and #4?", "erase #3?", "swap the cube.",
         "remove the cube from.", "delete #3 remove #4."] $ \input ->
    check ("reject structural: " ++ input) (isLeft (parseSentences input))
  check "descriptor order and repetition preserved"
    (parseSentence "a cube red cube on A4" == Right
      (Attribution (Indefinite [Sh Cube, C Red, Sh Cube]) [P (0,3)]))
  check "inverted single-property boundary"
    (parseSentence "Is the large cube red?" == Right
      (Check (Definite [S Large, Sh Cube]) (C Red)))
  check "compound predicates do not lower to atomic evaluation"
    (toAtomicSentence (Attribution (Reference (AtSquare (0,0))) [C Red, Sh Cube]) == Nothing)
  check "pronouns do not lower to atomic evaluation"
    (toAtomicSentence (Check It (C Red)) == Nothing)
  check "attribute removal lowers to layer 1"
    (toAtomicSentence (AttributeRemoval (Reference (AtSquare (7,6))) RemoveColor) ==
      Just (Performative (RemoveAttribute (AtSquare (7,6)) RemoveColor)))
  putStrLn "All Layer 2 parser checks passed."

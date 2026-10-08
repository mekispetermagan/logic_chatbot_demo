module Console where

import AtomicEvaluation (evaluateAtomicSentences)
import AtomicParser (parseAtomicSentences)
import Ontology (World)
import Pretty (pretty)
import qualified Sandbox
import System.IO (hFlush, isEOF, stdout)

main :: IO ()
main = chatLoop Sandbox.world

chatLoop :: World -> IO ()
chatLoop world = do
  putStrLn (pretty world)
  putStr "> "
  hFlush stdout
  done <- isEOF
  if done then putStrLn "" else do
    input <- getLine
    if input == ":quit" then pure () else
      case parseAtomicSentences input of
        Left message -> do
          putStrLn message
          chatLoop world
        Right sentences -> do
          let (updatedWorld, feedback) = evaluateAtomicSentences world sentences
          mapM_ (putStrLn . pretty) feedback
          chatLoop updatedWorld

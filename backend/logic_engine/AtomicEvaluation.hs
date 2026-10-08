module AtomicEvaluation where

import Data.List (foldl')
import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import AtomicSentence
import Ontology
import Pretty
import Result

data FeedbackAnswer = UpdateAnswer UpdateChange
                    | CheckAnswer Bool
                    | QueryAnswerValue QueryAnswer
                    | FeedbackMessage String
                    deriving (Eq, Show)

data AtomicFeedback = AtomicFeedback
  { feedbackSentence :: AtomicSentence
  , feedbackAnswer :: FeedbackAnswer
  } deriving (Eq, Show)

instance PrettyShow FeedbackAnswer where
  pretty (UpdateAnswer change) = pretty change
  pretty (CheckAnswer True) = "true"
  pretty (CheckAnswer False) = "false"
  pretty (QueryAnswerValue answer) = pretty answer
  pretty (FeedbackMessage message) = message

instance PrettyShow AtomicFeedback where
  pretty (AtomicFeedback sentence answer) = pretty sentence ++ "\n  " ++ pretty answer

evaluateAtomicSentence :: World -> AtomicSentence -> (World, AtomicFeedback)
evaluateAtomicSentence world sentence = case sentence of
  Performative performative ->
    let (updated, result) = evaluateAtomicPerformative world performative
        answer = case result of
          Result change -> UpdateAnswer change
          Message message -> FeedbackMessage message
    in (updated, AtomicFeedback sentence answer)
  PropertyCheck question ->
    (world, AtomicFeedback sentence $ case evaluateAtomicPropertyCheck world question of
      Result answer -> CheckAnswer answer
      Message message -> FeedbackMessage message)
  PropertyQuery question ->
    (world, AtomicFeedback sentence $ case evaluateAtomicPropertyQuery world question of
      Result answer -> QueryAnswerValue answer
      Message message -> FeedbackMessage message)

-- Feedback follows input order, and questions see all preceding updates.
evaluateAtomicSentences :: World -> [AtomicSentence] -> (World, [AtomicFeedback])
evaluateAtomicSentences initial sentences =
  let (finalWorld, reversedFeedback) = foldl' step (initial, []) sentences
  in (finalWorld, reverse reversedFeedback)
  where
    step (world, feedback) sentence =
      let (updated, answer) = evaluateAtomicSentence world sentence
      in (updated, answer : feedback)

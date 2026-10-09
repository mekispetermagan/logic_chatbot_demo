module Layer2Evaluation where

import Data.List (intercalate)
import Discourse
import Ontology
import Layer2Syntax
import AtomicSentence
import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import AtomicEvaluation
import Pretty

-- A continuation does not begin another entry or age a paused utterance twice.
evaluateEntry :: World -> SalienceRanking -> [Sentence] -> (World, SalienceRanking, Maybe Pending, String)
evaluateEntry world ranking = evaluateRemaining world (beginEntry ranking) Nothing

resumeEntry :: World -> SalienceRanking -> Pending -> Identifier -> (World, SalienceRanking, Maybe Pending, String)
resumeEntry world ranking pending identifier
  | identifier `elem` candidateIds pending = evaluateRemaining world ranking (Just identifier) (remainingSentences pending)
  | otherwise = (world, ranking, Just pending, "Choose one of the listed objects")

evaluateRemaining :: World -> SalienceRanking -> Maybe Identifier -> [Sentence]
                  -> (World, SalienceRanking, Maybe Pending, String)
evaluateRemaining world ranking _ [] = (world, ranking, Nothing, "")
evaluateRemaining world ranking selected sentences@(sentence:rest) =
  case resolution of
    Ambiguous identifiers -> (world, ranking, Just (Pending sentences identifiers),
      pretty sentence ++ "\n  Which object?")
    Unresolved message -> continue world (advanceUtterance ranking) (pretty sentence ++ "\n  " ++ message)
    Resolved resolvedWorld identifier ->
      let (updated, answers, associated) = evaluateResolved resolvedWorld identifier sentence
          updatedRanking = mention updated identifier associated ranking
      in continue updated updatedRanking (pretty sentence ++ "\n  " ++ intercalate "\n  " answers)
  where
    resolution = case selected of
      Just identifier -> Resolved world identifier
      Nothing -> resolveSubject (case sentence of Attribution _ _ -> True; _ -> False)
                   world ranking (subjectOf sentence)
    continue updated updatedRanking answer =
      let (finalWorld, finalRanking, pending, feedback) = evaluateRemaining updated updatedRanking Nothing rest
      in (finalWorld, finalRanking, pending, answer ++ if null feedback then "" else "\n" ++ feedback)

evaluateResolved :: World -> Identifier -> Sentence -> (World, [String], [Property])
evaluateResolved world identifier sentence = case sentence of
  Attribution subject properties ->
    let initialProperties = case subject of Indefinite descriptors -> descriptors; _ -> []
        step (current, answers) property =
          let (updated, feedback) = evaluateAtomicSentence current (Performative (AP reference property))
          in (updated, answers ++ [pretty (feedbackAnswer feedback)])
        (updated, answers) = foldl step (world, []) (initialProperties ++ properties)
    in (updated, answers, descriptorsOf subject ++ properties)
  Check subject property ->
    let (_, feedback) = evaluateAtomicSentence world (PropertyCheck (APC reference property))
    in (world, [pretty (feedbackAnswer feedback)], descriptorsOf subject ++ [property])
  Query attribute subject ->
    let (_, feedback) = evaluateAtomicSentence world (PropertyQuery (APQ attribute reference))
        associated = case feedbackAnswer feedback of
          QueryAnswerValue (PropertyValue property) -> [property]
          QueryAnswerValue (RowValue _) -> positionProperty
          QueryAnswerValue (ColumnValue _) -> positionProperty
          _ -> []
        positionProperty = [P position | World objects <- [world], object <- objects,
                             idOf object == identifier, Just position <- [positionOf object]]
    in (world, [pretty (feedbackAnswer feedback)], descriptorsOf subject ++ associated)
  where reference = ById identifier

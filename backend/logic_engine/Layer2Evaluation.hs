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
import Layer3Evaluation
import Pretty

-- A continuation does not begin another entry or age a paused utterance twice.
evaluateEntry :: World -> SalienceRanking -> [Sentence] -> (World, SalienceRanking, Maybe Pending, String)
evaluateEntry world ranking = evaluateRemaining world (beginEntry ranking) []

resumeEntry :: World -> SalienceRanking -> Pending -> Identifier -> (World, SalienceRanking, Maybe Pending, String)
resumeEntry world ranking pending@SquarePending{} _ = (world, ranking, Just pending, "Choose a square")
resumeEntry world ranking pending identifier
  | identifier `elem` candidateIds pending = evaluateRemaining world ranking
      (resolvedSubjects pending ++ [identifier]) (remainingSentences pending)
  | otherwise = (world, ranking, Just pending, "Choose one of the listed objects")

evaluateRemaining :: World -> SalienceRanking -> [Identifier] -> [Sentence]
                  -> (World, SalienceRanking, Maybe Pending, String)
evaluateRemaining = evaluateRemainingWith Nothing

resumeSquareEntry :: World -> SalienceRanking -> Pending -> Position -> (World, SalienceRanking, Maybe Pending, String)
resumeSquareEntry world ranking pending@SquarePending{} position
  | position `elem` squareChoices pending = evaluateRemainingWith (Just position) world ranking
      (resolvedSubjects pending) (remainingSentences pending)
  | otherwise = (world, ranking, Just pending, "Choose one of the listed squares")
resumeSquareEntry world ranking pending _ = (world, ranking, Just pending, "Choose an object")

evaluateRemainingWith :: Maybe Position -> World -> SalienceRanking -> [Identifier] -> [Sentence]
                      -> (World, SalienceRanking, Maybe Pending, String)
evaluateRemainingWith _ world ranking _ [] = (world, ranking, Nothing, "")
evaluateRemainingWith square world ranking supplied sentences@(sentence:rest) =
  resolveOperands world [] supplied (subjectsOf sentence)
  where
    resolveOperands current identifiers _ [] =
      case evaluateDerived current identifiers sentence square of
        Just (ChooseSquares positions) -> (world, ranking,
          Just (SquarePending sentences [] identifiers positions), pretty sentence ++ "\n  Which square?")
        Just (DerivedComplete updated answers associated) -> complete identifiers updated answers associated
        Nothing -> let (updated, answers, associated) = evaluateResolved current identifiers sentence
                   in complete identifiers updated answers associated
    resolveOperands current identifiers (identifier:chosen) (_:subjects)
      | hasId current identifier = resolveOperands current (identifiers ++ [identifier]) chosen subjects
      | otherwise = failed "Object no longer exists"
    resolveOperands current identifiers [] (subject:subjects) =
      case resolveSubject creates current ranking subject of
        Ambiguous candidates -> (world, ranking, Just (Pending sentences candidates identifiers),
          pretty sentence ++ "\n  Which object?")
        Unresolved message -> failed message
        Resolved resolvedWorld identifier -> resolveOperands resolvedWorld (identifiers ++ [identifier]) [] subjects
    complete identifiers updated answers associated =
      let updatedRanking = mentionMany updated (zip identifiers associated) ranking
      in continue updated updatedRanking (pretty sentence ++ "\n  " ++ intercalate "\n  " answers)
    creates = case sentence of Attribution _ _ -> True; _ -> False
    failed message = continue world (advanceUtterance ranking) (pretty sentence ++ "\n  " ++ message)
    continue updated updatedRanking answer =
      let (finalWorld, finalRanking, pending, feedback) = evaluateRemaining updated updatedRanking [] rest
      in (finalWorld, finalRanking, pending, answer ++ if null feedback then "" else "\n" ++ feedback)

evaluateResolved :: World -> [Identifier] -> Sentence -> (World, [String], [[Property]])
evaluateResolved world [first, second] (Swapping left right) =
  let (updated, feedback) = evaluateAtomicSentence world
        (Performative (Swap (ById first) (ById second)))
      properties identifier subject = descriptorsOf subject ++
        [P position | World objects <- [updated], object <- objects,
                      idOf object == identifier, Just position <- [positionOf object]]
  in (updated, [pretty (feedbackAnswer feedback)], [properties first left, properties second right])
evaluateResolved world [identifier] sentence = case sentence of
  Attribution subject properties ->
    let initialProperties = case subject of Indefinite descriptors -> descriptors; _ -> []
        step (current, answers) property =
          let (updated, feedback) = evaluateAtomicSentence current (Performative (AP reference property))
          in (updated, answers ++ [pretty (feedbackAnswer feedback)])
        (updated, answers) = foldl step (world, []) (initialProperties ++ properties)
    in (updated, answers, [descriptorsOf subject ++ properties])
  AttributeRemoval subject attribute -> structural (RemoveAttribute reference attribute) subject
  Removal subject -> structural (Remove reference) subject
  Deletion subject -> structural (Delete reference) subject
  Swapping _ _ -> (world, ["Expected two objects"], [])
  Check subject property ->
    let (_, feedback) = evaluateAtomicSentence world (PropertyCheck (APC reference property))
    in (world, [pretty (feedbackAnswer feedback)], [descriptorsOf subject ++ [property]])
  Query attribute subject ->
    let (_, feedback) = evaluateAtomicSentence world (PropertyQuery (APQ attribute reference))
        associated = case feedbackAnswer feedback of
          QueryAnswerValue (PropertyValue property) -> [property]
          QueryAnswerValue (RowValue _) -> positionProperty
          QueryAnswerValue (ColumnValue _) -> positionProperty
          _ -> []
        positionProperty = [P position | World objects <- [world], object <- objects,
                             idOf object == identifier, Just position <- [positionOf object]]
    in (world, [pretty (feedbackAnswer feedback)], [descriptorsOf subject ++ associated])
  _ -> (world, ["Unsupported derived sentence"], [])
  where
    reference = ById identifier
    structural performative subject =
      let (updated, feedback) = evaluateAtomicSentence world (Performative performative)
      in (updated, [pretty (feedbackAnswer feedback)], [descriptorsOf subject])
evaluateResolved world _ _ = (world, ["Invalid operand count"], [])

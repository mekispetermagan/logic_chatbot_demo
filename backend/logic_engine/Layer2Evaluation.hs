module Layer2Evaluation where

import Data.List (intercalate)
import Discourse
import Ontology
import Layer2Syntax
import AtomicSentence
import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import AtomicSquareCheck
import AtomicEvaluation
import DomainLibrary
import Domains.Objects.Library (objectsLibrary)
import Pretty

-- A continuation does not begin another entry or age a paused utterance twice.
evaluateEntryIn :: DomainLibrary -> World -> SalienceRanking -> [Sentence] -> (World, SalienceRanking, Maybe Pending, String)
evaluateEntryIn library world ranking = (evaluateRemainingIn library) world (beginEntry ranking) []

resumeEntryIn :: DomainLibrary -> World -> SalienceRanking -> Pending -> Identifier -> (World, SalienceRanking, Maybe Pending, String)
resumeEntryIn library world ranking pending@SquarePending{} _ = (world, ranking, Just pending, "Choose a square")
resumeEntryIn library world ranking pending identifier
  | identifier `elem` candidateIds pending = (evaluateRemainingIn library) world ranking
      (resolvedSubjects pending ++ [identifier]) (remainingSentences pending)
  | otherwise = (world, ranking, Just pending, "Choose one of the listed objects")

evaluateRemainingIn :: DomainLibrary -> World -> SalienceRanking -> [Identifier] -> [Sentence]
                  -> (World, SalienceRanking, Maybe Pending, String)
evaluateRemainingIn library = (evaluateRemainingWithIn library) Nothing

resumeSquareEntryIn :: DomainLibrary -> World -> SalienceRanking -> Pending -> Position -> (World, SalienceRanking, Maybe Pending, String)
resumeSquareEntryIn library world ranking pending@SquarePending{} position
  | position `elem` squareChoices pending = (evaluateRemainingWithIn library) (Just position) world ranking
      (resolvedSubjects pending) (remainingSentences pending)
  | otherwise = (world, ranking, Just pending, "Choose one of the listed squares")
resumeSquareEntryIn library world ranking pending _ = (world, ranking, Just pending, "Choose an object")

evaluateRemainingWithIn :: DomainLibrary -> Maybe Position -> World -> SalienceRanking -> [Identifier] -> [Sentence]
                      -> (World, SalienceRanking, Maybe Pending, String)
evaluateRemainingWithIn library _ world ranking _ [] = (world, ranking, Nothing, "")
evaluateRemainingWithIn library square world ranking supplied sentences@(sentence:rest) =
  resolveOperands world [] supplied (subjectsOf sentence)
  where
    resolveOperands current identifiers _ [] =
      case evaluateDerivedSentence library current identifiers sentence square of
        Just (ChooseSquares positions) -> (world, ranking,
          Just (SquarePending sentences [] identifiers positions), pretty sentence ++ "\n  Which square?")
        Just (DerivedComplete updated answers associated) -> complete identifiers updated answers associated
        Just (DerivedCompleteWithMentions updated answers mentions) -> completeMentions updated answers mentions
        Nothing -> let (updated, answers, associated) = (evaluateResolvedIn library) current identifiers sentence
                   in complete identifiers updated answers associated
    resolveOperands current identifiers (identifier:chosen) (_:subjects)
      | hasId current identifier = resolveOperands current (identifiers ++ [identifier]) chosen subjects
      | otherwise = failed "Object no longer exists"
    resolveOperands current identifiers [] (subject:subjects) =
      case resolveSubjectUsing (propertyTruth library) (mentionProperties library) (ontology library) creates current ranking subject of
        Ambiguous candidates -> (world, ranking, Just (Pending sentences candidates identifiers),
          pretty sentence ++ "\n  Which object?")
        Unresolved message -> failed message
        Resolved resolvedWorld identifier -> resolveOperands resolvedWorld (identifiers ++ [identifier]) [] subjects
    complete identifiers updated answers associated =
      completeMentions updated answers (zip identifiers associated)
    completeMentions updated answers mentions =
      let expanded = [(identifier, concatMap (mentionProperties library) properties) | (identifier, properties) <- mentions]
          updatedRanking = mentionManyWith (propertyTruth library) updated expanded ranking
      in continue updated updatedRanking (pretty sentence ++ "\n  " ++ intercalate "\n  " answers)
    creates = case sentence of Attribution _ _ -> True; _ -> False
    failed message = continue world (advanceUtterance ranking) (pretty sentence ++ "\n  " ++ message)
    continue updated updatedRanking answer =
      let (finalWorld, finalRanking, pending, feedback) = (evaluateRemainingIn library) updated updatedRanking [] rest
      in (finalWorld, finalRanking, pending, answer ++ if null feedback then "" else "\n" ++ feedback)

evaluateResolvedIn :: DomainLibrary -> World -> [Identifier] -> Sentence -> (World, [String], [[Property]])
evaluateResolvedIn _ world [] ClearingWorld =
  (World [], [if world == World [] then "No change" else "World cleared"], [])
evaluateResolvedIn library world [] (SquareOccupancy position) =
  let (_, feedback) = evaluateAtomicSentenceWith (ontology library) world (SquareCheck (ASC position))
  in (world, [pretty (feedbackAnswer feedback)], [])
evaluateResolvedIn library world [first, second] (Swapping left right) =
  let (updated, feedback) = evaluateAtomicSentenceWith (ontology library) world
        (Performative (Swap (ById first) (ById second)))
      properties identifier subject = descriptorsOf subject ++
        [P position | World objects <- [updated], object <- objects,
                      idOf object == identifier, Just position <- [positionOf object]]
  in (updated, [pretty (feedbackAnswer feedback)], [properties first left, properties second right])
evaluateResolvedIn library world [identifier] sentence = case sentence of
  Attribution subject properties ->
    let initialProperties = case subject of Indefinite descriptors -> descriptors; _ -> []
        step (current, answers) property =
          let (updated, feedback) = evaluateAtomicSentenceWith (ontology library) current (Performative (AP reference property))
          in (updated, answers ++ [pretty (feedbackAnswer feedback)])
        (updated, answers) = foldl step (world, []) (initialProperties ++ properties)
    in (updated, answers, [descriptorsOf subject ++ properties])
  AttributeRemoval subject attribute -> structural (RemoveAttribute reference attribute) subject
  Removal subject -> structural (Remove reference) subject
  Deletion subject -> structural (Delete reference) subject
  Swapping _ _ -> (world, ["Expected two objects"], [])
  Check subject property ->
    let (_, feedback) = evaluateAtomicSentenceWith (ontology library) world (PropertyCheck (APC reference property))
    in (world, [pretty (feedbackAnswer feedback)], [descriptorsOf subject ++ [property]])
  Query attribute subject ->
    let (_, feedback) = evaluateAtomicSentenceWith (ontology library) world (PropertyQuery (APQ attribute reference))
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
      let (updated, feedback) = evaluateAtomicSentenceWith (ontology library) world (Performative performative)
      in (updated, [pretty (feedbackAnswer feedback)], [descriptorsOf subject])
evaluateResolvedIn library world _ _ = (world, ["Invalid operand count"], [])

-- Current-domain convenience entry points.
evaluateEntry :: World -> SalienceRanking -> [Sentence] -> (World, SalienceRanking, Maybe Pending, String)
evaluateEntry = evaluateEntryIn objectsLibrary
resumeEntry :: World -> SalienceRanking -> Pending -> Identifier -> (World, SalienceRanking, Maybe Pending, String)
resumeEntry = resumeEntryIn objectsLibrary
evaluateRemaining :: World -> SalienceRanking -> [Identifier] -> [Sentence] -> (World, SalienceRanking, Maybe Pending, String)
evaluateRemaining = evaluateRemainingIn objectsLibrary
resumeSquareEntry :: World -> SalienceRanking -> Pending -> Position -> (World, SalienceRanking, Maybe Pending, String)
resumeSquareEntry = resumeSquareEntryIn objectsLibrary
evaluateRemainingWith :: Maybe Position -> World -> SalienceRanking -> [Identifier] -> [Sentence] -> (World, SalienceRanking, Maybe Pending, String)
evaluateRemainingWith = evaluateRemainingWithIn objectsLibrary
evaluateResolved :: World -> [Identifier] -> Sentence -> (World, [String], [[Property]])
evaluateResolved = evaluateResolvedIn objectsLibrary

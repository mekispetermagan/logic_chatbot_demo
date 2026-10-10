module Discourse where

import Data.List (nub, sortOn)
import Ontology
import Layer2Syntax
import ReferenceResolution
import Result

-- Ages are relative to the current entry and its last completed utterance.
type SalienceRanking = [((Int, Int), Identifier, [Property])]

data Resolution = Resolved World Identifier | Unresolved String | Ambiguous [Identifier]
  deriving (Eq, Show)

data Pending = Pending
  { remainingSentences :: [Sentence]
  , candidateIds :: [Identifier]
  , resolvedSubjects :: [Identifier]
  }
  | SquarePending
  { remainingSentences :: [Sentence]
  , candidateIds :: [Identifier]
  , resolvedSubjects :: [Identifier]
  , squareChoices :: [Position]
  }
  deriving (Eq, Show)

holds :: Object -> Property -> Bool
holds object property = case property of
  C color -> colorOf object == Just color
  S size -> sizeOf object == Just size
  Sh shape -> shapeOf object == Just shape
  P position -> positionOf object == Just position

purge :: World -> SalienceRanking -> SalienceRanking
purge (World objects) ranking =
  [(age, identifier, filter (holds object) properties)
  | (age, identifier, properties) <- ranking
  , object <- objects, idOf object == identifier]

-- Retain the current entry and this many preceding entries.
previousEntryLimit :: Int
previousEntryLimit = 3

beginEntry :: SalienceRanking -> SalienceRanking
beginEntry ranking = [((entry + 1, utterance), identifier, properties)
  | ((entry, utterance), identifier, properties) <- ranking, entry < previousEntryLimit]

advanceUtterance :: SalienceRanking -> SalienceRanking
advanceUtterance ranking =
  [((entry, if entry == 0 then utterance + 1 else utterance), identifier, properties)
  | ((entry, utterance), identifier, properties) <- ranking]

mention :: World -> Identifier -> [Property] -> SalienceRanking -> SalienceRanking
mention world identifier properties = mentionMany world [(identifier, properties)]

-- All operands of one utterance share recency; do not age once per operand.
mentionMany :: World -> [(Identifier, [Property])] -> SalienceRanking -> SalienceRanking
mentionMany world mentions ranking = purge world $
  [((0, 0), identifier, nub properties) | (identifier, properties) <- mentions] ++ advanceUtterance ranking

subjectsOf :: Sentence -> [Subject]
subjectsOf (Attribution subject _) = [subject]
subjectsOf (AttributeRemoval subject _) = [subject]
subjectsOf (Removal subject) = [subject]
subjectsOf (Swapping first second) = [first, second]
subjectsOf (Deletion subject) = [subject]
subjectsOf (StepMove subject _) = [subject]
subjectsOf (RelativeMove subject _ target) = [subject, target]
subjectsOf (NeighborMove subject target) = [subject, target]
subjectsOf (CopyAttribute subject _ target) = [subject, target]
subjectsOf (SpatialQuestion subject _ target) = subject : maybe [] (:[]) target
subjectsOf (CountObjects (Neighboring subject)) = [subject]
subjectsOf (CountObjects _) = []
subjectsOf (CountSquares _) = []
subjectsOf (Quantified _ _ _) = []
subjectsOf (Check subject _) = [subject]
subjectsOf (Query _ subject) = [subject]

descriptorsOf :: Subject -> [Property]
descriptorsOf (Definite properties) = properties
descriptorsOf (Indefinite properties) = properties
descriptorsOf _ = []

resolveSubject :: Bool -> World -> SalienceRanking -> Subject -> Resolution
resolveSubject create world@(World objects) ranking subject = case subject of
  Reference reference -> if create
    then case resolvePerformativeReference world reference of
      Result (updated, object, _) -> Resolved updated (idOf object)
      Message message -> Unresolved message
    else case resolveReference world reference of
      Result object -> Resolved world (idOf object)
      Message message -> Unresolved message
  Indefinite _ | create -> let identifier = nextId world
                          in Resolved (World (emptyObject identifier : objects)) identifier
  Indefinite _ -> Unresolved "Expected an existing object"
  It -> case clean of
    [] -> Unresolved "No antecedent for it"
    _ -> choose [identifier | (age, identifier, _) <- clean, age == minimum [a | (a, _, _) <- clean]]
  Definite properties ->
    let requested = nub properties
        candidates = [(identifier, sum scores)
          | object <- objects, all (holds object) requested
          , let identifier = idOf object
          , let matches property = [10 * entry + utterance
                  | ((entry, utterance), i, mentioned) <- clean, i == identifier, property `elem` mentioned]
          , all (not . null . matches) requested
          , let scores = map (minimum . matches) requested]
    in case sortOn snd candidates of
      [] -> choose [idOf object | object <- objects, all (holds object) requested]
      (_, best):_ -> choose [identifier | (identifier, score) <- candidates, score - best < length requested + 1]
  where
    clean = filter (\((entry, _), _, _) -> entry <= previousEntryLimit) (purge world ranking)
    choose identifiers = case nub identifiers of
      [] -> Unresolved "No matching object"
      [identifier] -> Resolved world identifier
      several -> Ambiguous several

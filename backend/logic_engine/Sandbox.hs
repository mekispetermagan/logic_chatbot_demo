module Sandbox where

import Ontology
import AtomicPerformative
import AtomicParser (parseAtomicSentences)
import AtomicSentence (AtomicSentence)

introductionText :: String
introductionText =
  "#1 on B3. #1 red. #1 medium. #1 bloom. #1 red? color of #1? position of #1?"

introductionSentences :: Either String [AtomicSentence]
introductionSentences = parseAtomicSentences introductionText

revisionText :: String
revisionText =
  "#1 on A1. #1 red. #1 bloom. #1 blue. #1 spark. #1 on H8. " ++
  "#1 red? #1 blue? #1 bloom? shape of #1? row of #1? column of #1?"

revisionSentences :: Either String [AtomicSentence]
revisionSentences = parseAtomicSentences revisionText

partialObjectsText :: String
partialObjectsText =
  "#2 drop. color of #2? size of #2? position of #2? " ++
  "#2 red? #2 drop? color of #99? #99 blue?"

partialObjectsSentences :: Either String [AtomicSentence]
partialObjectsSentences = parseAtomicSentences partialObjectsText

obj     :: Object
obj     = Object (Id 0) (Just Blue) (Just Small) (Just Bloom) (Just (0,0))
obj'    :: Object
obj'    = Object (Id 1) (Nothing) (Just Medium) (Just Spark) (Just (2,1))
obj''   :: Object
obj''   = Object (Id 2) (Just Red) Nothing Nothing (Just (2,2))

world :: World
world = World [obj, obj', obj'']

perf :: AtomicPerformative
perf = AP (ById (Id 0)) (C Green)
perf' :: AtomicPerformative
perf' = AP (ById (Id 1)) (C Green)
perf'' :: AtomicPerformative
perf'' = AP (ById (Id 3)) (C Green)

world' :: World
world' = world `updateWorldWith` perf
world'' :: World
world'' = world' `updateWorldWith` perf'
world''' :: World
world''' = world'' `updateWorldWith` perf''

type SalienceRanking = [(Int, Identifier, [Property])]

sR :: SalienceRanking
sR =
  [ (0, Id 4, [C Red])
  , (1, Id 3, [C Blue, Sh Spark])
  , (1, Id 2, [C Green, Sh Spark])
  , (2, Id 1, [C Green])
  , (3, Id 0, [S Large, Sh Spark])
  ]

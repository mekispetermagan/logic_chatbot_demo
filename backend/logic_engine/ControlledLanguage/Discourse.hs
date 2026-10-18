module ControlledLanguage.Discourse where

import Data.List (nub)
import Ontology
import qualified Discourse as Legacy

-- A location and its occupant are separate discourse referents.
data Referent = ObjectReferent Identifier | SquareReferent Position deriving (Eq,Ord,Show)
type Age = (Int,Int)
type SalienceRanking = [(Age,Referent,[Property])]

previousEntryLimit :: Int
previousEntryLimit = Legacy.previousEntryLimit

beginEntry :: SalienceRanking -> SalienceRanking
beginEntry ranking = [((entry+1,utterance),referent,facts)
  | ((entry,utterance),referent,facts) <- ranking, entry < previousEntryLimit]

advanceUtterance :: SalienceRanking -> SalienceRanking
advanceUtterance ranking = [((entry,if entry == 0 then utterance+1 else utterance),referent,facts)
  | ((entry,utterance),referent,facts) <- ranking]

purgeWith :: (World -> Referent -> Bool) -> (World -> Referent -> Property -> Bool)
          -> World -> SalienceRanking -> SalienceRanking
purgeWith exists truth world ranking = [(age,referent,filter (truth world referent) facts)
  | (age,referent,facts) <- ranking, exists world referent]

mentionManyWith :: (World -> Referent -> Bool) -> (World -> Referent -> Property -> Bool)
                -> World -> [(Referent,[Property])] -> SalienceRanking -> SalienceRanking
mentionManyWith exists truth world mentions ranking = purgeWith exists truth world
  ([((0,0),referent,nub facts) | (referent,facts) <- mentions] ++ advanceUtterance ranking)

objectRanking :: SalienceRanking -> Legacy.SalienceRanking
objectRanking ranking = [(age,identifier,facts) | (age,ObjectReferent identifier,facts) <- ranking]

-- Convenient object-only fixture constructor; production uses the domain evaluator.
mention :: World -> Identifier -> [Property] -> SalienceRanking -> SalienceRanking
mention (World objects) identifier facts ranking =
  [((0,0),ObjectReferent identifier,filter (holdsProperty object) facts) | object <- objects,idOf object == identifier]
  ++ advanceUtterance ranking

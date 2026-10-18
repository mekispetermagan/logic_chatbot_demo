module Domains.Objects.Language.Evaluation
  (module ControlledLanguage.Evaluation, runEntry, editWorld, changesBetween) where
import ControlledLanguage.Evaluation
import ControlledLanguage.Syntax (Entry,Choice)
import Ontology (World)
import ControlledLanguage.Discourse (SalienceRanking)
import qualified WorldEditor as Editor
import Domains.Objects.Definition (objectsDomain)
runEntry :: World -> SalienceRanking -> Int -> Entry -> [Choice] -> Int -> Outcome
runEntry = runEntryWith objectsDomain
editWorld :: Int -> World -> Editor.EditorAction -> (World,Int,String)
editWorld = editWorldWith objectsDomain
changesBetween :: World -> World -> [Change]
changesBetween = changesBetweenWith objectsDomain

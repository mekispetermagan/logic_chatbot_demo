module Domains.Network.Language.Evaluation
  (module ControlledLanguage.Evaluation, runEntry, editWorld, changesBetween) where
import ControlledLanguage.Evaluation
import ControlledLanguage.Syntax (Entry,Choice)
import Ontology (World)
import ControlledLanguage.Discourse (SalienceRanking)
import qualified WorldEditor as Editor
import Domains.Network.Definition (networkDomain)
runEntry :: World -> SalienceRanking -> Int -> Entry -> [Choice] -> Int -> Outcome
runEntry = runEntryWith networkDomain
editWorld :: Int -> World -> Editor.EditorAction -> (World,Int,String)
editWorld = editWorldWith networkDomain
changesBetween :: World -> World -> [Change]
changesBetween = changesBetweenWith networkDomain

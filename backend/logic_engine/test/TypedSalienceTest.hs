module Main where

import Control.Monad (forM_,unless)
import Data.Either (isLeft)
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import Ontology
import Domain (Domain)
import Domains.Objects.Definition (objectsDomain)
import Domains.Network.Definition (networkDomain)
import ControlledLanguage.Syntax
import ControlledLanguage.Parser
import ControlledLanguage.Pretty
import ControlledLanguage.Evaluation
import ControlledLanguage.Discourse

check :: String -> Bool -> IO ()
check name ok = unless ok (fail name)
seed :: World
seed = World [Object (Id 0) (Map.singleton (AttributeId "color") (ValueId "red")) (Just (0,0)),
              Object (Id 1) Map.empty (Just (1,1))]
run :: Domain -> World -> SalienceRanking -> String -> [Choice] -> Outcome
run domain world ranking source choices = case parseEntryWith domain source of
  Left message -> errorWithoutStackTrace message
  Right entry -> runEntryWith domain world ranking 2 entry choices 0
hasSquare :: Position -> SalienceRanking -> Bool
hasSquare p = any (\(_,r,_) -> r==SquareReferent p)
main :: IO ()
main = do
  forM_ [objectsDomain,networkDomain] $ \domain -> do
    let execute = run domain seed []
        occupied = execute "Does A1 satisfy not occupied? Does it satisfy occupied?" []
    check "square pronoun accepts occupancy" (not (resultError occupied) && "\n  false" `isInfixOf` resultFeedback occupied && "\n  true" `isInfixOf` resultFeedback occupied)
    check "square query never mentions its occupant" (all (\(_,r,_) -> r==SquareReferent (0,0)) (resultRanking occupied))
    let noObject = execute "Does A1 satisfy occupied? Set color of it to green." []
        noSquare = execute "Does #0 exist? Does it satisfy occupied?" []
    check "square is not coerced to its occupant" (resultError noObject && resultWorld noObject==seed && "No object antecedent" `isInfixOf` resultFeedback noObject)
    check "object is not coerced to its position" (resultError noSquare && "No square antecedent" `isInfixOf` resultFeedback noSquare)
    let typed = execute "Does #0 exist? Does H8 satisfy occupied? Set color of it to green. Does it satisfy occupied?" []
    check "operand type selects its own antecedent pool" (not (resultError typed) && maybe False ((==Just "green") . (`valueOf` "color")) (objectAtId (resultWorld typed) 0))
    let squareRecent=execute "Does #0 exist? Does C3 satisfy occupied? Does it satisfy at the edge?" []
        objectRecent=execute "Does C3 satisfy occupied? Does #0 exist? Does it satisfy at the edge?" []
    check "polymorphic predicate uses recency across both kinds" ("\n  false" `isInfixOf` resultFeedback squareRecent && not (resultError squareRecent) && "\n  true" `isInfixOf` resultFeedback objectRecent)
    let source="Move #0 to C3. Does it satisfy at the edge?"
        paused=execute source []
    check "equal-age object/square mentions require typed choice" (case resultPause paused of Just (_,_,ids,ps) -> ids==[0] && ps==[(2,2)]; _ -> False)
    let chooseObject=execute source [ObjectChoice 0]
        chooseSquare=execute source [SquareChoice (2,2)]
    check "either mixed choice resumes without conversion" (not (resultError chooseObject) && resultPause chooseObject==Nothing && not (resultError chooseSquare) && resultPause chooseSquare==Nothing)
    let squareTie=execute "Rearrange positions by [#0 to C3, #1 to D4]. Does it satisfy occupied?" []
    check "square-only ambiguity lists squares, not their occupants" (case resultPause squareTie of Just (_,_,ids,ps) -> null ids && ps==[(2,2),(3,3)]; _ -> False)
    let objectTie=execute "Exchange positions of #0 and #1. Set color of it to blue." []
    check "object-only ambiguity remains object-only" (case resultPause objectTie of Just (_,_,ids,ps) -> ids==[0,1] && null ps; _ -> False)
    let moved=execute "Does C3 satisfy not occupied? Move #0 to it. Does it satisfy occupied?" []
        created=execute "Does C3 satisfy not occupied? Create object with color green on it." []
        cloned=execute "Does C3 satisfy not occupied? Clone appearance of #0 into a new object on it." []
    check "square pronouns work in move/create/clone destinations" (all (not . resultError) [moved,created,cloned] && maybe False ((==Just (2,2)) . positionOf) (objectAtId (resultWorld moved) 0))
    let explicit=execute "Does A1 satisfy occupied? Set color of the object at it to green." []
    check "explicit occupant conversion is permitted" (not (resultError explicit) && maybe False ((==Just "green") . (`valueOf` "color")) (objectAtId (resultWorld explicit) 0))
    let headObject=execute "What is the color of the object at A1? Does it satisfy at the edge?" []
    check "nested occupant selector does not invent separate square antecedent" (resultPause headObject==Nothing && not (hasSquare (0,0) (resultRanking headObject)))
    let queried=execute "Does A1 satisfy occupied?" []
        deleted=run domain seed (resultRanking queried) "Delete #0." []
        sqFacts=[p | (_,SquareReferent (0,0),facts) <- resultRanking deleted,p <- facts]
    check "object deletion preserves square mention and purges stale occupancy" (hasSquare (0,0) (resultRanking deleted) && null sqFacts && all (\(_,r,_) -> r/=ObjectReferent (Id 0)) (resultRanking deleted))
    let vacancy=execute "Does C3 satisfy not occupied?" []
        nowOccupied=run domain seed (resultRanking vacancy) "Move #0 to C3." []
    check "movement invalidates vacancy evidence" (not (squareFact (Not Occupied) `elem` [p | (_,SquareReferent (2,2),facts) <- resultRanking nowOccupied,p<-facts]))
    let retained=foldl (\ranking _ -> resultRanking (run domain seed ranking "Does #0 exist?" [])) (resultRanking vacancy) [1..3::Int]
        expired=resultRanking (run domain seed retained "Does #0 exist?" [])
    check "same three-entry window for square mentions" (hasSquare (2,2) retained && not (hasSquare (2,2) expired))
    let batch=execute "Atomically { Move #0 to C3. Move #1 to C3. }." []
    check "atomic failure discards square and object salience together" (resultError batch && null (resultRanking batch) && resultWorld batch==seed)
    forM_ ["Does it satisfy occupied and color is red?","Does A1 satisfy color is red?","Does #0 satisfy occupied?"] $ \source ->
      check "incompatible predicate types remain syntax errors" (isLeft (parseEntryWith domain source))
    forM_ ["Does it satisfy occupied?","Does it satisfy at the edge?","Create object on it.","Move #0 to it.","Which object occupies it?","Set color of the object at it to green."] $ \source ->
      case parseEntryWith domain source of
        Left message -> fail message
        Right entry -> do
          check "surface pronoun round trip" (parseEntryWith domain (entryText entry)==Right entry)
          check "canonical pronoun round trip" (parseCanonicalWith domain (canonicalEntryText entry)==Right entry)
  let connection=run networkDomain seed [] "Does D4 satisfy not occupied? Build shortest connection from it to H8." []
  check "network construction accepts typed endpoint pronouns" (not (resultError connection) && any ((==Just (3,3)) . positionOf) (objectsOf (resultWorld connection)))
  putStrLn "All typed object/square salience checks passed."

module Main where

import Control.Monad (unless,forM_)
import Data.Either (isLeft)
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import Ontology
import ControlledLanguage.Discourse (SalienceRanking,Referent(..))
import Domains.Network.Language
import Domains.Network.Definition (networkDomain)
import qualified Domains.Network.Patterns as P
import qualified Domains.Network.Syntax as N
import qualified Domains.Network.Analysis as A

check :: String -> Bool -> IO ()
check name result = unless result (fail name)
node :: Int -> Maybe String -> String -> Maybe Position -> Object
node n color pattern p = (P.setPorts [port | (port,c) <- zip P.ports pattern, c /= '-']
  (Object (Id n) Map.empty p)) {attributesOf=Map.fromList
    ([(AttributeId "color",ValueId c) | Just c <- [color]] ++
     [(AttributeId (N.portName port),ValueId (N.portName port)) | (port,c) <- zip P.ports pattern, c /= '-'])}
run :: World -> SalienceRanking -> Int -> String -> [Choice] -> Outcome
run w ranking next source choices = case parseEntry source of
  Left message -> errorWithoutStackTrace message
  Right entry -> runEntry w ranking next entry choices 0
at :: Outcome -> Int -> Object
at result identifier = maybe (errorWithoutStackTrace "Missing object") id (objectAtId (resultWorld result) identifier)
answer :: World -> String -> String
answer w source = resultFeedback (run w [] (1+maximum (-1:map (idToInt . idOf) (objectsOf w))) source [])
checksAnswer :: World -> String -> String -> Bool
checksAnswer w source expected = ("\n  " ++ expected) `isInfixOf` answer w source
examples :: [String] -> [String]
examples [] = []
examples ("```text":rest) = let (block,after)=break (== "```") rest in unlines block:examples (drop 1 after)
examples (_:rest) = examples rest

main :: IO ()
main = do
  source <- readFile "../../specification/network-language-v2.md"
  forM_ (examples (lines source)) $ \text -> case parseEntry text of
    Left message -> fail message
    Right entry -> do
      check "document examples round trip canonically" (parseEntry (canonicalEntryText entry) == Right entry)
      check "document examples round trip in readable form" (parseEntry (entryText entry) == Right entry)
  let empty = World []
  forM_ (sequence [[c,'-'] | c <- "nesw"]) $ \pattern -> do
    let result=run empty [] 7 ("Create object with pattern " ++ pattern ++ " on C4. What is the pattern of it?") []
    check "all sixteen patterns create/query exactly" (not (resultError result) && patternOf (at result 7)==pattern && resultNextId result==8)
  forM_ ["A4 red.","#3 red?","Create object with pattern ne on A4.","Create object with pattern ur-- on A4.",
         "Open up port of #3.","Set color of A4 to red.","Create object on A4","Undo ignored.",
         "Does #3 satisfy size is large?","Does #3 satisfy color is blue.","Atomically { Does #3 exist? }.",
         "Does some object matching color is red satisfy connected to a blue object?",
         "Does every object matching color is red satisfy some object matching color is blue?"] $ \text ->
    check ("strict syntax: "++text) (isLeft (parseEntry text))
  let seed=World [node 0 (Just "green") "----" (Just (0,0)),node 1 (Just "red") "----" (Just (3,0))]
      built=run seed [] 7 "Build shortest connection from #0 to #1 with route color blue." []
  check "dot endpoints open necessary ports" (patternOf (at built 0)=="-e--" && patternOf (at built 1)=="---w")
  check "persistent allocation creates intermediates" (resultNextId built == 9 && all (hasId (resultWorld built) . Id) [7,8])
  check "all route colors overwritten deliberately" (all ((== Just "blue") . (`valueOf` "color")) (objectsOf (resultWorld built)))
  check "intermediates are not discourse antecedents" (all (\(_,identifier,_) -> case identifier of ObjectReferent n -> n `elem` [Id 0,Id 1]; SquareReferent _ -> True) (resultRanking built))
  let next=run (resultWorld built) [] 9 "Build shortest connection from D1 to D4." []
  check "incremental drawing preserves old endpoint ports" (patternOf (at next 1)=="n--w" && valueOf (at next 1) "color"==Just "blue")
  check "uncolored extension route creates colorless nodes" (all ((==Nothing) . (`valueOf` "color")) [at next n | n <- [9,10,11]])
  check "distance inspects existing links" (checksAnswer (resultWorld next) "What is the distance from #0 to the object at D4?" "6")
  let wrongIntermediate=World [node 0 Nothing "----" (Just (0,0)), node 1 (Just "green") "----" (Just (1,0)), node 2 Nothing "----" (Just (2,0))]
      detour=run wrongIntermediate [] 3 "Build shortest connection from #0 to #2 with route color blue." []
  check "planner routes around an incompatible intermediate without changing it" (Just (at detour 1) == objectAtId wrongIntermediate 1 && "(4 steps)" `isInfixOf` resultFeedback detour)
  let closedWall=World [node 0 Nothing "----" (Just (0,0)),node 1 Nothing "----" (Just (2,0))] -- surround source except target direction
      wall=World (objectsOf closedWall ++ [node (2+y) Nothing "----" (Just (1,y)) | y <- [0..7]])
      failed=run wall [] 10 "Build shortest connection from #0 to #1 with route color blue." []
  check "no path rolls back endpoint ports and colors" (resultError failed && resultWorld failed==wall && resultNextId failed==10)
  let same=run empty [] 40 "Build shortest connection from A1 to A1 with route color yellow." []
  check "same-square construction creates a colored dot" (patternOf (at same 40)=="----" && valueOf (at same 40) "color"==Just "yellow" && resultNextId same==41)
  let colorIntermediate=World [node 0 Nothing "----" (Just (0,0)),node 1 (Just "green") "-e-w" (Just (1,0)),node 2 Nothing "----" (Just (2,0))]
      recolored=run colorIntermediate [] 3 "Build shortest connection from #0 to #2 with route color blue." []
  check "valid green midpoint is recolored without port changes" (valueOf (at recolored 1) "color"==Just "blue" && patternOf (at recolored 1)=="-e-w")
  let linked=run seed [] 7 "Move #1 to B1. Link #0 to #1." []
      oneClosed=run (resultWorld linked) [] 7 "Close east port of #0." []
      unlinked=run (resultWorld linked) [] 7 "Unlink #0 from #1." []
  check "single-port close does not repair neighbor" (patternOf (at oneClosed 1)=="---w")
  check "unlink closes both facing ports" (patternOf (at unlinked 0)=="----" && patternOf (at unlinked 1)=="----")
  check "unlink is idempotent" (resultWorld (run (resultWorld unlinked) [] 7 "Unlink #0 from #1." [])==resultWorld unlinked)
  let extended=run (World [node 0 (Just "green") "----" (Just (0,0))]) [] 9 "Extend #0 north." []
  check "extension creates and inherits color" (patternOf (at extended 0)=="n---" && patternOf (at extended 9)=="--s-" && valueOf (at extended 9) "color"==Just "green")
  let occupied=run (resultWorld extended) [] 10 "Extend #0 north." []
  check "occupied extension fails without allocation" (resultError occupied && resultWorld occupied==resultWorld extended && resultNextId occupied==10)
  let patterns=World [node 0 Nothing "----" Nothing,node 1 (Just "red") "nesw" Nothing]
      copied=run patterns [] 2 "Copy pattern from #0 to #1." []
      appearanceCopied=run patterns [] 2 "Copy appearance from #0 to #1." []
  check "pattern copy clears ports but preserves color" (patternOf (at copied 1)=="----" && valueOf (at copied 1) "color"==Just "red")
  check "appearance copy includes color absence" (valueOf (at appearanceCopied 1) "color"==Nothing)
  let rotation=run (World [node 0 (Just "red") "n---" (Just (3,3))]) [] 1 "Rotate drawing of objects [#0] by 90 degrees clockwise about the center of rectangle D4 to E5." []
  check "drawing rotation moves identity and ports" (positionOf (at rotation 0)==Just (3,4) && patternOf (at rotation 0)=="-e--" && valueOf (at rotation 0) "color"==Just "red")
  let positionOnly=run (World [node 0 Nothing "n---" (Just (3,3))]) [] 1 "Rotate positions of objects [#0] by 90 degrees clockwise about the center of rectangle D4 to E5." []
  check "position rotation does not rotate ports" (patternOf (at positionOnly 0)=="n---")
  let cycleWorld=World [node 0 (Just "blue") "ne--" (Just (0,0)),node 1 (Just "blue") "ne-w" (Just (1,0)),
                        node 2 (Just "blue") "--sw" (Just (1,1)),node 3 (Just "blue") "-es-" (Just (0,1)),
                        node 4 (Just "blue") "---w" (Just (2,0))]
  forM_ [("Does #0 satisfy on a cycle?","true"),("Does #4 satisfy on a cycle?","false"),
         ("Does the component of #4 satisfy cyclic?","true"),("Does #1 satisfy articulation?","true"),
         ("Does #4 satisfy articulation?","false"),("Does the link between #1 and #4 satisfy bridge?","true"),
         ("Does the link between #0 and #1 satisfy bridge?","false"),
         ("Does the network satisfy forest?","false"),("Does the network satisfy monochromatic with color blue?","true"),
         ("Does the network satisfy properly colored?","false"),("What is the degree of #1?","3"),
         ("How many links in the network?","5"),("What is the distance from #0 to #0?","0")] $ \(question,expected) ->
    check ("graph query: " ++ question) (checksAnswer cycleWorld question expected)
  let mixed=World [if idOf o `elem` [Id 0,Id 2] then setAttribute (AttributeId "color") (Just (ValueId "green")) o else o | o <- objectsOf cycleWorld]
      whole="Does the component of #1 satisfy tree and monochromatic with color blue?"
      blueRegion="Does the component of #1 within the subgraph of the network induced by objects matching color is blue satisfy tree?"
      blueSubgraph="Does the subgraph of the component of #1 induced by objects matching color is blue satisfy tree?"
  check "three blue-component constructions differ" (checksAnswer mixed whole "false" && checksAnswer mixed blueRegion "true" && checksAnswer mixed blueSubgraph "false")
  check "filtering a component allows non-blue seed" (checksAnswer mixed "Does the subgraph of the component of #0 induced by objects matching color is blue satisfy forest?" "true")
  check "filtered component rejects excluded seed" (resultError (run mixed [] 5 "Does the component of #0 within the subgraph of the network induced by objects matching color is blue satisfy tree?" []))
  check "induction evaluates degree against input, no fixed point" (checksAnswer cycleWorld "How many objects in the subgraph of the network induced by objects matching junction?" "1")
  check "scoped endpoint differs from global junction" (checksAnswer mixed "Does #1 satisfy endpoint within the subgraph of the network induced by objects matching color is blue?" "true" && checksAnswer mixed "Does #1 satisfy junction?" "true")
  let scoped=run mixed [] 5 "Does #1 satisfy endpoint within the subgraph of the network induced by objects matching color is blue?" []
      changed=run mixed (resultRanking scoped) 5 "Set color of #4 to red." []
      oldFacts=[p | (_,identifier,ps) <- resultRanking scoped, identifier==ObjectReferent (Id 1),p@(Defined _) <- ps]
  check "contextual mentions are purged after remote color change" (not (null oldFacts) && all (not . truthFor networkDomain (resultWorld changed) (at changed 1)) oldFacts)
  forM_ [("Does the network satisfy forest?","true"),("Does the network satisfy connected?","false"),
         ("Does the network satisfy tree?","false"),("Does the network satisfy properly colored?","true"),
         ("Does the network satisfy monochromatic?","false"),("How many components in the network?","0")] $ \(q,expected) ->
    check "empty graph laws" (checksAnswer empty q expected)
  let unplaced=World [node 0 Nothing "----" Nothing]
  check "unplaced intrinsic and graph facts differ" (checksAnswer unplaced "Does #0 satisfy dot?" "true" && checksAnswer unplaced "Does #0 satisfy isolated?" "false")
  check "unplaced negation stays Boolean" (checksAnswer unplaced "How many objects match not isolated?" "1")
  check "degree of unplaced object is diagnostic" (resultError (run unplaced [] 1 "What is the degree of #0?" []))
  let batch=run seed [] 7 "Atomically { Set color of #0 to red. Move #0 to D1. }." []
  check "batch failure restores world and ranking" (resultError batch && resultWorld batch==seed && resultRanking batch==[])
  let ambiguous="Does #0 satisfy endpoint or junction and color is red?"
  check "Boolean ambiguity exposes two readings" (case parseEntryAlternatives ambiguous of Right readings -> length readings==2; _ -> False)
  let two=World [node 0 (Just "red") "----" Nothing,node 1 (Just "red") "----" Nothing]
      question="Set pattern of the unique object matching color is red to ne--."
      paused=run two [] 2 question []
      resumed=run two [] 2 question [ObjectChoice 1]
  check "reference choice pauses without mutation" (resultPause paused/=Nothing && resultWorld paused==two)
  check "reference choice resumes correct identity" (patternOf (at resumed 1)=="ne--" && patternOf (at resumed 0)=="----")
  putStrLn "All network v2 language checks passed."

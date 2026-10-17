module Main where

import Control.Monad (unless)
import Data.Either (isLeft)
import Data.List (isInfixOf, find)
import qualified Data.Map.Strict as Map
import Ontology
import Domain
import Pretty
import Discourse
import Layer2Syntax
import Layer2Parser
import Layer2Evaluation
import Domains.Network.Definition
import Domains.Network.Library
import Domains.Network.Graph
import Domains.Network.Patterns
import qualified Domains.Network.Syntax as N

check :: String -> Bool -> IO ()
check name condition = unless condition (fail name)
parse :: String -> [Sentence]
parse = either error id . parseSentencesWith networkLibrary
run :: World -> String -> (World, SalienceRanking, Maybe Pending, String)
run world text = evaluateEntryIn networkLibrary world [] (parse text)
newWorld :: String -> World
newWorld text = let (world,_,pending,_) = run (World []) text in
  if pending == Nothing then world else error "Unexpected clarification"
item :: World -> Int -> Object
item (World objects) identifier = maybe (error "Missing test object") id (find ((== Id identifier) . idOf) objects)
feedback :: World -> String -> String
feedback world text = let (_,_,_,message) = run world text in message

main :: IO ()
main = do
  check "extended ontology validates" (validateDomain networkDomain == Right networkDomain)
  let source = newWorld "#0 red nesw on A1. #1 blue."
      added = newWorld "A1 s. A1 ne."
      exact = newWorld "A1 nesw. A1 ur--."
  check "positive pattern is additive" (openPorts (item added 0) == [N.North,N.East,N.South])
  check "four slots clear omitted ports" (openPorts (item exact 0) == [N.North,N.East])
  check "exact and positive checks differ"
    ("true" `isInfixOf` feedback added "A1 ne?" && "false" `isInfixOf` feedback added "A1 ne--?")
  let rotated = newWorld "A1 red ne--. Rotate A1 clockwise."
      reflected = newWorld "A1 red ne--. Flip A1 horizontally. Flip A1 vertically."
  check "clockwise rotation preserves color and position"
    (openPorts (item rotated 0) == [N.East,N.South] && positionOf (item rotated 0) == Just (0,0) && attributeOf (AttributeId "color") (item rotated 0) == Just (ValueId "red"))
  check "reflection changes only relevant ports" (openPorts (item reflected 0) == [N.South,N.West])
  check "counterclockwise reverses rotation"
    (let (world,_,_,_) = run rotated "Rotate A1 counterclockwise." in openPorts (item world 0) == [N.North,N.East])
  let (copied,_,_,_) = run source "Make #0 the same as #1."
  check "copying null pattern clears source only"
    (null (openPorts (item copied 0)) && attributeOf (AttributeId "color") (item copied 0) == Just (ValueId "red"))
  let graph = newWorld "A1 red ----. Link A1 right. Extend B1 up."
  check "extension creates facing port and inherits color"
    (map (openPorts . item graph) [0,1,2] == [[N.East],[N.North,N.West],[N.South]] && all (\i -> attributeOf (AttributeId "color") (item graph i) == Just (ValueId "red")) [0,1,2])
  check "matching reciprocal ports form graph"
    (length (neighbors graph (item graph 1)) == 2 && distance graph Nothing (item graph 0) (item graph 2) == Just 2)
  check "reachability reflexive only when placed"
    (distance graph Nothing (item graph 0) (item graph 0) == Just 0 && distance source Nothing (item source 1) (item source 1) == Nothing)
  check "colored reachability includes endpoints"
    (distance graph (Just (ValueId "red")) (item graph 0) (item graph 2) == Just 2 && distance graph (Just (ValueId "blue")) (item graph 0) (item graph 2) == Nothing)
  let (blocked,_,_,_) = run graph "Extend A1 west."
  check "outside extension atomic no change" (blocked == graph)
  let (idempotent,_,_,_) = run graph "Link A1 right."
  check "occupied neighbor used without creation" (idempotent == graph)
  let (disconnected,_,_,_) = run graph "Disconnect A1 right."
  check "disconnect closes both facing ports" (not (hasPort (item disconnected 0) N.East) && not (hasPort (item disconnected 1) N.West))
  let emptyNeighbor = newWorld "A1 ne--. Disconnect A1 north."
  check "disconnect absent neighbor still closes source port" (openPorts (item emptyNeighbor 0) == [N.East])
  check "disconnect outward port closes source at board edge"
    (null (openPorts (item (newWorld "A1 w. Disconnect A1 west.") 0)))
  check "nonadjacent pair link leaves state intact"
    (let (world,_,_,_) = run graph "Link A1 to B2." in world == graph)
  let trim = newWorld "A1 nesw. B1 w. Remove unmatched ports from A1."
  check "trim removes only unmatched ports"
    (openPorts (item trim 0) == [N.East] && openPorts (item trim 1) == [N.West])
  let (colored,_,_,_) = run graph "Color the component of A1 blue."
  check "component coloring determines members before mutation"
    (all (\i -> attributeOf (AttributeId "color") (item colored i) == Just (ValueId "blue")) [0,1,2])
  let mixed = newWorld "A1 red e. B1 blue w. #2 red ----. #3 ---- on H8."
  check "dots isolated components, unplaced excluded" (length (components mixed) == 2)
  check "unplaced graph predicates false and numbers diagnose"
    ("false" `isInfixOf` feedback mixed "#2 isolated?" && "not on the board" `isInfixOf` feedback mixed "How many connections does #2 have?")
  check "intrinsic unplaced properties still true" ("true" `isInfixOf` feedback mixed "#2 dot?")
  check "degree distance component queries"
    ("\n  2" `isInfixOf` feedback graph "How many connections does B1 have?" &&
     "\n  2" `isInfixOf` feedback graph "What is the distance from A1 to B2?" &&
     "no path" `isInfixOf` feedback mixed "What is the distance from A1 to H8?")
  mapM_ (\text -> do
    check ("distance alias parse: " ++ text)
      (parseSentencesWith networkLibrary text == parseSentencesWith networkLibrary "What is the distance from A1 to B2?")
    check ("distance alias evaluation: " ++ text)
      (feedback graph text == "distance A1 to B2?\n  2"))
    ["Distance from A1 to B2?", "DISTANCE A1 TO B2?"]
  check "distance keeps required separator, question mark and existing-reference operands"
    (all (isLeft . parseSentencesWith networkLibrary)
      ["Distance A1 B2?", "Distance A1 to B2.", "Distance A1 to a red object?"])
  check "descriptor counts include unplaced intrinsic matches"
    ("\n  2" `isInfixOf` feedback mixed "How many dots?" && "\n  2" `isInfixOf` feedback mixed "How many red objects?")
  check "filtered relational counts use fixed target"
    ("\n  3" `isInfixOf` feedback graph "How many red objects are connected to A1?" &&
     "\n  2" `isInfixOf` feedback graph "How many red endpoints?")
  check "quantified clauses and vacuous explanations"
    ("true" `isInfixOf` feedback graph "Is every red object connected to A1 and on the board?" &&
     "false" `isInfixOf` feedback graph "Are some red objects unmatched?" &&
     "true — no matching objects" `isInfixOf` feedback graph "Is every yellow object unmatched?")
  check "computed definite resolves unique object"
    (let (world,_,pending,_) = run graph "The red bend is blue." in pending == Nothing && attributeOf (AttributeId "color") (item world 1) == Just (ValueId "blue"))
  check "computed indefinite creation is rejected"
    (all (isLeft . parseSentencesWith networkLibrary) ["A bend on A4.","A red endpoint on A4.","A4 is isolated."])
  check "explicit exact indefinite creation permitted"
    (openPorts (item (newWorld "A red ne-- on A4.") 0) == [N.North,N.East])
  let (mentioned,ranking,_,_) = run graph "A1 endpoint?"
      (changed,ranking',_,_) = evaluateEntryIn networkLibrary mentioned ranking (parse "Disconnect B1 left.")
  check "neighbor changes purge obsolete graph facts"
    (not (networkHolds changed (item changed 0) (Defined "endpoint")) &&
     all (\(_,identifier,props) -> identifier /= Id 0 || Defined "endpoint" `notElem` props) ranking')
  let (pausedWorld,pausedRanking,paused,_) = run graph "#0 yellow. Color the component of the endpoint green."
  check "ambiguity pauses exact operation retaining previous sentence"
    (attributeOf (AttributeId "color") (item pausedWorld 0) == Just (ValueId "yellow") && paused /= Nothing)
  case paused of
    Nothing -> fail "expected ambiguity"
    Just pending -> do
      let (resumed,_,done,_) = resumeEntryIn networkLibrary pausedWorld pausedRanking pending (Id 2)
      check "component recoloring resumes atomically" (done == Nothing && all (\i -> attributeOf (AttributeId "color") (item resumed i) == Just (ValueId "green")) [0,1,2])
  let forms = ["Rotate #0 clockwise.","Flip #0 vertically.","Make #0 the same pattern as #1.",
        "Link #0 east.","Disconnect #0 from #1.","Remove unmatched ports from #0.",
        "Color the component of #0 blue.","How many components?","How many red endpoints?",
        "How many red objects are connected to #0 by a red path?","What is the distance from #0 to #1?",
        "Distance from #0 to #1?", "Distance it to the red bend?",
        "Is #0 a dead end?","Is the red bend an endpoint?","Is #0 linked to #1?",
        "Is every red object connected to #0 by a red path and unmatched?","#0 ne--.","#0 ur--?",
        "Move #0 north.","Move #0 next to #1.","Does #0 have an unmatched port?"]
  mapM_ (\text -> do
    let sentences = parse text
    check ("pretty/parser round trip: " ++ text)
      (parseSentencesWith networkLibrary (unwords (map pretty sentences)) == Right sentences)) forms
  check "cycles and indefinite graph targets rejected"
    (all (isLeft . parseSentencesWith networkLibrary) ["#0 on a cycle?","#0 connected to a red object?","#0 red and bend?"])
  putStrLn "All network Layer 3 checks passed."

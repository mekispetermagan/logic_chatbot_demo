module Main where

import Control.Monad (unless)
import Data.Either (isLeft)
import Data.List (find, isInfixOf, nub)
import qualified Data.Map.Strict as Map
import Ontology
import Pretty
import Discourse
import Layer2Parser
import Layer2Evaluation
import Domains.Network.Library
import Domains.Objects.Library
import Domains.Network.Patterns
import qualified Domains.Network.Graph as Graph
import qualified Domains.Network.Pathfinding as Path
import qualified Domains.Network.Syntax as N

check :: String -> Bool -> IO ()
check name condition = unless condition (fail name)

parse = either error id . parseSentencesWith networkLibrary
run world = evaluateEntryIn networkLibrary world [] . parse
empty = World []
worldOf text = let (world,_,pending,_) = run empty text in
  if pending == Nothing then world else error "Unexpected pending entry"
at world position = maybe (error "Missing object") id (Graph.atPosition world position)
objects (World values) = values
color object = attributeOf (AttributeId "color") object

main :: IO ()
main = do
  check "north before east for equal shortest routes"
    (Path.shortestConnectionPath empty (0,0) (1,1) == Just [(0,0),(0,1),(1,1)])
  check "south before west for equal shortest routes"
    (Path.shortestConnectionPath empty (2,2) (1,1) == Just [(2,2),(2,1),(1,1)])
  check "empty opposite corners have length fourteen"
    (fmap length (Path.shortestConnectionPath empty (0,0) (7,7)) == Just 15)
  check "invalid endpoints, including identical ones, are rejected"
    (all (\p -> Path.shortestConnectionPath empty p p == Nothing &&
                Path.shortestConnectionPath empty p (0,0) == Nothing &&
                Path.shortestConnectionPath empty (0,0) p == Nothing)
         [(-1,0),(0,-1),(8,0),(0,8)])
  let obstacle = worldOf "B1 ----."
  check "shortest route goes around closed node"
    (Path.shortestConnectionPath obstacle (0,0) (2,0) == Just [(0,0),(0,1),(1,1),(2,1),(2,0)])
  let barrier = World [(Path.nesw (1,y)) {idOf = Id y, attributesOf = Map.empty} | y <- [0..7]]
  check "closed barrier makes route impossible"
    (Path.createConnection barrier (0,0) (2,0) Nothing == Nothing)
  let mismatch = worldOf "A1 e. B1 ns."
  check "both ports required, outgoing port cannot be invented"
    (Path.shortestConnectionPath mismatch (0,0) (1,1) == Nothing)
  let existing = worldOf "#10 red ew on B1. #20 yellow. H8 green nesw."
      (built,_,pending,_) = run existing "Connect A1 to C1."
  check "empty endpoints and existing through-node create connection"
    (pending == Nothing && length (objects built) == 5 &&
     Graph.distance built Nothing (at built (0,0)) (at built (2,0)) == Just 2)
  check "all original objects survive unchanged without color request"
    (all (`elem` objects built) (objects existing))
  check "new nodes colorless with exact necessary ports and fresh ids"
    (openPorts (at built (0,0)) == [N.East] && openPorts (at built (2,0)) == [N.West] &&
     color (at built (0,0)) == Nothing && color (at built (2,0)) == Nothing &&
     all ((> 20) . idToInt . idOf) [at built (0,0),at built (2,0)] &&
     length (nub (map idOf (objects built))) == length (objects built))
  let (repeated,_,_,repeatFeedback) = run built "Connect A1 to C1."
  check "repeated connection idempotent" (repeated == built && "No change" `isInfixOf` repeatFeedback)
  let (blue,_,_,_) = run existing "Connect A1 to C1 with blue."
  check "explicit color covers existing and new route nodes"
    (all ((== Just (ValueId "blue")) . color . at blue) [(0,0),(1,0),(2,0)] &&
     attributesOf (at blue (1,0)) == Map.fromList
       [(AttributeId "color",ValueId "blue"),(AttributeId "east",ValueId "east"),(AttributeId "west",ValueId "west")])
  check "off-route and unplaced colors unaffected"
    (at blue (7,7) == at existing (7,7) &&
     find ((== Id 20) . idOf) (objects blue) == find ((== Id 20) . idOf) (objects existing))
  let single = worldOf "Connect H1 to H1."
  check "same empty square creates a colorless dot"
    (length (objects single) == 1 && null (openPorts (at single (7,0))) && color (at single (7,0)) == Nothing)
  check "same occupied square unchanged by default"
    (let (updated,_,_,_) = run single "Connect H1 to H1." in updated == single)
  check "same square explicit color creates colored dot"
    (color (at (worldOf "Connect H1 to H1 with yellow.") (7,0)) == Just (ValueId "yellow"))
  let closed = worldOf "A1 red ----."
      (failed,_,_,failure) = run closed "Connect A1 to H8 with blue."
  check "failed path neither creates nor recolors"
    (failed == closed && "No path" `isInfixOf` failure)
  check "unplaced endpoint diagnosed before creating anything"
    (let original = worldOf "#0 red."
         (updated,_,_,message) = run original "Connect A1 to #0."
     in updated == original && "not on the board" `isInfixOf` message)
  check "missing identifier never creates an endpoint"
    (let (updated,_,_,_) = run empty "Connect A1 to #9." in updated == empty)
  let (bent,ranking,_,_) = run empty "Connect A1 to B2 with green."
  check "new bend has only route ports"
    (openPorts (at bent (0,1)) == [N.East,N.South])
  check "salience mentions endpoints, not implicit intermediate nodes"
    (nub [identifier | (_,identifier,_) <- ranking] == [idOf (at bent (0,0)), idOf (at bent (1,1))] &&
     all (\(_,_,properties) -> AttributeValue (AttributeId "color") (ValueId "green") `elem` properties) ranking)
  check "pronoun resolves existing source"
    (let original = worldOf "A1 red e."
         (updated,_,done,_) = evaluateEntryIn networkLibrary original
           [((0,0),Id 0,[])] (parse "Connect it to C1.")
     in done == Nothing && length (objects updated) == 3 && at updated (0,0) == at original (0,0))
  let ambiguous = worldOf "C1 red w. C3 red w."
      (pausedWorld,pausedRanking,paused,_) = run ambiguous "H8 blue. Connect A1 to the red with green."
  check "ambiguous target pauses without creating the empty source"
    (paused /= Nothing && Graph.atPosition pausedWorld (0,0) == Nothing &&
     color (at pausedWorld (7,7)) == Just (ValueId "blue"))
  case paused of
    Nothing -> fail "Expected clarification"
    Just request -> do
      let (updated,_,done,_) = resumeEntryIn networkLibrary pausedWorld pausedRanking request (Id 0)
      check "clarification resumes the complete path operation"
        (done == Nothing && all ((== Just (ValueId "green")) . color . at updated) [(0,0),(1,0),(2,0)] &&
         color (at updated (2,2)) == Just (ValueId "red"))
  let twoObjects = worldOf "A1 e. C1 blue w. C3 blue w."
      (pausedWorld2,pausedRanking2,paused2,_) = run twoObjects "Connect #0 to the blue."
  case paused2 of
    Nothing -> fail "Expected second-operand clarification"
    Just request -> do
      check "resolved source retained" (resolvedSubjects request == [Id 0])
      let (updated,_,done,_) = resumeEntryIn networkLibrary pausedWorld2 pausedRanking2 request (Id 1)
      check "resolved source and clarified target are paired correctly"
        (done == Nothing && Graph.distance updated Nothing (at updated (0,0)) (at updated (2,0)) == Just 2)
  mapM_ (\text -> let sentences = parse text in check ("round trip: " ++ text)
      (parseSentencesWith networkLibrary (unwords (map pretty sentences)) == Right sentences))
    ["Connect A1 to H8.","Connect #0 to the red tip with blue.","Connect it to B3 with green."]
  check "invalid color, indefinite operands, directions and question marks rejected"
    (all (isLeft . parseSentencesWith networkLibrary)
      ["Connect A1 to B2 with purple.","Connect a red to B2.","Connect A1 to B2?","Connect A1 north."])
  check "connect remains network-specific"
    (isLeft (parseSentencesWith objectsLibrary "Connect A1 to B2."))
  putStrLn "All network connection checks passed."

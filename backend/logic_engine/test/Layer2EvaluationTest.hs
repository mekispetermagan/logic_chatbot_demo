module Main where

import Control.Monad (unless)
import Data.List (isInfixOf)
import Discourse
import Layer2Evaluation
import Layer2Syntax
import Layer2Parser
import Ontology

check label condition = unless condition (fail label)
parse text = either error id (parseSentences text)
run w r text = evaluateEntry w r (parse text)
object i color shape = Object (Id i) color Nothing shape Nothing
redCube = object 0 (Just Red) (Just Cube)
blueCube = object 1 (Just Blue) (Just Cube)

main = do
  let empty = World []
      (w1, r1, p1, _) = run empty [] "A red cube on A1. It is blue. Is it red?"
  check "indefinite creates and pronoun updates same object"
    (w1 == World [redCube {colorOf = Just Blue, positionOf = Just (0,0)}] && p1 == Nothing)
  check "false question and old color are purged"
    (all (\(_, _, properties) -> C Red `notElem` properties) r1)
  let (_, _, _, feedback) = run w1 r1 "The cube is large. What is the color of it?"
  check "description and natural query resolve" ("blue" `isInfixOf` feedback)
  let (_, r2, _, _) = run w1 r1 "#0 blue?"
      (_, r3, _, _) = run w1 r2 "#0 cube?"
  check "mentions survive two entry boundaries"
    (any (\((entry,_),_,_) -> entry == 2) r3)
  check "missing pronoun creates nothing" (let (w,_,_,_) = run empty [] "It is red." in w == empty)
  check "missing definite creates nothing" (let (w,_,_,_) = run empty [] "The cube is red." in w == empty)
  let two = World [redCube, blueCube]
      (_, _, ambiguous, _) = run two [] "The cube is small. It is green."
  check "world fallback asks when nonunique" (fmap candidateIds ambiguous == Just [Id 0,Id 1])
  let (resumed, rr, done, answer) = resumeEntry two [] (maybe (error "pending") id ambiguous) (Id 1)
  check "clarification resumes remainder on chosen referent"
    (done == Nothing && colorOf (last (case resumed of World os -> os)) == Just Green && "green" `isInfixOf` answer && not (null rr))
  let ranked = [((0,0),Id 0,[C Red]), ((0,4),Id 0,[Sh Cube]),
                ((0,1),Id 1,[C Red]), ((0,2),Id 1,[Sh Cube])]
      allRed = World [redCube,redCube {idOf=Id 1}]
  check "combined close scores ask" (resolveSubject False allRed ranked (Definite [C Red,Sh Cube]) == Ambiguous [Id 0,Id 1])
  let distinct = [((0,0),Id 0,[Sh Cube]),((0,4),Id 1,[Sh Cube])]
  check "clear score winner" (resolveSubject False two distinct (Definite [Sh Cube]) == Resolved two (Id 0))
  check "pronoun tied distinct objects asks" (resolveSubject False two [((0,0),Id 0,[]),((0,0),Id 1,[])] It == Ambiguous [Id 0,Id 1])
  check "third previous entry remains anaphorically eligible"
    (resolveSubject False two [((3,0),Id 0,[Sh Cube])] (Definite [Sh Cube]) == Resolved two (Id 0))
  check "fourth previous entry does not supply anaphoric candidate"
    (resolveSubject False two [((4,0),Id 0,[Sh Cube])] (Definite [Sh Cube]) == Ambiguous [Id 0,Id 1])
  check "entry aging retains ages one through three and drops four"
    (beginEntry [((age,0),Id 0,[]) | age <- [0..3]] ==
      [((age,0),Id 0,[]) | age <- [1..3]])
  check "pronoun observes the same three-entry window"
    (resolveSubject False two [((3,0),Id 0,[])] It == Resolved two (Id 0) &&
     resolveSubject False two [((4,0),Id 0,[])] It == Unresolved "No antecedent for it")
  let initial = World [(object 3 (Just Red) (Just Sphere))
                        {sizeOf=Just Small, positionOf=Just (4,2)}]
      (sphereWorld, sphereRanking, _, _) = run initial [] "Sphere on A1"
      (redWorld, redRanking, _, _) = run sphereWorld sphereRanking "The sphere is red."
      (smallWorld, smallRanking, _, _) = run redWorld redRanking "It is small."
      (movedWorld, _, movementPending, _) = run smallWorld smallRanking "Move the small sphere to H1"
  check "small sphere resolves across separate entries without world fallback"
    (movementPending == Nothing && case movedWorld of
      World objects -> any (\o -> idOf o == Id 4 && positionOf o == Just (7,0)) objects &&
                       any (\o -> idOf o == Id 3 && positionOf o == Just (4,2)) objects)

  let occupied = World [redCube {positionOf=Just (0,0)}]
      (blocked,_,_,_) = run occupied [] "B1 to A1."
  check "creation precedes blocked movement" (case blocked of World [created,_] -> positionOf created == Just (1,0); _ -> False)
  let (_, r4, _, _) = run two [] "#0 red? #1 blue? #0 cube?"
  check "utterance ages" (map (\(age,_,_) -> age) r4 == [(0,0),(0,1),(0,2)])
  structuralTests
  putStrLn "All layer 2 evaluation checks passed."


structuralTests = do
  let cube n pos = (object n (Just Red) (Just Cube)) {positionOf=Just pos}
      sphere n pos = (object n (Just Blue) (Just Sphere)) {positionOf=Just pos}
      world = World [cube 0 (0,0),cube 1 (1,0),sphere 2 (2,0),sphere 3 (3,0)]
      (removed, removedRanking, _, _) = run world [] "#0 on A1? Remove it from board."
  check "remove pronoun and purge old position mentions"
    ((case removed of World objects -> positionOf (head objects) == Nothing) &&
      all (\(_,i,ps) -> i /= Id 0 || P (0,0) `notElem` ps) removedRanking)
  let (deleted, deletedRanking, _, _) = run world [] "#0 red? Delete it."
  check "delete purges all mentions of deleted object"
    (not (hasId deleted (Id 0)) && all (\(_,i,_) -> i /= Id 0) deletedRanking)
  let (_, _, p1, _) = run world [] "Swap the cube and the sphere."
  first <- maybe (fail "expected first ambiguity") pure p1
  check "first swap ambiguity has no resolved operands" (null (resolvedSubjects first))
  let (stillWorld, stillRanking, p2, _) = resumeEntry world [] first (Id 0)
  second <- maybe (fail "expected second ambiguity") pure p2
  check "second ambiguity preserves first resolution without partial changes"
    (stillWorld == world && null stillRanking && resolvedSubjects second == [Id 0] && candidateIds second == [Id 2,Id 3])
  let (swapped, swapRanking, done, _) = resumeEntry stillWorld stillRanking second (Id 2)
  check "second clarification completes atomic swap"
    (done == Nothing && case swapped of
      World objects -> positionOf (head objects) == Just (2,0) && positionOf (objects !! 2) == Just (0,0))
  check "swap operands share recency" (map (\(age,i,_) -> (age,i)) swapRanking == [((0,0),Id 0),((0,0),Id 2)])
  check "pronoun after swap asks rather than preferring one operand"
    (case resolveSubject False swapped swapRanking It of Ambiguous ids -> ids == [Id 0,Id 2]; _ -> False)
  let (_, _, afterSwap, _) = run world [((0,0),Id 2,[])] "Swap #0 and it."
  check "swap resolves pronoun against pre-utterance ranking" (afterSwap == Nothing)
  let (unchanged, _, _, _) = run world [] "Swap #0 and #99. Remove #99. Delete #99."
  check "missing structural operands never create" (unchanged == world)

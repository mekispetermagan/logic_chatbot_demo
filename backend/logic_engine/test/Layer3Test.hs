module Main where

import Control.Monad (forM_, unless)
import Data.Either (isLeft)
import Data.List (isInfixOf)
import Layer2Parser
import Layer2Syntax
import Layer2Evaluation
import Discourse
import Ontology
import Pretty

check name condition = unless condition (fail name)
parsed = either error id . parseSentences
run world text = evaluateEntry world [] (parsed text)
objects (World values) = values
at n world = case filter ((== Id n) . idOf) (objects world) of
  [object] -> object
  _ -> error "test object missing"

main = do
  forM_ ["Move it up.", "move #0 down", "Move the red cube left.", "Move A1 right.",
         "Move #0 just above #1.", "move #0 under it.", "move #0 right of the cube.",
         "move #0 left of #1.", "Move #0 next to #1.", "Make #0 the same color as #1.",
         "make the cube same size as it.", "make #0 the same shape as #1.",
         "#0 on board?", "Is #0 on the board?", "Does #0 have a color?",
         "#0 have a size?", "it have a shape?", "#0 have a square?",
         "Is #0 next to #1?", "#0 same color as #1?", "Does #0 have the same size as #1?",
         "#0 have the same shape as #1?", "#0 have the same square as #1?",
         "Is #0 in the same row as #1?", "#0 same column as #1?",
         "#0 at the edge?", "Is #0 in a corner?", "how many objects are red cube?",
         "how many red?", "how many objects are next to it?", "how many at the edge?",
         "how many objects in a corner?", "how many squares are empty?",
         "how many free?", "how many squares occupied?", "how many are taken?",
         "Is every red object a cube?", "every red is cube?", "Every red object is large?", "EVERY red object cube?", "some red objects are large cube?"] $ \input ->
    case parseSentences input of
      Left message -> fail (input ++ ": " ++ message)
      Right sentences -> check ("round trip " ++ input)
        (parseSentences (unwords (map pretty sentences)) == Right sentences)
  forM_ ["move a cube up.", "move #0 up?", "make #0 same color as #1?",
         "make #0 same square as #1.", "#0 next to #1.", "is a cube on board?",
         "every red cube?", "all red objects are cube?", "Are all red objects cube?", "every red objects are cube?", "are every red object cube?", "some cube green?", "how many red", "#0 on board",
         "move #0 up move #0 down", "every red object is?", "move #0 above #1 junk"] $ \input ->
    check ("reject " ++ input) (isLeft (parseSentences input))
  let first = Object (Id 0) (Just Red) (Just Small) (Just Cube) (Just (1,1))
      second = Object (Id 1) Nothing Nothing (Just Sphere) (Just (4,4))
      loose = emptyObject (Id 2)
      world = World [first, second, loose]
  forM_ [("up",(1,2)),("down",(1,0)),("left",(0,1)),("right",(2,1))] $ \(name, expected) -> do
    let (updated,_,pending,_) = run world ("Move #0 " ++ name)
    check "one-square movement" (positionOf (at 0 updated) == Just expected && pending == Nothing)
  forM_ [("above",(4,5)),("under",(4,3)),("left of",(3,4)),("right of",(5,4))] $ \(name, expected) -> do
    let (updated,_,_,_) = run world ("Move #0 just " ++ name ++ " #1")
    check "relative movement" (positionOf (at 0 updated) == Just expected)
  let cornerWorld = World [first {positionOf=Just (0,0)}, second {positionOf=Just (0,1)}, loose]
      (blocked,_,_,blockedFeedback) = run cornerWorld "Move #0 left. Move #0 up. Move #2 down."
  check "bounds, collisions, unplaced source leave world intact"
    (blocked == cornerWorld && "Outside board" `isInfixOf` blockedFeedback && "occupied" `isInfixOf` blockedFeedback && "unplaced" `isInfixOf` blockedFeedback)
  let (copied,_,_,_) = run world "Make #0 the same color as #1. Make #0 the same size as #1. Make #0 the same shape as #1."
  check "copy including null" (at 0 copied == first {colorOf=Nothing,sizeOf=Nothing,shapeOf=Just Sphere})
  forM_ [("#0 on board?",True),("#2 on board?",False),("#0 have a color?",True),
         ("#1 have a color?",False),("#0 have a square?",True),
         ("#0 at the edge?",False),("#0 in a corner?",False),
         ("#0 same row as #1?",False),("#0 same column as #1?",False)] $ \(text, expected) ->
    let (updated,_,_,feedback) = run world text in
      check text (updated == world && (if expected then "\n  true" else "\n  false") `isInfixOf` feedback)
  forM_ ["color","size","shape","square","row","column"] $ \attr -> do
    let (_,_,_,feedback) = run (World [emptyObject (Id 0),loose]) ("#0 same " ++ attr ++ " as #2?")
    check "null equality explains answer" ("true — both lack" `isInfixOf` feedback)
  forM_ [("how many red?","1"),("how many objects?","3"),
         ("how many squares are empty?","62"),("how many occupied?","2"),
         ("how many objects next to #0?","0"),
         ("how many at the edge?","0"),("how many in a corner?","0"),
         ("every red object is cube?","true"),("some red are sphere?","false"),
         ("every green is a cube?","true — no matching objects"),
         ("some green objects cube?","false — no matching objects")] $ \(text, expected) ->
    let (_,_,_,feedback) = run world text in check text (("\n  " ++ expected) `isInfixOf` feedback)
  let (_,_,_,edgeAnswers) = run cornerWorld "#0 next to #1? #0 at the edge? #0 in a corner? how many next to #0?"
  check "orthogonal adjacency and boundaries" ("\n  false" `notIn` edgeAnswers && "\n  1" `isInfixOf` edgeAnswers)
  let diagonal = World [first {positionOf=Just (0,0)},second {positionOf=Just (1,1)}]
      (_,_,_,diagonalAnswer) = run diagonal "#0 next to #1?"
  check "diagonals excluded" ("false" `isInfixOf` diagonalAnswer)
  let (beforeChoice, ranking, pending, _) = run world "#0 blue. Move #0 next to #1. #0 large."
  paused <- maybe (fail "expected square choice") pure pending
  check "pause at exact utterance with resolved subjects"
    (colorOf (at 0 beforeChoice) == Just Blue && sizeOf (at 0 beforeChoice) == Just Small &&
     resolvedSubjects paused == [Id 0,Id 1] && length (squareChoices paused) == 4)
  let (invalid,_,stillPending,_) = resumeSquareEntry beforeChoice ranking paused (7,7)
  check "invalid choice does not mutate" (invalid == beforeChoice && stillPending == Just paused)
  let (chosen,_,done,_) = resumeSquareEntry beforeChoice ranking paused (4,5)
  check "square choice resumes remainder" (done == Nothing && positionOf (at 0 chosen) == Just (4,5) && sizeOf (at 0 chosen) == Just Large)
  let occupied = World [first,second {positionOf=Just (0,0)},loose {positionOf=Just (0,1)}]
      (only,_,onlyPending,_) = run occupied "Move #0 next to #1"
  check "sole free neighbor chosen automatically" (onlyPending == Nothing && positionOf (at 0 only) == Just (1,0))
  let full = World (objects occupied ++ [(emptyObject (Id 3)) {positionOf=Just (1,0)}])
      (noMove,_,_,noFree) = run full "Move #0 next to #1"
  check "no free squares" (noMove == full && "No free squares" `isInfixOf` noFree)
  let (_,_,ambiguous,_) = run (World [first,first {idOf=Id 3,positionOf=Just (2,2)},second]) "Move the cube next to #1"
  objectChoice <- maybe (fail "expected object choice") pure ambiguous
  let (_,_,squareChoice,_) = resumeEntry (World [first,first {idOf=Id 3,positionOf=Just (2,2)},second]) [] objectChoice (Id 0)
  check "object clarification can lead to square clarification"
    (case squareChoice of Just SquarePending{} -> True; _ -> False)
  putStrLn "All Layer 3 checks passed."
  where notIn needle text = not (needle `isInfixOf` text)

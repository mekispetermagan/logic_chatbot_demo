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
  forM_ ["Move it up.", "move #0 down", "Move the red bloom left.", "Move A1 right.",
         "Move #0 just above #1.", "move #0 under it.", "move #0 right of the bloom.",
         "move #0 left of #1.", "Move #0 next to #1.", "Make #0 the same color as #1.",
         "make the bloom same size as it.", "make #0 the same shape as #1.",
         "#0 on board?", "Is #0 on the board?", "Does #0 have a color?",
         "#0 have a size?", "it have a shape?", "#0 have a square?",
         "Is #0 next to #1?", "#0 same color as #1?", "Does #0 have the same size as #1?",
         "#0 have the same shape as #1?", "#0 have the same square as #1?",
         "Is #0 in the same row as #1?", "#0 same column as #1?",
         "#0 at the edge?", "Is #0 in a corner?", "how many objects are red bloom?",
         "how many red?", "how many objects are next to it?", "how many at the edge?",
         "how many objects in a corner?", "how many squares are empty?",
         "how many free?", "how many squares occupied?", "how many are taken?",
         "Is every red object at the edge?", "Is every red object in a corner?",
         "Is every red object on the board?", "Does every red object have a shape?",
         "Do some red objects have a square?", "Some red objects have a color?",
         "Is every red object next to the bloom?",
         "Is every red object in the same row as #3?",
         "Does every red object have the same size as #3?",
         "Every red object small and at the edge?",
         "Some red objects bloom large and have a square and next to it?",
         "Every red object same color as A1 and same shape as the small bloom?",
         "Is every red object a bloom?", "every red is bloom?", "Every red object is large?", "EVERY red object bloom?", "some red objects are large bloom?"] $ \input ->
    case parseSentences input of
      Left message -> fail (input ++ ": " ++ message)
      Right sentences -> check ("round trip " ++ input)
        (parseSentences (unwords (map pretty sentences)) == Right sentences)
  forM_ ["move a bloom up.", "move #0 up?", "make #0 same color as #1?",
         "make #0 same square as #1.", "#0 next to #1.", "is a bloom on board?",
         "Every red object has the same color?", "Every red object have the same color?",
         "Every red object next to a bloom?", "Every red object next to bloom?",
         "Every red object small and?", "Every red object and small?",
         "Every red object small and and at the edge?",
         "Every red object small at the edge?", "Every red object small or large?",
         "Every red object at the edge.",
         "every red bloom?", "all red objects are bloom?", "Are all red objects bloom?", "every red objects are bloom?", "are every red object bloom?", "some bloom green?", "how many red", "#0 on board",
         "move #0 up move #0 down", "every red object is?", "move #0 above #1 junk"] $ \input ->
    check ("reject " ++ input) (isLeft (parseSentences input))
  let first = Object (Id 0) (Just Red) (Just Small) (Just Bloom) (Just (1,1))
      second = Object (Id 1) Nothing Nothing (Just Spark) (Just (4,4))
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
  check "copy including null" (at 0 copied == first {colorOf=Nothing,sizeOf=Nothing,shapeOf=Just Spark})
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
         ("every red object is bloom?","true"),("some red are spark?","false"),
         ("every green is a bloom?","true — no matching objects"),
         ("some green objects bloom?","false — no matching objects")] $ \(text, expected) ->
    let (_,_,_,feedback) = run world text in check text (("\n  " ++ expected) `isInfixOf` feedback)
  forM_ [("Is every red object at the edge?",True),
         ("Is every red object in a corner?",True),
         ("Is every red object on the board?",True),
         ("Does every red object have a shape?",True),
         ("Does every red object have a color?",True),
         ("Does every red object have a size?",True),
         ("Does every red object have a square?",True),
         ("Is every red object next to #1?",True),
         ("Is every red object next to the spark?",True),
         ("Is every red object in the same row as #1?",False),
         ("Is every red object in the same column as #1?",True),
         ("Does every red object have the same color as #1?",False),
         ("Every red object small bloom and at the edge?",True),
         ("Every red object small and next to #1 and in a corner?",True),
         ("Some red objects large and at the edge?",False),
         ("Every green object at the edge?",True),
         ("Some green objects at the edge?",False)] $ \(text, expected) ->
    let (updated,_,pending,feedback) = run cornerWorld text in
      check text (updated == cornerWorld && pending == Nothing &&
        (if expected then "\n  true" else "\n  false") `isInfixOf` feedback)
  let mixedWorld = World [first {positionOf=Just (0,0)},first {idOf=Id 3,positionOf=Nothing},second]
  forM_ [("Every red object on board?",False), ("Some red objects on board?",True),
         ("Every red object have a square?",False), ("Some red objects in a corner?",True),
         ("Every red object next to #2?",False)] $ \(text, expected) ->
    let (_,_,_,feedback) = run (World (objects mixedWorld ++ [loose])) text in
      check text ((if expected then "\n  true" else "\n  false") `isInfixOf` feedback)
  forM_ ["color","size","shape","square","row","column"] $ \attr -> do
    let nullWorld = World [loose {shapeOf=Just Bloom},emptyObject (Id 5)]
        (_,_,_,feedback) = run nullWorld ("Every bloom object same " ++ attr ++ " as #5?")
    check ("quantified null comparison " ++ attr)
      ((if attr == "shape" then "false" else "true — both lack") `isInfixOf` feedback)
  let splitWorld = World [first {positionOf=Nothing},first {idOf=Id 3,sizeOf=Just Large}]
      (_,_,_,splitAnswer) = run splitWorld "Some red objects small and on board?"
  check "conjunction checks one object, not separate existential witnesses"
    ("\n  false" `isInfixOf` splitAnswer)
  let (_,_,_,twoTargets) = run cornerWorld "Every red object same shape as #0 and next to #1?"
  check "distinct fixed targets stay aligned" ("\n  true" `isInfixOf` twoTargets)
  let (missingWorld,_,_,missingAnswer) = run cornerWorld "Every red object next to #99?"
  check "missing target never creates an object" (missingWorld == cornerWorld && "\n  true" `notIn` missingAnswer)
  let (_,_,_,pronounAnswer) = run cornerWorld "#1 spark? Every red object next to it?"
  check "quantified target uses discourse" ("\n  false" `notIn` pronounAnswer)
  let targetWorld = World [first,second,second {idOf=Id 4,positionOf=Just (1,2)}]
      (_,_,targetPending,_) = run targetWorld "Every red object next to the spark and same shape as the spark?"
  targetChoice <- maybe (fail "expected quantified target clarification") pure targetPending
  check "repeated target resolves once" (case remainingSentences targetChoice of
    sentence:_ -> length (subjectsOf sentence) == 1
    [] -> False)
  check "quantified pending pretty round trip"
    (parseSentences (unwords (map pretty (remainingSentences targetChoice))) == Right (remainingSentences targetChoice))
  let (targetUpdated,targetRanking,targetDone,targetAnswer) = resumeEntry targetWorld [] targetChoice (Id 4)
  check "clarified target reused for all clauses"
    (targetUpdated == targetWorld && targetDone == Nothing && "\n  false" `isInfixOf` targetAnswer &&
     any (\(_,identifier,_) -> identifier == Id 4) targetRanking &&
     not (any (\(_,identifier,_) -> identifier == Id 0) targetRanking))
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
  let (_,_,ambiguous,_) = run (World [first,first {idOf=Id 3,positionOf=Just (2,2)},second]) "Move the bloom next to #1"
  objectChoice <- maybe (fail "expected object choice") pure ambiguous
  let (_,_,squareChoice,_) = resumeEntry (World [first,first {idOf=Id 3,positionOf=Just (2,2)},second]) [] objectChoice (Id 0)
  check "object clarification can lead to square clarification"
    (case squareChoice of Just SquarePending{} -> True; _ -> False)
  putStrLn "All Layer 3 checks passed."
  where notIn needle text = not (needle `isInfixOf` text)

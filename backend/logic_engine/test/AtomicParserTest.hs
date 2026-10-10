module Main where

import AtomicParser
import AtomicEvaluation
import Control.Monad (forM_, unless)
import Data.Either (isLeft)
import Ontology
import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import AtomicSentence
import Pretty
import Result
import Sandbox (world)

check :: String -> Bool -> IO ()
check name result = unless result (fail name)

main :: IO ()
main = do
  forM_ ["#3 red.", "#3 is red.", " #3 IS RED \n"] $ \input ->
    check input (parseAtomicPerformative input == Right (AP (ById (Id 3)) (C Red)))
  forM_ ["#3 A4.", "#3 on A4", "#3 is A4", "#3 is on a4."] $ \input ->
    check input (parseAtomicPerformative input == Right (AP (ById (Id 3)) (P (0, 3))))
  forM_ [("blue", C Blue), ("green", C Green), ("yellow", C Yellow),
         ("small", S Small), ("medium", S Medium), ("large", S Large),
         ("cube", Sh Cube), ("sphere", Sh Sphere), ("pyramid", Sh Pyramid)] $
    \(word, property) -> check word
      (parseAtomicPerformative ("#0 " ++ word) == Right (AP (ById (Id 0)) property))
  let expected = [AP (ById (Id 1)) (P (1, 2)), AP (ById (Id 1)) (C Red),
                  AP (ById (Id 1)) (S Medium), AP (ById (Id 1)) (Sh Cube), AP (ById (Id 1)) (Sh Sphere)]
  let input = "#1 on B3. #1 red. #1 medium. #1 is cube. #1 is sphere"
  check "mixed separators" (parseAtomicPerformatives input == Right expected)
  check "period without spaces"
    (parseAtomicPerformatives "#1 red.#1 cube." ==
      Right [AP (ById (Id 1)) (C Red), AP (ById (Id 1)) (Sh Cube)])
  check "sequential revision"
    (foldl updateWorldWith (World []) expected == World
      [Object (Id 1) (Just Red) (Just Medium) (Just Sphere) (Just (1, 2))])
  forM_ ["", "  ", "o-1 red", "#1red", "#1 on red", "#1 I1", "#1 A0",
         "#1 A9", "#1 A10", "#1 red junk", "#1 red?", "#1 redo2 blue",
         "#1 red #2 purple", "#1 red..", "#999999999999999999999999999 red"] $
    \bad -> check ("reject " ++ show bad) (isLeft (parseAtomicPerformatives bad))
  check "single parser rejects sequence" (isLeft (parseAtomicPerformative input))
  forM_ ["#3 red?", "#3 IS RED ?"] $ \question ->
    check question (parseAtomicSentence question ==
      Right (PropertyCheck (APC (ById (Id 3)) (C Red))))
  check "position check" (parseAtomicSentence "#3 is on A4?" ==
    Right (PropertyCheck (APC (ById (Id 3)) (P (0, 3)))))
  check "mixed atomic sentences" (parseAtomicSentences
    "#1 on B3. #1 red?#1 medium. #1 is cube. #1 is sphere ?" == Right
    [Performative (AP (ById (Id 1)) (P (1, 2))), PropertyCheck (APC (ById (Id 1)) (C Red)),
     Performative (AP (ById (Id 1)) (S Medium)), Performative (AP (ById (Id 1)) (Sh Cube)),
     PropertyCheck (APC (ById (Id 1)) (Sh Sphere))])
  forM_ ["", "#1 red??", "#1 red?.", "#1 red? junk", "#1 red?#2 I9"] $
    \bad -> check ("reject mixed " ++ show bad) (isLeft (parseAtomicSentences bad))
  forM_ [C Blue, S Small, Sh Cube, P (0, 0)] $ \property ->
    check "matching property" (case evaluateAtomicPropertyCheck world (APC (ById (Id 0)) property) of
      Result True -> True
      _ -> False)
  forM_ [C Red, S Large, Sh Pyramid, P (7, 7)] $ \property ->
    check "different property" (case evaluateAtomicPropertyCheck world (APC (ById (Id 0)) property) of
      Result False -> True
      _ -> False)
  forM_ [C Blue, S Small, Sh Cube, P (0, 0)] $ \property ->
    check "absent property" (case evaluateAtomicPropertyCheck
      (World [emptyObject (Id 0)]) (APC (ById (Id 0)) property) of
        Result False -> True
        _ -> False)
  check "missing referent" (case evaluateAtomicPropertyCheck world (APC (ById (Id 99)) (C Red)) of
    Message _ -> True
    _ -> False)
  check "pretty property check" (pretty (APC (ById (Id 1)) (C Red)) == "#1 red?")
  check "pretty position check" (pretty (APC (ById (Id 1)) (P (7, 7))) == "#1 on H8?")
  check "pretty performative" (pretty (AP (ById (Id 1)) (C Red)) == "#1 red.")
  check "pretty position performative"
    (pretty (AP (ById (Id 1)) (P (1, 2))) == "#1 on B3.")
  let sentences = [Performative (AP (ById (Id 1)) (C Red)),
                   PropertyCheck (APC (ById (Id 1)) (P (1, 2)))]
  check "pretty mixed sentences round trip"
    (parseAtomicSentences (unwords (map pretty sentences)) == Right sentences)
  forM_ [(ColorAttribute, PropertyValue (C Blue)),
         (SizeAttribute, PropertyValue (S Small)),
         (ShapeAttribute, PropertyValue (Sh Cube)),
         (PositionAttribute, PropertyValue (P (0, 0))),
         (RowAttribute, RowValue 0), (ColumnAttribute, ColumnValue 0)] $ \(attribute, answer) -> do
    let query = APQ attribute (ById (Id 0))
    check "query pretty round trip" (parseAtomicSentence (pretty query) ==
      Right (PropertyQuery query))
    check "query evaluation" (case evaluateAtomicPropertyQuery world query of
      Result actual -> actual == answer
      _ -> False)
    check "absent query attribute" (case evaluateAtomicPropertyQuery
      (World [emptyObject (Id 0)]) query of
        Result Absent -> True
        _ -> False)
  check "case insensitive query" (parseAtomicSentence " COLOR OF #3 ? " ==
    Right (PropertyQuery (APQ ColorAttribute (ById (Id 3)))))
  check "mixed queries and updates" (parseAtomicSentences
    "#1 red.color of #1?#1 red? row of #1?" == Right
    [Performative (AP (ById (Id 1)) (C Red)), PropertyQuery (APQ ColorAttribute (ById (Id 1))),
     PropertyCheck (APC (ById (Id 1)) (C Red)), PropertyQuery (APQ RowAttribute (ById (Id 1)))])
  forM_ ["color of #1", "color of #1.", "color #1?", "colour of #1?",
         "color of #1??", "#1 red. shape of #1? junk"] $ \bad ->
    check ("reject query " ++ bad) (isLeft (parseAtomicSentences bad))
  check "performative parser rejects queries"
    (isLeft (parseAtomicPerformative "color of #1?"))
  check "query missing referent" (case evaluateAtomicPropertyQuery world
    (APQ ColorAttribute (ById (Id 99))) of
      Message _ -> True
      _ -> False)
  forM_ [(PropertyValue (C Red), "red"), (PropertyValue (S Medium), "medium"),
         (PropertyValue (Sh Sphere), "sphere"), (PropertyValue (P (7, 7)), "H8"),
         (RowValue 7, "8"), (ColumnValue 7, "H"), (Absent, "none")] $ \(answer, text) ->
    check "pretty query answer" (pretty answer == text)
  let sequenceInput = [
        PropertyQuery (APQ ColorAttribute (ById (Id 1))),
        Performative (AP (ById (Id 1)) (C Red)),
        PropertyCheck (APC (ById (Id 1)) (C Red)),
        Performative (AP (ById (Id 1)) (C Blue)),
        PropertyQuery (APQ ColorAttribute (ById (Id 1))),
        Performative (AP (ById (Id 1)) (C Blue)),
        PropertyCheck (APC (ById (Id 99)) (C Blue)),
        Performative (AP (ById (Id 1)) (P (7, 7))),
        PropertyQuery (APQ PositionAttribute (ById (Id 1)))]
  let (evaluatedWorld, feedback) = evaluateAtomicSentences (World []) sequenceInput
  check "final evaluated world" (evaluatedWorld == World
    [Object (Id 1) (Just Blue) Nothing Nothing (Just (7, 7))])
  check "feedback sentence ordering" (map feedbackSentence feedback == sequenceInput)
  check "evaluation feedback" (case map feedbackAnswer feedback of
    [FeedbackMessage _, UpdateAnswer (ObjectCreated (Id 1) (C Red)),
     CheckAnswer True, UpdateAnswer (PropertyChanged (Id 1) (Just (C Red)) (C Blue)),
     QueryAnswerValue (PropertyValue (C Blue)), UpdateAnswer NoChange,
     FeedbackMessage _, UpdateAnswer (PropertyChanged (Id 1) Nothing (P (7, 7))),
     QueryAnswerValue (PropertyValue (P (7, 7)))] -> True
    _ -> False)
  check "empty evaluation" (evaluateAtomicSentences world [] == (world, []))
  check "questions preserve world" (fst (evaluateAtomicSentences world
    [PropertyCheck (APC (ById (Id 0)) (C Blue)),
     PropertyQuery (APQ ColorAttribute (ById (Id 0)))]) == world)
  check "pretty evaluation feedback"
    (pretty (feedback !! 3) == "#1 blue.\n  #1: red -> blue")
  check "pretty query feedback"
    (pretty (last feedback) == "position of #1?\n  H8")
  squareReferenceTests
  structuralTests
  attributeRemovalTests
  putStrLn "All atomic parser and evaluation checks passed."


squareReferenceTests :: IO ()
squareReferenceTests = do
  let square = AtSquare (0, 3)
      destination = (0, 4)
      sourceObject = (emptyObject (Id 4)) { positionOf = Just (0, 3) }
      destinationObject = (emptyObject (Id 7)) { positionOf = Just destination }
      perform reference property = Performative (AP reference property)
      empty = World []
  check "square parse" (parseAtomicSentence "a4 red" ==
    Right (perform square (C Red)))
  check "square move parse" (parseAtomicSentence "a4 to a5" ==
    Right (perform square (P destination)))
  check "square check parse" (parseAtomicSentence "a4 on a5?" ==
    Right (PropertyCheck (APC square (P destination))))
  forM_ ["column", "color", "size", "shape", "row", "position"] $ \attribute -> do
    check "shorthand square query" (case parseAtomicSentence ("a4 " ++ attribute ++ "?") of
      Right (PropertyQuery _) -> True
      _ -> False)
    check "shorthand ID query" (case parseAtomicSentence ("#3 " ++ attribute ++ "?") of
      Right (PropertyQuery _) -> True
      _ -> False)
    check "query mark required" (isLeft (parseAtomicSentences ("a4 " ++ attribute)))
  forM_ ["o3 red", "O3 red", "color of c5", "a4 to a5?", "#3 to a5?",
         "a4 red??", "a4 column.", "#3 color", "#3red"] $ \bad ->
    check ("reject new syntax " ++ bad) (isLeft (parseAtomicSentences bad))
  let (created, _) = evaluateAtomicSentence empty (perform square (C Red))
  check "empty square creates positioned object" (created == World
    [Object (Id 0) (Just Red) Nothing Nothing (Just (0, 3))])
  let (existing, _) = evaluateAtomicSentence (World [sourceObject]) (perform square (C Blue))
  check "occupied square updates same ID" (existing == World
    [sourceObject { colorOf = Just Blue }])
  let occupied = World [sourceObject, destinationObject]
      (blocked, blockedFeedback) = evaluateAtomicSentence occupied (perform square (P destination))
  check "occupied source blocked move" (blocked == occupied)
  check "concise blocked feedback" (pretty blockedFeedback == "A4 on A5.\n  A5 occupied")
  let (createdBlocked, createdFeedback) = evaluateAtomicSentence
        (World [destinationObject]) (perform square (P destination))
  check "creation survives blocked move" (createdBlocked == World
    [(emptyObject (Id 8)) { positionOf = Just (0, 3) }, destinationObject])
  check "creation and blocked feedback"
    (pretty createdFeedback == "A4 on A5.\n  Created #8; A5 occupied")
  let (moved, _) = evaluateAtomicSentence empty (perform square (P destination))
  check "create then move" (moved == World
    [(emptyObject (Id 0)) { positionOf = Just destination }])
  check "existing self move" (fst (evaluateAtomicSentence (World [sourceObject])
    (perform square (P (0, 3)))) == World [sourceObject])
  check "empty self move creates" (fst (evaluateAtomicSentence empty
    (perform square (P (0, 3)))) == World [(emptyObject (Id 0)) { positionOf = Just (0, 3) }])
  let (sequential, _) = evaluateAtomicSentences (World [sourceObject])
        [perform square (P destination), perform square (C Red)]
  check "square resolved at each step" (sequential == World
    [Object (Id 5) (Just Red) Nothing Nothing (Just (0, 3)),
     sourceObject { positionOf = Just destination }])
  let questions = [PropertyCheck (APC square (C Red)),
                   PropertyQuery (APQ ColorAttribute square)]
      (unchanged, answers) = evaluateAtomicSentences empty questions
  check "empty questions never create" (unchanged == empty &&
    all (\answer -> case feedbackAnswer answer of FeedbackMessage _ -> True; _ -> False) answers)
  let ambiguous = World [sourceObject, sourceObject { idOf = Id 5 }]
  check "ambiguous square not modified" (fst (evaluateAtomicSentence ambiguous
    (perform square (C Red))) == ambiguous)
  check "ambiguous square query" (case evaluateAtomicPropertyQuery ambiguous
    (APQ ColorAttribute square) of Message _ -> True; _ -> False)
  check "boundary check retains creation" (fst (evaluateAtomicSentence empty
    (perform square (P (8, 0)))) == World [(emptyObject (Id 0)) { positionOf = Just (0, 3) }])
  check "invalid reference does not create" (fst (evaluateAtomicSentence empty
    (perform (AtSquare (8, 0)) (C Red))) == empty)
  case parseAtomicSentences "a4 red. color of a4? #0 column? a4 to a5. a5 red?" of
    Left message -> fail message
    Right sentences -> check "mixed reference pretty round trip"
      (parseAtomicSentences (unwords (map pretty sentences)) == Right sentences)


structuralTests :: IO ()
structuralTests = do
  let ref n = ById (Id n)
      forms = [("remove #3", Remove (ref 3)), ("REMOVE A1 FROM BOARD.", Remove (AtSquare (0,0))),
               ("swap #3 #4", Swap (ref 3) (ref 4)), ("Swap A1 and B1.", Swap (AtSquare (0,0)) (AtSquare (1,0))),
               ("erase #3.", Delete (ref 3)), ("DELETE #3", Delete (ref 3))]
  forM_ forms $ \(text, expected) -> do
    check ("structural parse " ++ text) (parseAtomicPerformative text == Right expected)
    check "structural pretty round trip" (parseAtomicPerformative (pretty expected) == Right expected)
  forM_ ["remove #3?", "swap #3 and #4?", "delete #3?", "remove #3 from.",
         "swap #3", "swap #3 #4 #5", "erase it", "remove #3 delete #4"] $ \text ->
    check ("structural rejection " ++ text) (isLeft (parseAtomicSentences text))
  let left = Object (Id 0) (Just Red) (Just Small) (Just Cube) (Just (0,0))
      right = Object (Id 1) (Just Blue) Nothing (Just Sphere) (Just (1,0))
      loose = Object (Id 2) Nothing (Just Large) Nothing Nothing
      world = World [left, right, loose]
      normalized (updated, Result change) = (updated, Just change)
      normalized (updated, Message _) = (updated, Nothing)
      eval = normalized . evaluateAtomicPerformative world
  check "remove preserves object attributes and identity"
    (eval (Remove (ref 0)) == (World [left {positionOf=Nothing},right,loose], Just (ObjectRemoved (Id 0) (0,0))))
  check "remove unplaced is no change" (eval (Remove (ref 2)) == (world, Just NoChange))
  check "delete unplaced object" (eval (Delete (ref 2)) == (World [left,right], Just (ObjectDeleted (Id 2))))
  check "swap occupied squares atomically"
    (fst (eval (Swap (AtSquare (0,0)) (AtSquare (1,0)))) ==
      World [left {positionOf=Just (1,0)},right {positionOf=Just (0,0)},loose])
  check "swap placed and unplaced exchanges absence and position"
    (fst (eval (Swap (ref 0) (ref 2))) ==
      World [left {positionOf=Nothing},right,loose {positionOf=Just (0,0)}])
  check "swap self is no change" (eval (Swap (ref 0) (AtSquare (0,0))) == (world, Just NoChange))
  let unplacedWorld = World [left {positionOf=Nothing}, loose]
  check "swap two unplaced is no change"
    (normalized (evaluateAtomicPerformative unplacedWorld (Swap (ref 0) (ref 2))) == (unplacedWorld, Just NoChange))
  forM_ [Remove (ref 99), Delete (ref 99), Swap (ref 0) (ref 99), Swap (ref 99) (ref 0),
         Remove (AtSquare (7,7))] $ \operation ->
    check "missing structural operand never creates or partially updates" (fst (eval operation) == world)
  let full = World [(emptyObject (Id n)) {positionOf=Just (n `mod` 8,n `div` 8)} | n <- [0..63]]
      swapped = fst (evaluateAtomicPerformative full (Swap (ref 0) (ref 63)))
  check "swap needs no spare square on full board"
    (case swapped of World objects -> positionOf (head objects) == Just (7,7) && positionOf (last objects) == Just (0,0))
  check "mixed structural sentence sequence"
    (case parseAtomicSentences "remove #0. position of #0? swap #0 #1. erase #1. #0 red?" of
      Right sentences -> length sentences == 5
      Left _ -> False)


attributeRemovalTests :: IO ()
attributeRemovalTests = do
  let ref = ById (Id 3)
      object = Object (Id 3) (Just Red) (Just Small) (Just Cube) (Just (0,3))
      other = (emptyObject (Id 4)) {colorOf = Just Blue}
      world = World [object, other]
      cases = [(RemoveColor, object {colorOf = Nothing}),
               (RemoveSize, object {sizeOf = Nothing}),
               (RemoveShape, object {shapeOf = Nothing}),
               (RemoveSquare, object {positionOf = Nothing})]
  forM_ cases $ \(attribute, expected) -> do
    let operation = RemoveAttribute ref attribute
        text = pretty operation
        (updated, result) = evaluateAtomicPerformative world operation
    check "attribute removal round trip" (parseAtomicPerformative text == Right operation)
    check "attribute removal final period optional"
      (parseAtomicPerformative (init text) == Right operation)
    check "attribute removal preserves identity, other attributes, and other objects"
      (updated == World [expected, other])
    check "attribute removal feedback" (case result of
      Result change -> pretty change == case attribute of
        RemoveColor -> "#3: red -> none"
        RemoveSize -> "#3: small -> none"
        RemoveShape -> "#3: cube -> none"
        RemoveSquare -> "#3: on A4 -> unplaced"
      _ -> False)
    check "clearing absent attribute is no change"
      (case evaluateAtomicPerformative updated operation of
        (again, Result NoChange) -> again == updated
        _ -> False)
    forM_ [ById (Id 99), AtSquare (7,7)] $ \missing ->
      check "attribute removal never creates missing subjects"
        (case evaluateAtomicPerformative world (RemoveAttribute missing attribute) of
          (unchanged, Message _) -> unchanged == world
          _ -> False)
  check "square subject case insensitive"
    (parseAtomicPerformative " A4 REMOVE COLOR. " ==
      Right (RemoveAttribute (AtSquare (0,3)) RemoveColor))
  check "square subject resolves existing object"
    (fst (evaluateAtomicPerformative world (RemoveAttribute (AtSquare (0,3)) RemoveColor)) ==
      World [object {colorOf = Nothing}, other])
  check "square removal agrees with prefix remove"
    (fst (evaluateAtomicPerformative world (RemoveAttribute ref RemoveSquare)) ==
      fst (evaluateAtomicPerformative world (Remove ref)))
  forM_ ["#3 remove color?", "A4 remove square?", "#3 remove row.",
         "#3 remove column.", "#3 remove position.", "#3 remove.",
         "#3 remove color #3 red", "#3 remove color size.", "#3 is remove color."] $ \bad ->
    check ("reject attribute removal " ++ bad) (isLeft (parseAtomicSentences bad))
  case parseAtomicSentences "#3 remove color. #3 red? color of #3? #3 blue" of
    Left message -> fail message
    Right sentences -> do
      let (updated, feedback) = evaluateAtomicSentences world sentences
      check "removal participates in sequential evaluation"
        (updated == World [object {colorOf = Just Blue}, other])
      check "questions see cleared attribute" (case map feedbackAnswer feedback of
        [UpdateAnswer (PropertyCleared (Id 3) (C Red)), CheckAnswer False,
         QueryAnswerValue Absent, UpdateAnswer (PropertyChanged (Id 3) Nothing (C Blue))] -> True
        _ -> False)

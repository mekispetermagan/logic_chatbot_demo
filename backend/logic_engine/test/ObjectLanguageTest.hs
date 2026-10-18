module Main where

import Control.Monad (unless, forM_)
import Data.Either (isLeft)
import Data.List (isInfixOf, sortOn)
import qualified Data.Map.Strict as Map
import Ontology
import qualified ControlledLanguage.Discourse as D
import Domains.Objects.Language.Parser
import Domains.Objects.Language.Pretty
import Domains.Objects.Language.Evaluation
import qualified Domains.Objects.Language.Syntax as V

check :: String -> Bool -> IO ()
check name result = unless result (fail name)
object :: Int -> [(String,String)] -> Maybe Position -> Object
object n values p = Object (Id n) (Map.fromList [(AttributeId a,ValueId v) | (a,v) <- values]) p
run :: World -> D.SalienceRanking -> Int -> String -> [V.Choice] -> Outcome
run w r n text choices = case parseEntry text of Left error -> errorWithoutStackTrace error; Right entry -> runEntry w r n entry choices 0
at :: Int -> Outcome -> Object
at n result = case objectAtId (resultWorld result) n of Just o -> o; Nothing -> errorWithoutStackTrace ("Missing #" ++ show n)
examples :: [String] -> [String]
examples [] = []
examples ("```text":rest) = let (block,after) = break (== "```") rest in unlines block : examples (drop 1 after)
examples (_:rest) = examples rest

main :: IO ()
main = do
  let alternatives text = either errorWithoutStackTrace id (parseEntryAlternatives text)
      ambiguous = "Does #3 satisfy color is red or size is large and shape is bloom?"
  check "surface syntax creates without redundant parentheses"
    (parseEntry "Create object with color red and shape bloom on C4." ==
      Right (V.Sequence [V.Command (V.Create [("color","red"),("shape","bloom")] (Just (V.Cell (2,3))))]))
  check "simple and single-operator conditions need no parentheses"
    (length (alternatives "Does #3 satisfy color is red and shape is bloom?") == 1 &&
     length (alternatives "Does A4 satisfy not occupied?") == 1)
  check "mixed operators expose both scopes instead of precedence"
    (length (alternatives ambiguous) == 2 && isLeft (parseEntry ambiguous))
  check "parentheses explicitly settle each grouping"
    (length (alternatives "Does #3 satisfy color is red or (size is large and shape is bloom)?") == 1 &&
     length (alternatives "Does #3 satisfy (color is red or size is large) and shape is bloom?") == 1)
  check "negation scope is also clarified"
    (length (alternatives "Does A4 satisfy not occupied and shading is light?") == 2)
  check "associative operator chains do not create fake ambiguity"
    (length (alternatives "Does #3 satisfy color is red and size is large and shape is bloom?") == 1)
  check "nested square conditions expose their boundary ambiguity"
    (length (alternatives "Does #3 satisfy on a square matching shading is light or true?") == 2)
  check "simple nested square test has no unnecessary grouping"
    (length (alternatives "Does it satisfy on a square matching shading is light?") == 1)
  check "description conjunction is distinct from operand conjunction"
    (length (alternatives "Exchange positions of the object with color red and shape bloom and the object with color blue.") == 1)
  check "appearance literals and offsets normalize without parentheses"
    (length (alternatives "Set appearance of #3 to color red, size none, shape loop.") == 1 &&
     length (alternatives "Shift positions of objects [#3] by east 0, north 1.") == 1)
  forM_ (alternatives ambiguous ++ alternatives "Does A4 satisfy not occupied and shading is light?" ++
         alternatives "Does #3 satisfy on a square matching shading is light or true?") $ \reading -> do
    check "human-readable grouping round trip" (parseEntry (entryText reading) == Right reading)
    check "fully delimited replay round trip" (parseEntry (canonicalEntryText reading) == Right reading)
  source <- readFile "../../specification/object-language-v2.md"
  forM_ (examples (lines source)) $ \example -> case parseEntry example of
    Left message -> fail message
    Right parsed -> check "canonical round trip" (parseEntry (entryText parsed) == Right parsed)
  forM_ ["A4 red.","#3 red.","Set color of A4 to red.","Set color of #03 to red.",
         "Set color of #3 to red", "Undo rest ignored", "Undo. Set color of #3 to red.",
         "Create object with (shape flower) on A4.","Create object with (color red and color blue) on A4.",
         "Create object with (shape bloom and color red) on A4.",
         "Does A4 satisfy (color is red)?","Does #3 satisfy (occupied)?",
         "Does #3 satisfy (next to the unique object matching (true)))?",
         "Atomically { Does #3 exist? }.","Move #3 to A9."] $ \text ->
    check ("reject noncanonical/ill-typed syntax: " ++ text) (isLeft (parseEntry text))
  let empty = World []
      created = run empty [] 7 "Create object with (color red) on A4. Set shape of it to bloom." []
  check "fresh explicit partial creation" (idOf (at 7 created) == Id 7 && positionOf (at 7 created) == Just (0,3) && valueOf (at 7 created) "size" == Nothing)
  check "creation advances counter" (resultNextId created == 8)
  let outside = runEntry empty [] 0 (V.Sequence [V.Command (V.Create [] (Just (V.Cell (8,0))))]) [] 0
      invalidValue = runEntry (resultWorld created) [] 8
        (V.Sequence [V.Command (V.SetAttribute (V.One (V.Ident 7)) "color" (Just "purple"))]) [] 0
  check "primitive invariants also protect programmatic callers" (resultError outside && resultWorld outside == empty && resultError invalidValue && resultWorld invalidValue == resultWorld created)
  let failed = run empty [] 7 "Set color of #99 to red. Create object off the board." []
  check "missing update never creates and stops sequence" (resultWorld failed == empty && resultError failed && resultNextId failed == 7)
  let collision = run (resultWorld created) [] 8 "Create object with (color blue) on A4." []
  check "failed creation leaves no object" (resultWorld collision == resultWorld created && resultNextId collision == 8 && resultError collision)
  let initial = World [object 0 [("color","blue"),("shape","bloom")] (Just (3,3)),
                       object 1 [("color","yellow"),("shape","spark")] (Just (4,3)),
                       object 2 [("color","red"),("shape","drop")] (Just (4,4)),
                       object 3 [("color","green"),("shape","loop")] (Just (3,4))]
      rotate what = run initial [] 4 ("Rotate " ++ what ++ " of objects at [D4, E4, D5, E5] by 90 degrees clockwise about the center of rectangle D4 to E5.") []
      moved = rotate "positions"
      appearances = rotate "appearance"
      visible result = sortOn fst [(positionOf o,attributesOf o) | o <- objectsOf (resultWorld result)]
  check "clockwise mapping retains identity" (positionOf (at 0 moved) == Just (3,4) && valueOf (at 0 moved) "color" == Just "blue" && valueOf (at 0 moved) "shape" == Just "bloom")
  check "appearance rotation fixes identity and position" (positionOf (at 0 appearances) == Just (3,3) && valueOf (at 0 appearances) "color" == Just "yellow")
  check "visually identical results differ semantically" (visible moved == visible appearances && resultWorld moved /= resultWorld appearances)
  check "review exposes semantic distinction" (all ((=="position") . changeKind) (resultChanges moved) && all ((=="appearance") . changeKind) (resultChanges appearances))
  let ranking = D.mention initial (Id 0) [property ("color","blue")] []
      sequence = run initial ranking 4 "Set color of #0 to red. Move #0 to E4. Set size of #0 to large." []
      batch = run initial ranking 4 "Atomically { Set color of #0 to red. Move #0 to E4. Set size of #0 to large. }." []
  check "sequence retains earlier change and stops" (resultError sequence && valueOf (at 0 sequence) "color" == Just "red" && valueOf (at 0 sequence) "size" == Nothing)
  check "batch rolls back domain and salience" (resultError batch && resultWorld batch == initial && resultRanking batch == ranking && null (resultChanges batch))
  let self = run initial [] 4 "Transfer appearance from #0 to #0." []
  check "self transfer preserves source" (resultWorld self == initial)
  let absent = World [object 0 [] Nothing,object 1 [("color","red")] (Just (0,0))]
      copied = run absent [] 2 "Copy color from #0 to #1." []
      transferred = run absent [] 2 "Transfer color from #1 to #0." []
  check "copy absence clears destination" (valueOf (at 1 copied) "color" == Nothing)
  check "transfer clears only source component" (valueOf (at 0 transferred) "color" == Just "red" && valueOf (at 1 transferred) "color" == Nothing && positionOf (at 1 transferred) == Just (0,0))
  let cloned = run absent [] 8 "Clone appearance of #1 into a new object off the board." []
  check "clone fresh identity and nullable appearance" (idOf (at 8 cloned) == Id 8 && attributesOf (at 8 cloned) == attributesOf (at 1 cloned) && positionOf (at 8 cloned) == Nothing)
  let exchanged = run absent [] 2 "Exchange positions of #0 and #1." []
  check "nullable position exchange" (positionOf (at 0 exchanged) == Just (0,0) && positionOf (at 1 exchanged) == Nothing)
  let cycle = run initial [] 4 "Rearrange positions by [#0 to D5, #3 to E5, #2 to E4, #1 to D4]." []
  check "simultaneous mapping equals rotation" (resultWorld cycle == resultWorld moved)
  forM_ ["Rearrange positions by [#0 to A1, #1 to A1].",
         "Rearrange positions by [#0 to A1, the object at D4 to B1].",
         "Permute appearance by [#0 to #1].",
         "Rotate positions of objects [#0] by 90 degrees clockwise about the center of rectangle A1 to B3."] $ \text -> do
    let result = run initial [] 4 text []
    check "invalid mapping/half-cell transform atomic" (resultError result && resultWorld result == initial)
  let eager = run absent [] 2 "Does #0 satisfy (true or next to #99)?" []
  check "Boolean branches cannot hide missing references" (resultError eager)
  let allBlue = World [object n [("color","blue")] Nothing | n <- [0..3]]
      bulk = run allBlue [] 4 "Set color of objects matching (color is blue) to red." []
  check "bulk selection frozen before updates" (all ((== Just "red") . (`valueOf` "color")) (objectsOf (resultWorld bulk)))
  let counts = run empty [] 0 "Does every object matching (color is red) satisfy (shape is bloom)? Does some object matching (color is red) satisfy (shape is bloom)? How many squares match (not occupied)?" []
  check "vacuity and vacancy answers" (all (`isInfixOf` resultFeedback counts) ["true — no matching objects","false — no matching objects","  64"])
  let riddle = run (World [object 0 [("color","red")] (Just (0,0))]) [] 1 "Does #0 satisfy (on a square matching (shading is dark))?" []
  check "square shading computed by engine" ("  true" `isInfixOf` resultFeedback riddle)
  let two = World [object 0 [("shape","bloom")] Nothing, object 1 [("shape","bloom")] Nothing]
      unmentioned = run two [] 2 "Set color of #0 to red. Set size of the object with (shape bloom) to large." []
  check "setting color does not mention unrelated shape" (case resultPause unmentioned of Just (_,_,ids,_) -> ids == [0,1]; _ -> False)
  let stagedText = "Atomically { Create object with (color red) off the board. Move it next to #0. Set size of the object with (color red) to large. }."
      seed = World [object 0 [] (Just (3,3))]
      paused = run seed [] 7 stagedText []
      resumed = run seed [] 7 stagedText [V.SquareChoice (3,4)]
  check "batch pause keeps committed world" (resultWorld paused == seed && stagedWorld paused /= Nothing && resultNextId paused == 8)
  check "batch resume does not duplicate creation" (length (objectsOf (resultWorld resumed)) == 2 && resultNextId resumed == 8 && positionOf (at 7 resumed) == Just (3,4) && valueOf (at 7 resumed) "size" == Just "large")
  let ranked = D.mention two (Id 0) [property ("shape","bloom")] []
      anaphoric = run two ranked 2 "Set color of the object with (shape bloom) to red." []
      unique = run two ranked 2 "Set color of the unique object matching (shape is bloom) to red." []
  check "anaphoric resolution retains salience preference" (resultPause anaphoric == Nothing && valueOf (at 0 anaphoric) "color" == Just "red")
  check "unique computed description exposes global ambiguity" (case resultPause unique of Just (_,_,ids,_) -> ids == [0,1]; _ -> False)
  putStrLn "All revised object language checks passed."

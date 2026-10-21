module Main where

import Control.Monad (unless, forM_)
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Ontology (Property(..))
import qualified ControlledLanguage.Discourse as D
import Domains.Cellular.Types
import qualified Domains.Cellular.Evaluation as E
import Domains.Cellular.Language.Syntax
import Domains.Cellular.Language.Parser
import Domains.Cellular.Language.Pretty
import Domains.Cellular.Language.Evaluation

assert :: String -> Bool -> IO ()
assert name yes = unless yes (error name)
life :: Ruleset
life = canonicalRuleset (Ruleset (Set.fromList [White,Black]) Moore (Map.fromList
  [(White,Rule Black Black (Set.singleton 3) True),(Black,Rule White Black (Set.fromList [0,1,4,5,6,7,8]) True)]))
world :: [(Int,Int)] -> Automaton
world ps = Automaton (Map.fromList [(p,if p `elem` ps then Black else White) | p <- boardPositions]) life 0 1
entry :: String -> Entry
entry = either error id . parseEntry
run :: Automaton -> String -> Outcome
run w source = runEntry w [] 123 (entry source) [] 0
ok :: Automaton -> String -> IO Outcome
ok w source = do
  let o = run w source
  assert (source ++ ": " ++ resultFeedback o) (not (resultError o) && resultPause o == Nothing)
  pure o
main :: IO ()
main = do
  let blank = world []
      blinker = world [(7,7),(8,7),(9,7)]
      block = world [(7,7),(8,7),(7,8),(8,8)]
      examples =
        [ "Set color of P16 to black. What is the color of it?"
        , "Set rule for black to target white, counts [0, 1, 2, 3, 4, 7, 8], enabled true."
        , "Replace ruleset with preset rgb cycle, randomly refilling the board if required."
        , "Set color of cells in rectangle A1 to P16 to white."
        , "Does A3 satisfy connected to D5?"
        , "How many neighbors of A1 match color is white?"
        , "Does every cell matching color is red satisfy neighbor of A3?"
        , "Does the board satisfy fixed point?"
        , "After 0 generations, what is the next transition of A1?"
        , "What is the first generation offset within 20 generations at which A1 satisfies color is black?"
        , "What is the first generation offset within 20 generations at which the board satisfies fixed point?"
        , "What is the stabilization time of the board within 100 generations?"
        , "What is the least return time of the board within 100 generations?"
        , "Does the count of cells matching color is black reach 0 within 70 generations?"
        , "Does the count of cells matching true reach 256 within 1 generation?"
        , "Does the count of cells matching (color is black and row is 8) reach 1 within 2 generations?"
        , "Exchange color of A1 and B2."
        , "Copy color from A1 to B2."
        , "Replace colors by [A1 to black, B2 to white]."
        , "Permute colors by [A1 to B2, B2 to A1]."
        , "Shift colors of the board by east -1, north 2."
        , "Rotate colors of cells in rectangle A1 to B2 by 90 degrees clockwise about the center of rectangle A1 to B2."
        , "Reflect colors of cells [A1, B1] across vertical through the center of rectangle A1 to B1."
        , "Initialize the board randomly."
        , "Undo." ]
  forM_ examples $ \s -> assert ("pretty/parse roundtrip " ++ s) (parseEntry (entryText (entry s)) == parseEntry s)
  forM_ ["Set color of A17 to black.","Set color of Q1 to black.","Set color of A01 to black.",
         "Set color of A1 to black","What is the color of A1.","Advance 0 generations.","Advance 257 generations.",
         "Advance 1 generations.","Set rule for white to target black, counts [3, 3], enabled true.",
         "Undo. Advance 1 generation.","Atomically { What is the palette? }.","After 2 generations, what is the generation?",
         "Does A1 satisfy occupied?","Set color of A1 to black. Blah.",
         "Does the count of cells matching true reach 257 within 1 generation?",
         "Does the count of cells matching true reach -1 within 1 generation?",
         "Does the count of cells matching true reach 01 within 1 generation?",
         "Does the count of cells matching true reach 0 within 0 generations?",
         "Does the count of cells matching true reach 0 within 257 generations?",
         "Does the count of cells matching true reach 0 within 1 generations?",
         "Does the count of cells matching true reach 0 within 1 generation."] $ \s ->
    assert ("reject " ++ s) (case parseEntryAlternatives s of Left _ -> True; _ -> False)
  assert "mixed Boolean grouping asks" (case parseEntryAlternatives "Does A1 satisfy color is white or color is black and row is 1?" of Right xs -> length xs==2; _ -> False)
  assert "not scope asks" (case parseEntryAlternatives "Does A1 satisfy not color is white and row is 1?" of Right xs -> length xs==2; _ -> False)
  case parseEntryAlternatives "Does A1 satisfy not color is white and row is 1?" of
    Right alternatives -> forM_ alternatives $ \reading -> assert "negation scope canonical replay is unique" (parseEntry (entryText reading) == Right reading)
    Left message -> error message
  assert "associative and normalizes" (case parseEntryAlternatives "Does A1 satisfy color is white and row is 1 and column is A?" of Right [_] -> True; _ -> False)

  painted <- ok blank "Set color of P16 to black. What is the color of it?"
  assert "fixed coordinate identity" (Map.lookup (15,15) (cells (resultWorld painted)) == Just Black && "black" `isInfixOf` resultFeedback painted)
  assert "edit preserves clock" (generation (resultWorld painted)==0 && rulesetRevision (resultWorld painted)==1)
  relative <- ok blank "Set color of the cell north of A16 to black."
  assert "relative coordinate wraps" (Map.lookup (0,0) (cells (resultWorld relative))==Just Black)
  forM_ ["Does A1 satisfy color is red?","Does every cell matching color is red satisfy true?","Does some cell matching color is red satisfy true?"] $ \s -> do
    o <- ok blank s
    assert "inactive color/empty quantification leaves board" (resultWorld o==blank)
  assert "empty universal explicitly true" ("true; no matching cells" `isInfixOf` resultFeedback (run blank "Does every cell matching color is red satisfy true?"))
  assert "empty existential explicitly false" ("false; no matching cells" `isInfixOf` resultFeedback (run blank "Does some cell matching color is red satisfy true?"))
  assert "eager invalid branch" (resultError (run blank "Does every cell matching color is red satisfy same cell as it?"))
  assert "inactive write fails" (resultError (run blank "Set color of A1 to red."))
  assert "duplicates reject even same value" (resultError (run blank "Replace colors by [A1 to black, A1 to black]."))
  assert "permutation requires closed identities" (resultError (run blank "Permute colors by [A1 to B1]."))

  let seam = world [(0,0),(15,0),(1,1),(4,4)]
  linked <- ok seam "Does A1 satisfy connected to P1? Does A1 satisfy connected to B2? Does A1 satisfy connected to E5? Does E5 satisfy connected to E5?"
  assert "seam/diagonal/component/self" (length (filter (== "  true") (lines (resultFeedback linked)))==3 && "  false" `isInfixOf` resultFeedback linked)
  let orth = seam {ruleset=(ruleset seam) {neighborhood=Orthogonal,rules=Map.empty}}
  assert "diagonal not Neumann connected" ("false" `isInfixOf` resultFeedback (run orth "Does A1 satisfy connected to B2?"))
  component <- ok (world [(0,0),(1,0)]) "Set color of cells connected to A1 to white."
  assert "component frozen no white recruitment" (cells (resultWorld component)==cells blank && length [p | (_,D.SquareReferent p,_) <- resultRanking component]==2)

  forecast <- ok blinker "After 1 generation, which cells match color is black? What is the least return time of the board within 4 generations?"
  assert "blinker exact forecast" ("[I7, I8, I9]" `isInfixOf` resultFeedback forecast && "  2" `isInfixOf` resultFeedback forecast && resultWorld forecast==blinker)
  stable <- ok block "What is the stabilization time of the board within 100 generations? Does the board reach a fixed point within 20 generations?"
  assert "already stable time zero" ("stabilization time 0" `isInfixOf` resultFeedback stable && "true" `isInfixOf` resultFeedback stable && resultWorld stable==block)
  oscillator <- ok blinker "Does the board reach a fixed point within 100 generations?"
  assert "cycle is not termination" ("false; no fixed point" `isInfixOf` resultFeedback oscillator)
  dying <- ok (world [(0,0)]) "What is the stabilization time of the board within 1 generation?"
  assert "fixed point at bound witnesses N+1" ("stabilization time 1" `isInfixOf` resultFeedback dying)
  extinct <- ok (world [(0,0)]) "Does the count of cells matching color is black reach 0 within 1 generation?"
  assert "count reaches zero at inclusive final offset without advancing" ("true; count reaches 0 at generation offset 1" `isInfixOf` resultFeedback extinct && resultWorld extinct==world [(0,0)])
  alreadyAbsent <- ok blank "Does the count of cells matching color is black reach 0 within 70 generations?"
  assert "count search includes offset zero" ("generation offset 0 (already matches)" `isInfixOf` resultFeedback alreadyAbsent && resultWorld alreadyAbsent==blank)
  fullCount <- ok blank "Does the count of cells matching true reach 256 within 1 generation?"
  assert "whole-board counts extend beyond neighbor counts" ("true; count reaches 256" `isInfixOf` resultFeedback fullCount)
  notExtinct <- ok blinker "Does the count of cells matching color is black reach 0 within 70 generations?"
  assert "negative answer is bounded" ("false; count does not reach 0 within 70 generations" `isInfixOf` resultFeedback notExtinct && resultWorld notExtinct==blinker)
  exactCount <- ok (world [(0,0)]) "Does the count of cells matching color is black reach 2 within 1 generation?"
  assert "reach compares exact counts rather than thresholds" ("false; count does not reach 2" `isInfixOf` resultFeedback exactCount)
  rowCount <- ok blinker "Does the count of cells matching color is black and row is 8 reach 1 within 1 generation?"
  assert "arbitrary predicates are counted on future boards" ("true; count reaches 1 at generation offset 1" `isInfixOf` resultFeedback rowCount)
  frozenCount <- ok (world [(0,0)]) "Does the count of cells matching color is white and same cell as the cell with color black reach 1 within 1 generation?"
  assert "count references resolve now, not after disappearance" ("true; count reaches 1 at generation offset 1" `isInfixOf` resultFeedback frozenCount)
  assert "hypothetical count facts do not enter current salience" (all (notElem (fact (Atom (ColorIs White))) . (\(_,_,fs) -> fs)) (resultRanking frozenCount))
  let cycleConfig = Ruleset (Set.fromList [Red,Green,Blue]) Moore (Map.fromList
        [(c,Rule target target (Set.fromList [0..8]) True) | (c,target) <- [(Red,Green),(Green,Blue),(Blue,Red)]])
      cycleWorld = Automaton (Map.fromList [(p,Red) | p <- boardPositions]) cycleConfig 19 3
  temporaryAbsence <- ok cycleWorld "Does the count of cells matching color is red reach 0 within 3 generations? After 3 generations, how many cells match color is red?"
  assert "first hit does not promise permanent extinction" ("true; count reaches 0 at generation offset 1" `isInfixOf` resultFeedback temporaryAbsence && "  256" `isInfixOf` resultFeedback temporaryAbsence && resultWorld temporaryAbsence==cycleWorld)
  advanced <- ok block "Advance 20 generations."
  assert "stable multi-step increments time" (generation (resultWorld advanced)==20 && cells (resultWorld advanced)==cells block)
  changedRules <- ok blinker "Disable rule for white."
  assert "rule revision not time" (rulesetRevision (resultWorld changedRules)==2 && generation (resultWorld changedRules)==0)
  let failedSequence = run blank "Set color of A1 to black. Set color of B1 to red. Set color of C1 to black."
      failedBatch = run blank "Atomically { Set color of A1 to black. Set color of B1 to red. }."
  assert "ordinary stop retains earlier command" (resultError failedSequence && Map.lookup (0,0) (cells (resultWorld failedSequence))==Just Black && Map.lookup (2,0) (cells (resultWorld failedSequence))==Just White)
  assert "batch rollback includes discourse" (resultError failedBatch && resultWorld failedBatch==blank && null (resultRanking failedBatch))
  assert "invalid neighborhood doesn't clamp" (resultError (run blank "Set neighborhood to von neumann."))
  compatible <- ok blank "Replace ruleset with preset game of life, preserving the board."
  assert "semantic no-op preserves old representation" (resultWorld compatible==blank)
  assert "palette preserve fails" (resultError (run blank "Replace ruleset with preset rgb cycle, preserving the board."))
  randomized <- ok blank "Replace ruleset with preset rgb cycle, randomly refilling the board if required."
  assert "random refill deterministic" (resultWorld randomized==resultWorld (run blank "Replace ruleset with preset rgb cycle, randomly refilling the board if required."))
  assert "random refill obeys palette revision" (generation (resultWorld randomized)==0 && rulesetRevision (resultWorld randomized)==2 && all (`elem` [Red,Green,Blue]) (Map.elems (cells (resultWorld randomized))))

  let paused = run blank "Set color of cells [A1, B1] to black. Set color of it to white."
  assert "bulk mentions create pronoun tie" (case resultPause paused of Just (1,_,ps) -> Set.fromList ps==Set.fromList [(0,0),(1,0)]; _ -> False)
  let resumed = runEntry blank [] 123 (entry "Set color of cells [A1, B1] to black. Set color of it to white.") [(1,0)] 1
  assert "replay continues exact update" (not (resultError resumed) && resultPause resumed==Nothing && cells (resultWorld resumed) Map.! (1,0)==White && cells (resultWorld resumed) Map.! (0,0)==Black)
  let batchPause = run blank "Atomically { Set color of cells [A1, B1] to black. Set color of it to white. }."
  assert "paused batch provisional only" (resultWorld batchPause==blank && resultRanking batchPause==[] && stagedWorld batchPause/=Nothing)
  let old = run blank "Set color of A1 to black. Does A1 satisfy neighbor count for color black is in [0]?"
      stale = purgeRanking (resultWorld (run (resultWorld old) "Set color of B1 to black.")) (resultRanking old)
  assert "neighbor fact purged after other cell changes" (all (notElem (fact (Atom (NeighborCount Black [0]))) . (\(_,_,facts) -> facts)) stale)
  let falseCheck = run blank "Does A1 satisfy color is black?"
  assert "false question property not retained" (all (notElem (fact (Atom (ColorIs Black))) . (\(_,_,facts) -> facts)) (resultRanking falseCheck))
  let many = blank {ruleset=Ruleset (Set.fromList [minBound..maxBound]) Moore Map.empty}
      colorful = many {cells=Map.union (Map.fromList [((0,0),Red),((1,0),Blue),((0,1),Green),((1,1),Yellow)]) (cells many)}
  rotated <- ok colorful "Rotate colors of cells in rectangle A1 to B2 by 90 degrees clockwise about the center of rectangle A1 to B2."
  assert "rotation permutes captured colors exactly" ([cells (resultWorld rotated) Map.! p | p <- [(0,0),(1,0),(0,1),(1,1)]] == [Blue,Yellow,Red,Green])
  assert "open geometric transform fails atomically" (resultError (run colorful "Rotate colors of cells [A1] by 90 degrees clockwise about the center of rectangle A1 to B2."))
  swapped <- ok colorful "Permute colors by [A1 to B1, B1 to A1]."
  assert "permutation preserves identities and captures both sources" (cells (resultWorld swapped) Map.! (0,0)==Blue && cells (resultWorld swapped) Map.! (1,0)==Red)
  let mentioned = run colorful "What is the color of A1?"
      predicted = runEntry (resultWorld mentioned) (resultRanking mentioned) 42
        (entry "After 1 generation, what is the color of it?") [] 0
  assert "forecast resolves current antecedent" (not (resultError predicted) && resultPause predicted==Nothing && "Resolved A1" `isInfixOf` resultFeedback predicted)
  let legacy = many {ruleset=(ruleset many) {rules=Map.singleton White (Rule Red Black (Set.singleton 0) True)}}
      inspected = run legacy "What is the ruleset? What is the next transition of A1?"
  assert "legacy nonbinary counted color disclosed without rewriting" (not (resultError inspected) && resultWorld inspected==legacy && "legacy counted color black" `isInfixOf` resultFeedback inspected)
  let cleanQuestion = run block "Does A1 satisfy changes in the next generation?"
  assert "prediction recheck participates in work cache" (not (resultError cleanQuestion))
  let timed = run block (unwords (replicate 17 "Advance 256 generations."))
  assert "resource exhaustion distinct and atomic per command" (resultError timed && generation (resultWorld timed)==4096 && "resource limit" `isInfixOf` resultFeedback timed)
  putStrLn "All cellular language checks passed."

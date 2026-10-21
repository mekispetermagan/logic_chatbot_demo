module Main where

import Control.Monad (unless)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Domains.Cellular.Types
import Domains.Cellular.Evaluation
import Ontology (Position)

assert :: String -> Bool -> IO ()
assert name success = unless success (error name)

life :: Ruleset
life = Ruleset (Set.fromList [White,Black]) Moore (Map.fromList
  [ (White, Rule Black Black (Set.singleton 3) True)
  , (Black, Rule White Black (Set.fromList [0,1,4,5,6,7,8]) True) ])

worldWith :: [Position] -> Automaton
worldWith live = Automaton
  (Map.fromList [(p, if p `elem` live then Black else White) | p <- boardPositions]) life 0 1

liveCells :: Automaton -> Set.Set Position
liveCells = Map.keysSet . Map.filter (== Black) . cells

advance :: Automaton -> Automaton
advance world = case step world of
  Right (next,_) -> next
  Left message -> error message

invalid :: Automaton -> Bool
invalid world = case step world of Left _ -> True; Right _ -> False

shift :: Position -> Position -> Position
shift (dx,dy) (x,y) = ((x+dx) `mod` 16, (y+dy) `mod` 16)

main :: IO ()
main = do
  assert "four toroidal A1 neighbors" (Set.fromList (neighbors Orthogonal (0,0)) == Set.fromList [(0,1),(1,0),(0,15),(15,0)])
  assert "eight toroidal A1 neighbors" (Set.fromList (neighbors Moore (0,0)) == Set.fromList [(0,1),(1,1),(1,0),(1,15),(0,15),(15,15),(15,0),(15,1)])
  assert "opposite edges adjacent" ((15,4) `elem` neighbors Orthogonal (0,4) && (3,15) `elem` neighbors Orthogonal (3,0))
  assert "distinct neighbors never include the cell" (and
    [length ns == neighborLimit mode && Set.size (Set.fromList ns) == length ns && p `notElem` ns
    | mode <- [Orthogonal,Moore], p <- boardPositions, let ns = neighbors mode p])

  let gliderCells = [(8,9),(9,8),(7,7),(8,7),(9,7)]
      glider = worldWith gliderCells
      first = advance glider
      fourth = iterate advance glider !! 4
  assert "known synchronous first glider step" (liveCells first == Set.fromList [(7,8),(9,8),(8,7),(9,7),(8,6)])
  assert "glider first change count" (fmap snd (step glider) == Right 4)
  assert "glider translates southeast in four generations" (liveCells fourth == Set.fromList (map (shift (1,-1)) gliderCells))
  assert "time advances; rules and revision persist" (generation fourth == 4 && ruleset fourth == life && rulesetRevision fourth == 1)
  assert "three generations change the preset visibly" (cells (iterate advance glider !! 3) /= cells glider)
  let wrapped = worldWith (map (shift (7,7)) gliderCells)
  assert "glider translation also crosses torus seams" (liveCells (iterate advance wrapped !! 4) == Set.map (shift (1,-1)) (liveCells wrapped))
  let block = worldWith [(3,3),(4,3),(3,4),(4,4)]
  assert "stable board still advances one generation" (fmap (\(w,n) -> (cells w,generation w,n)) (step block) == Right (cells block,1,0))
  assert "blinker updates simultaneously" (liveCells (advance (worldWith [(1,1),(2,1),(3,1)])) == Set.fromList [(2,0),(2,1),(2,2)])

  let allRed = Automaton (Map.fromList [(p,Red) | p <- boardPositions])
        (Ruleset (Set.fromList [minBound..maxBound]) Orthogonal
          (Map.singleton Red (Rule Blue Red (Set.singleton 4) True))) 17 3
      blue = advance allRed
      withRule rule = allRed {ruleset = (ruleset allRed) {rules = Map.singleton Red rule}}
  assert "generic six-color rules, not hardcoded Life" (all (== Blue) (Map.elems (cells blue)) && generation blue == 18 && rulesetRevision blue == 3)
  assert "disabled rules retain source color" (cells (advance (withRule (Rule Blue Red (Set.singleton 4) False))) == cells allRed)
  assert "missing rule retains source color" (cells (advance (allRed {ruleset = (ruleset allRed) {rules = Map.empty}})) == cells allRed)
  assert "zero neighbors can trigger a rule" (all (== Blue) (Map.elems (cells (advance (withRule (Rule Blue Green (Set.singleton 0) True))))))
  assert "false condition retains color" (cells (advance (withRule (Rule Blue Green (Set.singleton 1) True))) == cells allRed)
  assert "empty triggering set never fires" (cells (advance (withRule (Rule Blue Red Set.empty True))) == cells allRed)
  assert "out of range threshold rejected" (invalid (withRule (Rule Blue Red (Set.singleton 5) True)))
  assert "disabled invalid rule is still rejected" (invalid (withRule (Rule Blue Red (Set.singleton 9) False)))
  assert "same-color target rejected" (invalid (withRule (Rule Red Green Set.empty True)))
  assert "palette removal cannot strand cells or rules" (invalid (allRed {ruleset = (ruleset allRed) {palette = Set.fromList [White,Black]}}))
  assert "one-color palette rejected" (invalid (allRed {ruleset = (ruleset allRed) {palette = Set.singleton Red}}))
  assert "missing square rejected" (invalid (glider {cells = Map.delete (0,0) (cells glider)}))
  assert "out of board square rejected" (invalid (glider {cells = Map.insert (16,0) Black (cells glider)}))
  assert "negative generation rejected" (invalid (glider {generation = -1}))
  assert "invalid revision rejected" (invalid (glider {rulesetRevision = 0}))
  let old = glider {generation = 12, rulesetRevision = 7}
      painted = old {cells = Map.insert (15,15) Black (cells old)}
  assert "painting changes exactly one corner cell without advancing time" (paintCell old (15,15) Black == Right (painted,1))
  assert "same color is a no-op" (paintCell painted (15,15) Black == Right (painted,0))
  assert "painting white replaces black" (paintCell painted (15,15) White == Right (old,1))
  assert "all active colors are paintable" (and
    [fmap (\(w,n) -> (Map.lookup (0,0) (cells w), generation w, n)) (paintCell allRed (0,0) color)
       == Right (Just color,17,if color == Red then 0 else 1) | color <- [minBound..maxBound]])
  assert "inactive paint color rejected" (case paintCell old (0,0) Red of Left _ -> True; _ -> False)
  assert "painting outside board never wraps" (and
    [case paintCell old position Black of Left _ -> True; _ -> False | position <- [(-1,0),(0,-1),(16,0),(0,16)]])
  assert "painting validates the input world" (case paintCell (old {generation = -1}) (0,0) Black of Left _ -> True; _ -> False)
  assert "equivalent Life editor representation is a no-op" (replaceRuleset old (canonicalRuleset life) Nothing == Right (old,0))
  let alternate = life {neighborhood = Orthogonal, rules = Map.singleton White (Rule Black Black (Set.singleton 2) True)}
      edited = old {ruleset = alternate, rulesetRevision = 8}
      rgb = Ruleset (Set.fromList [Red,Green,Blue]) Moore (Map.fromList
        [(source,Rule target target (Set.fromList [2..8]) True) | (source,target) <- [(Red,Green),(Green,Blue),(Blue,Red)]])
  assert "rules-only change preserves cells and generation" (replaceRuleset old alternate Nothing == Right (edited,0))
  assert "new rules are used in the next generation" (ruleset (advance edited) == alternate && generation (advance edited) == 13)
  assert "refill permission does not reset a compatible board" (replaceRuleset old alternate (Just 42) == Right (edited,0))
  assert "palette removal requires refill confirmation" (case replaceRuleset old rgb Nothing of Left _ -> True; _ -> False)
  case replaceRuleset old rgb (Just 42) of
    Left message -> error message
    Right (filled,n) -> do
      assert "refill sets time zero and increments rules revision once" (generation filled == 0 && rulesetRevision filled == 8 && ruleset filled == rgb)
      assert "random refill uses only active colors" (Set.fromList (Map.elems (cells filled)) == palette rgb && n == 256)
      assert "refill is reproducible for a supplied seed" (replaceRuleset old rgb (Just 42) == Right (filled,n))
      assert "different seeds produce different fillings" (fmap (cells . fst) (replaceRuleset old rgb (Just 43)) /= Right (cells filled))
      assert "resubmitting accepted rules with refill permission is a no-op" (replaceRuleset filled rgb (Just 99) == Right (filled,0))
  assert "invalid replacement never gets hidden by refill" (case replaceRuleset old (rgb {palette = Set.singleton Red}) (Just 42) of Left _ -> True; _ -> False)
  assert "complementary Life counts preserve every black-cell case" (and
    [let w = worldWith ((8,8) : take n (neighbors Moore (8,8)))
     in cells (advance w) == cells (advance (w {ruleset = canonicalRuleset life})) | n <- [0..8]])
  putStrLn "All cellular checks passed."

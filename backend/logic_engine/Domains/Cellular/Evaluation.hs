module Domains.Cellular.Evaluation (neighbors, step, paintCell, replaceRuleset) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Word (Word64)
import Ontology (Position)
import Domains.Cellular.Types

neighbors :: Neighborhood -> Position -> [Position]
neighbors mode (x,y) = [((x+dx) `mod` boardSize, (y+dy) `mod` boardSize) | (dx,dy) <- offsets]
  where
    offsets = case mode of
      Orthogonal -> [(0,1),(1,0),(0,-1),(-1,0)]
      Moore -> [(0,1),(1,1),(1,0),(1,-1),(0,-1),(-1,-1),(-1,0),(-1,1)]

-- Every count reads the same immutable input board. No newly written cell
-- can influence another cell until the next call to step.
step :: Automaton -> Either String (Automaton, Int)
step input = do
  world <- validateAutomaton input
  let before = cells world
      config = ruleset world
      evolve position source = case Map.lookup source (rules config) of
        Just rule | enabled rule ->
          let count = length [() | neighbor <- neighbors (neighborhood config) position,
                                   Map.lookup neighbor before == Just (neighborColor rule)]
          in if count `Set.member` neighborCounts rule then targetColor rule else source
        _ -> source
      after = Map.mapWithKey evolve before
      changed = Map.size (Map.filterWithKey (\position color -> Map.lookup position before /= Just color) after)
  pure (world {cells = after, generation = generation world + 1}, changed)

-- Manual edits change only one cell; time and rule configuration stay intact.
paintCell :: Automaton -> Position -> Color -> Either String (Automaton, Int)
paintCell input position color = do
  world <- validateAutomaton input
  if Map.notMember position (cells world)
    then Left "Cell is outside the board"
    else if color `Set.notMember` palette (ruleset world)
      then Left "Color is not active in this ruleset"
      else pure (world {cells = Map.insert position color (cells world)},
                 if Map.lookup position (cells world) == Just color then 0 else 1)

-- Entropy is supplied by the caller. World generation and every semantic
-- decision remain pure and reproducible for that seed.
replaceRuleset :: Automaton -> Ruleset -> Maybe Word64 -> Either String (Automaton, Int)
replaceRuleset input requested seed = do
  world <- validateAutomaton input
  config <- validateRuleset requested
  let needsRefill = any (`Set.notMember` palette config) (Map.elems (cells world))
      nextCells = case seed of
        Just initial | needsRefill ->
          let colors = Set.toAscList (palette config)
              -- Word64 arithmetic wraps at 2^64. The high bits of this LCG
              -- avoid the short low-bit cycle for two/four-color palettes.
              stream = drop 1 (iterate (\n -> n * 6364136223846793005 + 1442695040888963407) initial)
              choose n = colors !! fromIntegral ((n `div` 4294967296) `mod` fromIntegral (length colors))
          in Map.fromList (zip boardPositions (map choose stream))
        _ -> cells world
  if needsRefill && seed == Nothing
    then Left "The palette excludes colors on the board; confirm a random refill"
    else if canonicalRuleset config == canonicalRuleset (ruleset world)
      then Right (world, 0)
      else do
        next <- validateAutomaton (world {cells = nextCells, ruleset = config,
          generation = if needsRefill then 0 else generation world,
          rulesetRevision = rulesetRevision world + 1})
        let changed = Map.size (Map.filterWithKey (\p c -> Map.lookup p (cells world) /= Just c) nextCells)
        Right (next, changed)

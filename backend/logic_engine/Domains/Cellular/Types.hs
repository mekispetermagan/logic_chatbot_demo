module Domains.Cellular.Types where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Ontology (Position)

data Color = White | Black | Red | Green | Blue | Yellow
  deriving (Eq, Ord, Read, Show, Enum, Bounded)

data Neighborhood = Orthogonal | Moore deriving (Eq, Read, Show)

data Rule = Rule
  { targetColor :: Color
  , neighborColor :: Color
  , neighborCounts :: Set.Set Int
  , enabled :: Bool
  } deriving (Eq, Read, Show)

data Ruleset = Ruleset
  { palette :: Set.Set Color
  , neighborhood :: Neighborhood
  , rules :: Map.Map Color Rule
  } deriving (Eq, Read, Show)

data Automaton = Automaton
  { cells :: Map.Map Position Color
  , ruleset :: Ruleset
  , generation :: Integer
  , rulesetRevision :: Integer
  } deriving (Eq, Read, Show)

boardSize :: Int
boardSize = 16

boardPositions :: [Position]
boardPositions = [(x, y) | y <- [0..boardSize-1], x <- [0..boardSize-1]]

neighborLimit :: Neighborhood -> Int
neighborLimit Orthogonal = 4
neighborLimit Moore = 8

validateAutomaton :: Automaton -> Either String Automaton
validateAutomaton world
  | Map.keysSet (cells world) /= Set.fromList boardPositions = Left "A cellular board must contain exactly the 256 squares A1 to P16"
  | generation world < 0 = Left "Generation must be nonnegative"
  | rulesetRevision world < 1 = Left "Ruleset revision must be positive"
  | any (`Set.notMember` active) (Map.elems (cells world)) = Left "A cell uses an inactive color"
  | otherwise = validateRuleset config >> Right world
  where
    config = ruleset world
    active = palette config

validateRuleset :: Ruleset -> Either String Ruleset
validateRuleset config
  | Set.size active < 2 || Set.size active > 6 = Left "The palette must contain between two and six colors"
  | any invalidRule (Map.toList (rules config)) = Left "Invalid rule: use distinct active source/target colors, an active neighbor color, and counts within the neighborhood"
  | otherwise = Right config
  where
    active = palette config
    invalidRule (source, rule) =
      any (`Set.notMember` active) [source, targetColor rule, neighborColor rule]
      || source == targetColor rule
      || any (\n -> n < 0 || n > neighborLimit (neighborhood config)) (Set.toList (neighborCounts rule))

-- With two colors, counting the other color is exactly the complementary
-- neighbor count. This preserves old Life rules when opening the new editor.
canonicalRuleset :: Ruleset -> Ruleset
canonicalRuleset config
  | Set.size (palette config) == 2 = config {rules = Map.map canonical (rules config)}
  | otherwise = config
  where
    canonical rule
      | neighborColor rule == targetColor rule = rule
      | otherwise = rule {neighborColor = targetColor rule,
                          neighborCounts = Set.map (neighborLimit (neighborhood config) -) (neighborCounts rule)}

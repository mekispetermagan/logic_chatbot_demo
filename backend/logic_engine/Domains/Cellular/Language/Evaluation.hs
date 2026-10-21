module Domains.Cellular.Language.Evaluation where

import Control.Monad (forM, unless, when)
import Control.Monad.Except
import Control.Monad.State.Strict
import Data.List (nub, sortOn, intercalate, find)
import Data.Maybe (fromMaybe)
import Data.Word (Word64)
import Text.Read (readMaybe)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified ControlledLanguage.Discourse as D
import Ontology (Position, Property(..))
import Domains.Cellular.Types
import qualified Domains.Cellular.Evaluation as E
import Domains.Cellular.Language.Syntax
import Domains.Cellular.Language.Pretty

type Ranking = D.SalienceRanking
data Failure = Blocked String | Choose [Position] deriving (Eq,Show)
data EvalState = EvalState
  { current :: Automaton, ranking :: Ranking, choices :: [Position]
  , mentions :: [(Position,[Property])], randomSeed :: Word64
  , work :: Int, cache :: [(Automaton,Automaton)] }
type Eval = ExceptT Failure (State EvalState)
data Outcome = Outcome
  { resultWorld :: Automaton, resultRanking :: Ranking, resultFeedback :: String
  , resultError :: Bool, resultPause :: Maybe (Int,String,[Position]), stagedWorld :: Maybe Automaton }

block :: String -> Eval a
block = throwError . Blocked
liftResult :: Either String a -> Eval a
liftResult = either block pure
nextOf :: Automaton -> Eval Automaton
nextOf w = do
  known <- gets cache
  case snd <$> find (\(prior,_) -> generation prior==generation w && rulesetRevision prior==rulesetRevision w && prior==w) known of
    Just next -> pure next
    Nothing -> do
      used <- gets work
      when (used >= 4096) (block "Evaluation resource limit reached; no answer computed")
      (next,_) <- liftResult (E.step w)
      modify (\s -> s {work=used+1,cache=(w,next):cache s})
      pure next
future :: Automaton -> Int -> Eval Automaton
future w 0 = pure w
future w n = nextOf w >>= \next -> future next (n-1)

componentOf :: Automaton -> Position -> Set.Set Position
componentOf w seed = visit Set.empty (Set.singleton seed)
  where
    hue = cells w Map.! seed
    visit seen frontier
      | Set.null frontier = seen
      | otherwise = let seen' = Set.union seen frontier
                        around = Set.fromList [q | p <- Set.toList frontier, q <- E.neighbors (neighborhood (ruleset w)) p, cells w Map.! q == hue]
                    in visit seen' (Set.difference around seen')

-- Conditions stored in discourse contain literal coordinates, never old pronouns.
fact :: Condition CellPredicate -> Property
fact c = Defined ("cellular:" ++ show c)
readFact :: Property -> Maybe (Condition CellPredicate)
readFact (Defined text) = case splitAt 9 text of ("cellular:",source) -> readMaybe source; _ -> Nothing
readFact _ = Nothing
conditionFacts :: Condition CellPredicate -> [Property]
conditionFacts c = nub (fact c : case c of And a b -> conditionFacts a ++ conditionFacts b; Or a b -> conditionFacts a ++ conditionFacts b; _ -> [])
needsNext :: Condition CellPredicate -> Bool
needsNext (Atom Changes) = True
needsNext (Not a) = needsNext a
needsNext (And a b) = needsNext a || needsNext b
needsNext (Or a b) = needsNext a || needsNext b
needsNext _ = False
combine :: (a -> Bool) -> Condition a -> Bool
combine f (Atom a) = f a
combine f (Not c) = not (combine f c)
combine f (And a b) = combine f a && combine f b
combine f (Or a b) = combine f a || combine f b
validGroundCondition :: Condition CellPredicate -> Bool
validGroundCondition = allAtoms valid
  where
    valid (SameCell (Cell p)) = validPosition p
    valid (SameColor (Cell p)) = validPosition p
    valid (NeighborOf (Cell p)) = validPosition p
    valid (ConnectedTo (Cell p)) = validPosition p
    valid (SameCell _) = False
    valid (SameColor _) = False
    valid (NeighborOf _) = False
    valid (ConnectedTo _) = False
    valid (NeighborCount _ ns) = length ns == length (nub ns) && all (\n -> n>=0 && n<=8) ns
    valid (RowIs n) = n>=0 && n<16
    valid (ColumnIs n) = n>=0 && n<16
    valid _ = True
allAtoms :: (a -> Bool) -> Condition a -> Bool
allAtoms f (Atom a) = f a
allAtoms f (Not a) = allAtoms f a
allAtoms f (And a b) = allAtoms f a && allAtoms f b
allAtoms f (Or a b) = allAtoms f a && allAtoms f b
validPosition :: Position -> Bool
validPosition (x,y) = x>=0 && x<16 && y>=0 && y<16

testCell :: Automaton -> Maybe Automaton -> Condition CellPredicate -> Position -> Bool
testCell w next c p = combine atom c
  where
    at r = cells w Map.! r
    atom Always = True
    atom (ColorIs hue) = at p == hue
    atom (RowIs y) = snd p == y
    atom (ColumnIs x) = fst p == x
    atom (SameCell (Cell q)) = p == q
    atom (SameColor (Cell q)) = at p == at q
    atom (NeighborOf (Cell q)) = p `elem` E.neighbors (neighborhood (ruleset w)) q
    atom (ConnectedTo (Cell q)) = p `Set.member` componentOf w q
    atom (NeighborCount hue ns) = length [() | q <- E.neighbors (neighborhood (ruleset w)) p, at q == hue] `elem` ns
    atom Changes = maybe False (\n -> Map.lookup p (cells n) /= Map.lookup p (cells w)) next
    atom _ = False
purgeRanking :: Automaton -> Ranking -> Ranking
purgeRanking w = purgeRankingWithNext w (either (const Nothing) (Just . fst) (E.step w))
purgeRankingWithNext :: Automaton -> Maybe Automaton -> Ranking -> Ranking
purgeRankingWithNext w next r = [(age,D.SquareReferent p,filter (truth p) facts) | (age,D.SquareReferent p,facts) <- r, validPosition p]
  where
    truth p stored = case readFact stored of
      Just c -> validGroundCondition c && countsFit w c && testCell w next c p
      Nothing -> False
rankingNeedsNext :: Ranking -> Bool
rankingNeedsNext r = any (maybe False needsNext . readFact) [f | (_,_,fs) <- r, f <- fs]
cleanRanking :: Eval Ranking
cleanRanking = do
  w <- gets current; r <- gets ranking
  next <- if rankingNeedsNext r then Just <$> nextOf w else pure Nothing
  pure (purgeRankingWithNext w next r)
finishSentence :: Eval ()
finishSentence = do
  w <- gets current; state <- get
  let grouped = Map.toList (Map.fromListWith (++) (mentions state))
      aged = D.advanceUtterance (ranking state)
      candidate = [((0,0),D.SquareReferent p,nub fs) | (p,fs) <- grouped] ++ aged
  next <- if rankingNeedsNext candidate then Just <$> nextOf w else pure Nothing
  modify (\s -> s {ranking=purgeRankingWithNext w next candidate})
countsFit :: Automaton -> Condition CellPredicate -> Bool
countsFit w = allAtoms (\p -> case p of NeighborCount _ ns -> all (<= neighborLimit (neighborhood (ruleset w))) ns; _ -> True)
record :: Position -> [Property] -> Eval ()
record p facts = modify (\s -> s {mentions=mentions s ++ [(p,facts)]})
choose :: [Position] -> Eval Position
choose [] = block "No matching cell"
choose [p] = pure p
choose ps = do
  supplied <- gets choices
  case supplied of
    p:rest | p `elem` ps -> modify (\s -> s {choices=rest}) >> pure p
    _ -> throwError (Choose (sortOn (\(x,y) -> (y,x)) (nub ps)))
resolve :: Reference -> Eval Position
resolve ref = do
  (p,associated) <- case ref of
    Cell p -> pure (p,[])
    It -> do
      r <- cleanRanking
      let eligible = [(age,p) | (age,D.SquareReferent p,_) <- r]
      when (null eligible) (block "No cell antecedent for it")
      p <- choose (nub [p | (age,p) <- eligible, age == minimum (map fst eligible)])
      pure (p,[])
    WithColor c -> described False (Atom (ColorIs c))
    Matching unique c -> described unique c
    Relative d r -> do
      (x,y) <- resolve r
      let (dx,dy) = fromMaybe (0,0) (lookup d [("north",(0,1)),("east",(1,0)),("south",(0,-1)),("west",(-1,0))])
      pure (((x+dx) `mod` 16,(y+dy) `mod` 16),[])
  record p associated
  pure p
  where
    described unique cond = do
      grounded <- ground cond
      w <- gets current
      predicate <- predicateFor w grounded
      r <- cleanRanking
      let candidates = filter predicate boardPositions
          alternatives = evidence grounded
          costs p = [(sum (map minimum matches),length fs) | fs <- alternatives,
            let matches = [[10*e+u | ((e,u),D.SquareReferent q,stored) <- r, p==q, f `elem` stored] | f <- fs], all (not . null) matches]
          ranked = sortOn (fst . snd) [(p,minimum (costs p)) | p <- candidates, not (null (costs p))]
          selected | unique = candidates
                   | otherwise = case ranked of [] -> candidates; (_, (best,_)):_ -> [p | (p,(score,n)) <- ranked, score-best < n+1]
      p <- choose selected
      pure (p,conditionFacts grounded)
    evidence (And a b) = [x++y | x <- evidence a, y <- evidence b]
    evidence (Or a b) = evidence a ++ evidence b
    evidence c = [[fact c]]
ground :: Condition CellPredicate -> Eval (Condition CellPredicate)
ground (Not c) = Not <$> ground c
ground (And a b) = And <$> ground a <*> ground b
ground (Or a b) = Or <$> ground a <*> ground b
ground (Atom c) = Atom <$> case c of
  SameCell r -> SameCell . Cell <$> resolve r
  SameColor r -> SameColor . Cell <$> resolve r
  NeighborOf r -> NeighborOf . Cell <$> resolve r
  ConnectedTo r -> ConnectedTo . Cell <$> resolve r
  _ -> pure c
predicateFor :: Automaton -> Condition CellPredicate -> Eval (Position -> Bool)
predicateFor w c = do
  unless (countsFit w c) (block "Neighbor count exceeds the active neighborhood")
  next <- if needsNext c then Just <$> nextOf w else pure Nothing
  pure (testCell w next c)
boardTest :: Automaton -> Condition BoardPredicate -> Eval Bool
boardTest w c = do
  next <- if not (allAtoms (/= FixedPoint) c) then Just <$> nextOf w else pure Nothing
  pure (combine (\a -> case a of
    Monochromatic Nothing -> Set.size (Set.fromList (Map.elems (cells w))) == 1
    Monochromatic (Just hue) -> all (== hue) (Map.elems (cells w))
    FixedPoint -> maybe False ((== cells w) . cells) next) c)

rectangle :: Position -> Position -> Eval [Position]
rectangle (x,y) (a,b) = do
  unless (x<=a && y<=b) (block "Rectangle requires bottom-left then top-right bounds")
  pure [(i,j) | j <- [y..b], i <- [x..a]]
distinct :: Eq a => [a] -> Eval [a]
distinct xs = unless (length xs == length (nub xs)) (block "Duplicate resolved cells") >> pure xs
selection :: Collection -> Eval [Position]
selection (Cells rs) = mapM resolve rs >>= distinct
selection (Filter c) = do
  grounded <- ground c; w <- gets current; predicate <- predicateFor w grounded
  pure (filter predicate boardPositions)
selection (Component r) = do p <- resolve r; w <- gets current; pure (Set.toList (componentOf w p))
selection (Rectangle p q) = rectangle p q
active :: Color -> Eval ()
active c = do w <- gets current; unless (c `Set.member` palette (ruleset w)) (block "Color is not active in this ruleset")
writeColors :: [(Position,Color)] -> Eval [String]
writeColors updates = do
  _ <- distinct (map fst updates)
  mapM_ (active . snd) updates
  w <- gets current
  let after = Map.union (Map.fromList updates) (cells w)
      changed = [(p,c) | (p,c) <- updates, Map.lookup p (cells w) /= Just c]
  modify (\s -> s {current=w {cells=after}})
  mapM_ (\(p,c) -> record p [fact (Atom (ColorIs c))]) updates
  pure $ if null updates then ["No matching cells"] else if null changed then ["No change"] else
    [positionText p ++ ": " ++ colorText (cells w Map.! p) ++ " -> " ++ colorText c | (p,c) <- changed]
setConfig :: Ruleset -> Maybe Word64 -> Eval [String]
setConfig config seed = do
  w <- gets current
  (next,n) <- liftResult (E.replaceRuleset w config seed)
  modify (\s -> s {current=next})
  pure $ if next==w then ["No change"] else
    ["Ruleset revision " ++ show (rulesetRevision next) ++ ": " ++ rulesetText (canonicalRuleset (ruleset next)),
     if generation next /= generation w || n>0 then "Board randomly refilled; generation 0; " ++ show n ++ " cells changed" else "Board preserved"]
nextSeed :: Eval Word64
nextSeed = do
  seed <- gets randomSeed
  modify (\s -> s {randomSeed=seed*6364136223846793005+1442695040888963407})
  pure seed
randomCells :: Word64 -> Set.Set Color -> Map.Map Position Color
randomCells seed activeColors = Map.fromList (zip boardPositions (map pick stream))
  where
    colors = Set.toAscList activeColors
    stream = drop 1 (iterate (\n -> n*6364136223846793005+1442695040888963407) seed)
    pick n = colors !! fromIntegral ((n `div` 4294967296) `mod` fromIntegral (length colors))

evalCommand :: Command -> Eval [String]
evalCommand command = case command of
  Paint xs c -> do active c; ps <- selection xs; writeColors [(p,c) | p <- ps]
  Advance n -> do
    w <- gets current; next <- future w n
    modify (\s -> s {current=next})
    pure ["Generation " ++ show (generation next) ++ "; advanced " ++ generationsText n ++ "; " ++ show (changedCount w next) ++ " cells differ from start"]
  SetRule c rule -> do
    active c; w <- gets current
    setConfig ((ruleset w) {rules=Map.insert c rule (rules (ruleset w))}) Nothing
  ClearRule c -> do
    active c; w <- gets current
    setConfig ((ruleset w) {rules=Map.delete c (rules (ruleset w))}) Nothing
  ToggleRule c yes -> do
    active c; w <- gets current
    r <- maybe (block "No stored rule for this color") pure (Map.lookup c (rules (ruleset w)))
    setConfig ((ruleset w) {rules=Map.insert c (r {enabled=yes}) (rules (ruleset w))}) Nothing
  SetNeighborhood n -> do w <- gets current; setConfig ((ruleset w) {neighborhood=n}) Nothing
  ReplaceRuleset config refill -> do seed <- if refill then Just <$> nextSeed else pure Nothing; setConfig config seed
  Initialize -> do
    w <- gets current; seed <- nextSeed
    let next = w {cells=randomCells seed (palette (ruleset w)),generation=0}
    modify (\s -> s {current=next})
    pure ["Board randomly initialized; generation 0; " ++ show (changedCount w next) ++ " cells changed"]
  Copy a b -> do p <- resolve a; q <- resolve b; w <- gets current; writeColors [(q,cells w Map.! p)]
  Exchange a b -> do
    p <- resolve a; q <- resolve b; w <- gets current
    writeColors (if p==q then [(p,cells w Map.! p)] else [(q,cells w Map.! p),(p,cells w Map.! q)])
  ReplaceColors entries -> do pairs <- mapM (\(r,c) -> do p <- resolve r; pure (p,c)) entries; writeColors pairs
  Permute entries -> do
    pairs <- mapM (\(r,s) -> (,) <$> resolve r <*> resolve s) entries
    _ <- distinct (map fst pairs); _ <- distinct (map snd pairs)
    unless (Set.fromList (map fst pairs) == Set.fromList (map snd pairs)) (block "Color permutation must have identical source and destination sets")
    w <- gets current; writeColors [(q,cells w Map.! p) | (p,q) <- pairs]
  Shift dx dy -> do
    w <- gets current
    let shifted (x,y) = (fromInteger ((toInteger x+toInteger dx) `mod` 16),fromInteger ((toInteger y+toInteger dy) `mod` 16))
    let updates = [(shifted p,cells w Map.! p) | p <- boardPositions]
    -- The implicit 256-cell algorithm is not 256 dialogue mentions.
    lines' <- writeColors updates
    modify (\s -> s {mentions=[]})
    pure ["Shifted board colors; " ++ show (length [() | (p,c) <- updates, cells w Map.! p /= c]) ++ " cells changed" | not (null lines')]
  Spatial xs operation p q -> do
    _ <- rectangle p q
    ps <- selection xs
    when (null ps) (block "Geometric selection is empty")
    let (cx,cy) = (fst p+fst q,snd p+snd q)
        destination (x,y) = let (a,b) = (2*x-cx,2*y-cy)
                                (u,v) = case operation of Rotation 90 -> (b,-a); Rotation 180 -> (-a,-b); Rotation _ -> (-b,a); Reflection True -> (-a,b); Reflection False -> (a,-b)
                            in (u+cx,v+cy)
        doubled = map destination ps
    unless (all (\(x,y) -> even x && even y) doubled) (block "Transform does not map to exact cell centers")
    let qs = [(x `div` 2,y `div` 2) | (x,y) <- doubled]
    unless (all validPosition qs && Set.fromList ps == Set.fromList qs) (block "Transform must be a closed permutation of the selected cells")
    w <- gets current; writeColors [(b,cells w Map.! a) | (a,b) <- zip ps qs]

changedCount :: Automaton -> Automaton -> Int
changedCount a b = Map.size (Map.filterWithKey (\p c -> Map.lookup p (cells a) /= Just c) (cells b))

-- Ground references now, before switching to a hypothetical configuration.
groundQuestion :: Question -> Eval Question
groundQuestion (ColorOf r) = ColorOf . Cell <$> resolve r
groundQuestion (Check r c) = Check <$> (Cell <$> resolve r) <*> ground c
groundQuestion (Transition r) = Transition . Cell <$> resolve r
groundQuestion (Select count seed c) = Select count <$> traverse (fmap Cell . resolve) seed <*> ground c
groundQuestion (Quantify every p q) = Quantify every <$> ground p <*> ground q
groundQuestion q = pure q

evalQuestion :: Question -> Eval [String]
evalQuestion q = case q of
  Forecast n body -> do
    grounded <- groundQuestion body
    w <- gets current; explicit <- gets mentions
    next <- future w n
    modify (\s -> s {current=next,mentions=[]})
    answers <- evalQuestion grounded
    -- Future answers are not current facts. Keep only truthful current operands.
    modify (\s -> s {current=w,mentions=explicit})
    pure (("Forecast after " ++ generationsText n ++ " (ruleset revision " ++ show (rulesetRevision w) ++ ")"):answers)
  ReturnTime n -> do
    w <- gets current
    answer <- firstOffset w n (\futureWorld -> pure (cells futureWorld == cells w))
    pure [maybe (nonmatch n) show answer]
  FirstCell n r c -> do
    p <- resolve r; grounded <- ground c; w <- gets current
    -- Compile once now as well, to reject invalid counts eagerly.
    _ <- predicateFor w grounded
    answer <- firstOffset w n (\fw -> do predicate <- predicateFor fw grounded; pure (predicate p))
    pure [maybe (nonmatch n) show answer]
  FirstBoard n c -> do
    w <- gets current; answer <- firstOffset w n (\fw -> boardTest fw c)
    pure [maybe (nonmatch n) show answer]
  CountReaches c target n -> do
    -- Resolve reference operands once against the current world. Only the
    -- predicate's truth changes while examining hypothetical configurations.
    grounded <- ground c
    w <- gets current
    predicate <- predicateFor w grounded
    answer <- if length (filter predicate boardPositions) == target
      then pure (Just 0)
      else firstOffset w n (\fw -> do
        futurePredicate <- predicateFor fw grounded
        pure (length (filter futurePredicate boardPositions) == target))
    pure [case answer of
      Just k -> "true; count reaches " ++ show target ++ " at generation offset " ++ show k
                ++ if k == 0 then " (already matches)" else ""
      Nothing -> "false; count does not reach " ++ show target ++ " within " ++ generationsText n]
  Stabilization yes n -> do
    w <- gets current
    answer <- stabilize w n 0
    pure [case answer of
      Nothing -> if yes then "false; no fixed point within " ++ generationsText n else nonmatch n
      Just k -> (if yes then "true; " else "") ++ "stabilization time " ++ show k ++ if k==0 then " (already a fixed point)" else ""]
  _ -> do
    grounded <- groundQuestion q
    w <- gets current
    case grounded of
      ColorOf (Cell p) -> do record p [fact (Atom (ColorIs (cells w Map.! p)))]; pure [colorText (cells w Map.! p)]
      Check (Cell p) c -> do predicate <- predicateFor w c; record p (conditionFacts c); pure [boolText (predicate p)]
      Meta Generation -> pure [show (generation w)]
      Meta Palette -> pure [listText colorText (Set.toAscList (palette (ruleset w)))]
      Meta NeighborhoodName -> pure [neighborhoodText (neighborhood (ruleset w)) ++ " (" ++ show (neighborLimit (neighborhood (ruleset w))) ++ " neighbors)"]
      Meta Revision -> pure [show (rulesetRevision w)]
      Meta CompleteRuleset -> pure [inspectRuleset (ruleset w)]
      RuleOf c -> pure [case Map.lookup c (rules (canonicalRuleset (ruleset w))) of
        Nothing -> "none (" ++ (if c `Set.member` palette (ruleset w) then "no stored rule" else "inactive color") ++ ")"
        Just r -> inspectRule r]
      Select count seed c -> do
        predicate <- predicateFor w c
        let universe = maybe boardPositions (\(Cell p) -> E.neighbors (neighborhood (ruleset w)) p) seed
            ps = sortOn (\(x,y) -> (y,x)) (filter predicate universe)
        pure [if count then show (length ps) else listText positionText ps]
      Quantify every restriction c -> do
        restrict <- predicateFor w restriction; predicate <- predicateFor w c
        let ps = filter restrict boardPositions
            answer = if every then all predicate ps else any predicate ps
        pure [boolText answer ++ if null ps then "; no matching cells" else ""]
      CheckBoard c -> (:[]) . boolText <$> boardTest w c
      Transition (Cell p) -> do
        let source = cells w Map.! p
        next <- nextOf w
        record p [fact (Atom (ColorIs source))]
        let result = colorText (cells next Map.! p)
            detail = case Map.lookup source (rules (canonicalRuleset (ruleset w))) of
              Nothing -> "no stored rule; target/count not applicable"
              Just r -> let n = length [() | a <- E.neighbors (neighborhood (ruleset w)) p, cells w Map.! a == neighborColor r]
                        in inspectRule r ++ "; actual " ++ colorText (neighborColor r) ++ " neighbors " ++ show n ++ "; " ++
                          if not (enabled r) then "disabled" else if Set.null (neighborCounts r) then "empty count set; never fires" else if n `Set.member` neighborCounts r then "rule fires" else "count does not match"
        pure [positionText p ++ ": " ++ colorText source ++ "; " ++ detail ++ "; result " ++ result]
      _ -> block "Invalid cellular question"
  where
    nonmatch n = "none within " ++ generationsText n
    stabilize w bound k = do
      next <- nextOf w
      if cells next==cells w then pure (Just k) else if k>=bound then pure Nothing else stabilize next bound (k+1)
firstOffset :: Automaton -> Int -> (Automaton -> Eval Bool) -> Eval (Maybe Int)
firstOffset w bound predicate = walk w 1
  where
    walk current k = do
      next <- nextOf current
      matches <- predicate next
      if matches then pure (Just k) else if k>=bound then pure Nothing else walk next (k+1)
boolText :: Bool -> String
boolText True = "true"
boolText False = "false"
inspectRule :: Rule -> String
inspectRule r = ruleText r ++ if neighborColor r /= targetColor r then "; legacy counted color " ++ colorText (neighborColor r) ++ " (preserved; explicit replacement required to edit)" else ""
inspectRuleset :: Ruleset -> String
inspectRuleset config = let normalized = canonicalRuleset config
                       in rulesetText normalized ++ concat ["; " ++ colorText c ++ ": " ++ inspectRule r | (c,r) <- Map.toList (rules normalized), neighborColor r /= targetColor r]

runEntry :: Automaton -> Ranking -> Word64 -> Entry -> [Position] -> Int -> Outcome
runEntry world initialRanking seed entry supplied skip = walk initial 0 [] sentences
  where
    initial = EvalState world (D.beginEntry initialRanking) supplied [] seed 0 []
    batch = case entry of Batch _ -> True; _ -> False
    sentences = case entry of Sequence xs -> xs; Batch cs -> map Command cs; Undo -> []
    output state blocks pause failed =
      let provisional = batch && (failed || pause /= Nothing)
          prefix | batch && failed = "Atomic batch failed; nothing was applied.\n"
                 | provisional = "Provisional batch; nothing was applied.\n"
                 | otherwise = ""
      in Outcome (if provisional then world else current state) (if provisional then initialRanking else ranking state)
           (prefix ++ intercalate "\n" (drop (if batch then 0 else skip) blocks)) failed pause
           (if batch && pause /= Nothing then Just (current state) else Nothing)
    walk state _ blocks [] = output state blocks Nothing False
    walk state completed blocks (sentence:rest) =
      let action = do
            lines' <- case sentence of Command c -> evalCommand c; Question q -> evalQuestion q
            finishSentence
            pure lines'
          (result,attempted) = runState (runExceptT action) state {mentions=[]}
          format lines' = sentenceText sentence ++ "\n  " ++ intercalate "\n  " lines'
      in case result of
        Right lines' ->
          let grouped = Map.toList (Map.fromListWith (++) (mentions attempted))
              next = attempted {mentions=[]}
              resolved = ["Resolved " ++ intercalate ", " (map (positionText . fst) grouped) | not (null grouped)]
          in walk next (completed+1) (blocks ++ [format (resolved ++ lines')]) rest
        Left (Blocked message) -> output (state {ranking=D.advanceUtterance (ranking state)})
          (blocks ++ [format ([message] ++ ["Not executed: " ++ show (length rest) ++ " remaining sentences" | not (null rest)])]) Nothing True
        Left (Choose ps) -> output state (blocks ++ [format ["Which cell?"]]) (Just (completed,sentenceText sentence,ps)) False

module ControlledLanguage.Evaluation where

import Control.Monad (forM, forM_, when, unless)
import Control.Monad.Except
import Control.Monad.State.Strict
import Data.List (nub, sortOn, intercalate, isPrefixOf)
import Text.Read (readMaybe)
import Pretty (pretty)
import Data.Maybe (isJust, fromMaybe)
import qualified Data.Map.Strict as Map
import Ontology
import qualified ControlledLanguage.Discourse as D
import qualified Discourse as Legacy
import qualified Layer2Syntax as Old
import Domains.Objects.Definition (objectsDomain)
import ControlledLanguage.Domain
import qualified Domains.Network.Patterns as Ports
import qualified Domains.Network.Syntax as Net
import qualified Domains.Network.Graph as Graph
import qualified Domains.Network.Analysis as Analysis
import qualified Domains.Network.Pathfinding as Pathfinding
import Domain (Domain, inDomainBounds, validProperty)
import qualified WorldEditor as Editor
import ControlledLanguage.Syntax
import ControlledLanguage.Pretty

data Change = Change { changeObject :: Int, changeKind :: String, changeDetail :: String } deriving (Eq,Show)
data Failure = Blocked String | ChooseObjects [Int] | ChooseSquares [Position] | ChooseReferents [D.Referent] deriving (Eq,Show)
data EvalState = EvalState
  { activeDomain :: Domain, currentWorld :: World, currentRanking :: D.SalienceRanking, freshId :: Int
  , providedChoices :: [Choice], mentions :: [(D.Referent,[Property])]
  , graphContext :: Maybe (World,GraphExpr), groundedConditions :: [(Condition,Condition)] }
type Eval = ExceptT Failure (State EvalState)
data Outcome = Outcome
  { resultWorld :: World, resultRanking :: D.SalienceRanking, resultNextId :: Int
  , resultFeedback :: String, resultError :: Bool, resultChanges :: [Change]
  , resultPause :: Maybe (Int,String,[Int],[Position]), stagedWorld :: Maybe World }

objectAtId :: World -> Int -> Maybe Object
objectAtId (World objects) n = case filter ((== Id n) . idOf) objects of [o] -> Just o; _ -> Nothing
objectsOf :: World -> [Object]
objectsOf (World objects) = objects
property :: (String,String) -> Property
property (a,v) = AttributeValue (AttributeId a) (ValueId v)
appearanceOf :: Object -> [(String,Maybe String)]
appearanceOf object = [(a, fmap (\(ValueId v) -> v) (attributeOf (AttributeId a) object)) | a <- appearanceAttributes]
propertiesOf :: Object -> String -> [Property]
propertiesOf object "position" = maybe [] ((:[]) . P) (positionOf object)
propertiesOf object "row" = propertiesOf object "position"
propertiesOf object "column" = propertiesOf object "position"
propertiesOf object "appearance" = [AttributeValue a v | (a,v) <- Map.toList (attributesOf object)]
propertiesOf object "pattern" = map Ports.portProperty (Ports.openPorts object) ++ [contextFact (PatternIs (patternOf object))]
propertiesOf object a = maybe [] ((:[]) . AttributeValue (AttributeId a)) (attributeOf (AttributeId a) object)
record :: Object -> [Property] -> Eval ()
record object properties = modify (\s -> s {mentions = mentions s ++ [(D.ObjectReferent (idOf object),properties)]})
getObject :: Int -> Eval Object
getObject n = do w <- gets currentWorld; maybe (throwError (Blocked ("No object at #" ++ show n))) pure (objectAtId w n)
selectChoice :: [Int] -> Eval Int
selectChoice identifiers = do
  choices <- gets providedChoices
  case choices of
    ObjectChoice n:rest | n `elem` identifiers -> modify (\s -> s {providedChoices=rest}) >> pure n
    _ -> throwError (ChooseObjects identifiers)
resolve :: Ref -> Eval Object
resolve reference = do
  domain <- gets activeDomain
  world <- gets currentWorld
  ranking <- gets currentRanking
  object <- case reference of
    Ident n -> getObject n
    At square -> do
      p <- locateSquare square
      case filter ((== Just p) . positionOf) (objectsOf world) of
        [o] -> pure o
        [] -> throwError (Blocked ("No object at " ++ prettyPosition p))
        os -> selectChoice (map (idToInt . idOf) os) >>= getObject
    Unique c -> do
      predicate <- withContext Nothing (objectPredicate c)
      case filter (fst . predicate) (objectsOf world) of
        [] -> throwError (Blocked "No matching object")
        [o] -> pure o
        os -> selectChoice (map (idToInt . idOf) os) >>= getObject
    Described c -> do
      predicate <- withContext Nothing (objectPredicate c)
      grounded <- groundCondition c
      chooseAnaphoric (fst . predicate) (evidenceOptions grounded) world ranking
    Anaphoric d | isNetwork domain -> do
      let c = foldl1 And [if a == "pattern" then PatternIs v else ValueIs a v | (a,v) <- d]
      predicate <- withContext Nothing (objectPredicate c)
      grounded <- groundCondition c
      chooseAnaphoric (fst . predicate) (evidenceOptions grounded) world ranking
    It -> do
      referent <- resolvePronoun [ObjectKind]
      case referent of
        D.ObjectReferent identifier -> getObject (idToInt identifier)
        _ -> throwError (Blocked "Expected an object antecedent")
    Anaphoric d ->
      case Legacy.resolveSubjectUsing (truthFor domain) (:[]) domain False world (D.objectRanking ranking) (Old.Definite (map property d)) of
        Legacy.Resolved _ identifier -> getObject (idToInt identifier)
        Legacy.Unresolved message -> throwError (Blocked message)
        Legacy.Ambiguous ids -> selectChoice (map idToInt ids) >>= getObject
  props <- case reference of
    Anaphoric d -> associatedWith object (foldl1 And [if a == "pattern" then PatternIs v else ValueIs a v | (a,v) <- d])
    Unique c -> associatedWith object c
    Described c -> associatedWith object c
    At _ -> pure (propertiesOf object "position")
    _ -> pure []
  record object props
  pure object
-- Nested location selectors do not turn an object mention into a square mention.
-- Standalone square operands explicitly record their location, occupied or not.
resolveSquare :: Square -> Eval Position
resolveSquare square = do
  p <- locateSquare square
  recordSquare p []
  pure p
locateSquare :: Square -> Eval Position
locateSquare (Cell p) = checkedPosition (toInteger (fst p),toInteger (snd p))
locateSquare SquareIt = do
  referent <- resolvePronoun [SquareKind]
  case referent of
    D.SquareReferent p -> pure p
    _ -> throwError (Blocked "Expected a square antecedent")
locateSquare (Neighbor d reference) = do
  object <- resolve reference
  p <- requirePlaced "Reference object is unplaced" object
  checkedPosition (addInteger p (offset d))
recordSquare :: Position -> [Property] -> Eval ()
recordSquare p facts = modify (\s -> s {mentions=mentions s ++ [(D.SquareReferent p,facts)]})
squareFact :: Condition -> Property
squareFact c = Defined ("square:" ++ show c)
referentKind :: D.Referent -> ReferentKind
referentKind (D.ObjectReferent _) = ObjectKind
referentKind (D.SquareReferent _) = SquareKind
resolvePronoun :: [ReferentKind] -> Eval D.Referent
resolvePronoun kinds = do
  domain <- gets activeDomain
  world <- gets currentWorld
  ranking <- gets currentRanking
  let eligible = [(age,r) | (age,r,_) <- purgeRanking domain world ranking, referentKind r `elem` kinds]
      missing = case kinds of [ObjectKind] -> "No object antecedent for it"; [SquareKind] -> "No square antecedent for it"; _ -> "No antecedent for it"
  case eligible of
    [] -> throwError (Blocked missing)
    _ -> chooseReferent (nub [r | (age,r) <- eligible, age == minimum (map fst eligible)])
chooseReferent :: [D.Referent] -> Eval D.Referent
chooseReferent [r] = pure r
chooseReferent candidates = do
  choices <- gets providedChoices
  let toReferent (ObjectChoice n) = D.ObjectReferent (Id n)
      toReferent (SquareChoice p) = D.SquareReferent p
  case choices of
    choice:rest | toReferent choice `elem` candidates -> do
      modify (\s -> s {providedChoices=rest})
      pure (toReferent choice)
    _ -> throwError (ChooseReferents candidates)
requirePlaced :: String -> Object -> Eval Position
requirePlaced message object = maybe (throwError (Blocked message)) pure (positionOf object)
checkedPosition :: (Integer,Integer) -> Eval Position
checkedPosition (x,y)
  | x < 0 || y < 0 || x > 7 || y > 7 = throwError (Blocked "Outside board")
  | otherwise = pure (fromInteger x,fromInteger y)
addInteger :: Position -> Position -> (Integer,Integer)
addInteger (x,y) (a,b) = (toInteger x+toInteger a,toInteger y+toInteger b)
distinct :: [Object] -> Eval [Object]
distinct os = do
  unless (length os == length (nub (map idOf os))) (throwError (Blocked "Duplicate objects in selection"))
  pure os
resolveCollection :: Collection -> Eval [Object]
resolveCollection collection = do
  objects <- case collection of
    Objects refs -> mapM resolve refs >>= distinct
    AtSquares squares -> mapM (resolve . At) squares >>= distinct
    InGraph expression -> objectsOf . fst <$> evalGraph expression
    Matching c -> do
      predicate <- objectPredicate c
      filter (fst . predicate) . objectsOf <$> gets currentWorld
  forM_ objects (\o -> case collection of Matching c -> associatedWith o c >>= record o; _ -> record o [])
  pure objects
resolveTargets :: Targets -> Eval [Object]
resolveTargets (One r) = (:[]) <$> resolve r
resolveTargets (Many c) = resolveCollection c

-- Compile all explicit targets before evaluating any Boolean branch or bound member.
type Predicate a = a -> (Bool,[String])
combine :: (Bool -> Bool -> Bool) -> Predicate a -> Predicate a -> Predicate a
combine op left right x = let (a,an) = left x; (b,bn) = right x in (op a b,nub (an++bn))
plain :: (a -> Bool) -> Predicate a
plain f x = (f x,[])
objectPredicate :: Condition -> Eval (Predicate Object)
objectPredicate c = case c of
  Truth -> pure (plain (const True))
  ValueIs a v -> pure (plain (\o -> attributeOf (AttributeId a) o == Just (ValueId v)))
  Present a b -> pure (plain (\o -> isJust (valueOf o a) == b))
  PositionIs p -> pure (plain ((== Just p) . positionOf))
  IdentifierIs n -> pure (plain ((== Id n) . idOf))
  Not a -> do p <- objectPredicate a; pure (\o -> let (b,n) = p o in (not b,n))
  And a b -> combine (&&) <$> objectPredicate a <*> objectPredicate b
  Or a b -> combine (||) <$> objectPredicate a <*> objectPredicate b
  EqualAttribute a reference present -> do
    other <- resolve reference; remember c (EqualAttribute a (Ident (idToInt (idOf other))) present); record other (propertiesOf other a)
    pure (\object -> let l = valueOf object a; r = valueOf other a
                         note = ["both lack " ++ a | not present && l == Nothing && r == Nothing]
                     in (l == r && (not present || isJust l),note))
  SameObject r -> do other <- resolve r; remember c (SameObject (Ident (idToInt (idOf other)))); pure (plain ((== idOf other) . idOf))
  Adjacent r -> spatial (\n -> Adjacent (Ident n)) r (\p q -> manhattan p q == 1)
  Directed d r -> spatial (\n -> Directed d (Ident n)) r (\p q -> addInteger q (offset d) == (toInteger (fst p),toInteger (snd p)))
  Edge -> pure (plain (maybe False edge . positionOf))
  Corner -> pure (plain (maybe False corner . positionOf))
  Coordinate a n -> pure (plain (maybe False ((== n) . if a == "row" then snd else fst) . positionOf))
  OnSquare c' -> do p <- squarePredicate c'; pure (plain (maybe False (fst . p) . positionOf))
  PatternIs pattern -> pure (plain ((== pattern) . patternOf))
  NetworkRole name scope -> do
    context <- gets graphContext
    (view,grounded) <- currentView scope
    let intrinsic = name `elem` ["dot","tip","straight","bend","tee","cross"]
        unscoped = scope == Nothing && context == Nothing && intrinsic
    remember c (NetworkRole name (if unscoped then Nothing else Just grounded))
    pure (plain (\o -> (unscoped || Analysis.contains view o) && Analysis.role name view o))
  NetworkRelation name reference scope -> do
    other <- resolve reference
    (view,grounded) <- currentView scope
    remember c (NetworkRelation name (Ident (idToInt (idOf other))) (Just grounded))
    pure (plain (\o -> Analysis.contains view o && Analysis.contains view other &&
      if name == "linked" then any ((== idOf other) . idOf) (Graph.neighbors view o)
      else Analysis.shortestPath view o other /= Nothing))
  _ -> throwError (Blocked "Invalid object predicate")
  where
    spatial constructor r f = do other <- resolve r; remember c (constructor (idToInt (idOf other))); pure (plain (\o -> case (positionOf o,positionOf other) of (Just p,Just q) -> f p q; _ -> False))
squarePredicate :: Condition -> Eval (Predicate Position)
squarePredicate c = case c of
  Truth -> pure (plain (const True))
  Occupied -> do w <- gets currentWorld; pure (plain (\p -> any ((== Just p) . positionOf) (objectsOf w)))
  Shading light -> pure (plain (\(x,y) -> odd (x+y) == light))
  Coordinate a n -> pure (plain ((== n) . if a == "row" then snd else fst))
  Edge -> pure (plain edge)
  Corner -> pure (plain corner)
  Not a -> do p <- squarePredicate a; pure (\x -> let (b,n) = p x in (not b,n))
  And a b -> combine (&&) <$> squarePredicate a <*> squarePredicate b
  Or a b -> combine (||) <$> squarePredicate a <*> squarePredicate b
  _ -> throwError (Blocked "Invalid square predicate")
edge, corner :: Position -> Bool
edge (x,y) = x `elem` [0,7] || y `elem` [0,7]
corner (x,y) = x `elem` [0,7] && y `elem` [0,7]
manhattan :: Position -> Position -> Int
manhattan (x,y) (a,b) = abs (x-a)+abs (y-b)
valueOf :: Object -> String -> Maybe String
valueOf object a = case a of
  "position" -> prettyPosition <$> positionOf object
  "row" -> show . (+1) . snd <$> positionOf object
  "column" -> (\p -> [toEnum (fromEnum 'A'+fst p)]) <$> positionOf object
  "identifier" -> Just ("#" ++ show (idToInt (idOf object)))
  "appearance" -> Just (appearanceText (appearanceOf object))
  "pattern" -> Just (patternOf object)
  _ -> (\(ValueId v) -> v) <$> attributeOf (AttributeId a) object
associated :: Object -> Condition -> [Property]
associated o c = case c of
  ValueIs a v -> [property (a,v)]
  PositionIs p -> [P p]
  Present a _ -> propertiesOf o a
  EqualAttribute a _ _ -> propertiesOf o a
  Coordinate _ _ -> propertiesOf o "position"
  Not a -> associated o a
  And a b -> associated o a ++ associated o b
  Or a b -> associated o a ++ associated o b
  _ -> []

replace :: [Object] -> Eval ()
replace updates = do
  domain <- gets activeDomain
  World objects <- gets currentWorld
  let updated = [fromMaybe o (lookup (idOf o) [(idOf u,u) | u <- updates]) | o <- objects]
      positions = [p | o <- updated, Just p <- [positionOf o]]
  unless (all (\o -> all (validProperty domain . uncurry AttributeValue) (Map.toList (attributesOf o))) updates)
    (throwError (Blocked "Invalid attribute/value"))
  unless (all (inDomainBounds domain) positions) (throwError (Blocked "Outside board"))
  unless (length positions == length (nub positions)) (throwError (Blocked "Destination occupied"))
  modify (\s -> s {currentWorld=World updated})
replaceWith :: [String] -> [Object] -> Eval ()
replaceWith names updates = do
  replace updates
  domain <- gets activeDomain
  let components = names ++ ["pattern" | isNetwork domain && "appearance" `elem` names]
  forM_ updates (\o -> record o (concatMap (propertiesOf o) components))
newObject :: [(String,Maybe String)] -> Maybe Position -> Eval Object
newObject supplied position = do
  domain <- gets activeDomain
  unless (all (\(a,v) -> a /= "pattern" || maybe False validPattern v) supplied)
    (throwError (Blocked "Invalid exact pattern"))
  let attrs = expandFields supplied
  world <- gets currentWorld
  unless (maybe True (inDomainBounds domain) position) (throwError (Blocked "Outside board"))
  unless (all (\(a,v) -> a `elem` appearanceAttributesFor domain && maybe True (validProperty domain . property . (,) a) v) attrs)
    (throwError (Blocked "Invalid attribute/value"))
  when (maybe False (\p -> any ((== Just p) . positionOf) (objectsOf world)) position)
    (throwError (Blocked "Destination occupied"))
  n <- gets freshId
  when (n < 0 || n >= maxBound) (throwError (Blocked "Identifier space exhausted"))
  unless (all ((< Id n) . idOf) (objectsOf world)) (throwError (Blocked "Invalid identifier allocation state"))
  let object = Object (Id n) (Map.fromList [(AttributeId a,ValueId v) | (a,Just v) <- attrs]) position
  modify (\s -> s {currentWorld=World (object:objectsOf world),freshId=n+1})
  record object (propertiesOf object "appearance" ++ propertiesOf object "position" ++
    [contextFact (PatternIs (patternOf object)) | isNetwork domain])
  pure object
setFields :: [(String,Maybe String)] -> Object -> Object
setFields attrs object = foldl (\o (a,v) -> setAttribute (AttributeId a) (ValueId <$> v) o) object attrs
componentOf :: Domain -> String -> Object -> [(String,Maybe String)]
componentOf domain "appearance" = appearanceOfWith domain
componentOf _ "pattern" = filter ((`elem` portNames) . fst) . appearanceOfWithNetwork
componentOf domain a = filter ((== a) . fst) . appearanceOfWith domain
moveObjects :: [(Object,Position)] -> Eval ()
moveObjects pairs = replaceWith ["position"] [o {positionOf=Just p} | (o,p) <- pairs]
emptyMessage :: [a] -> [String]
emptyMessage [] = ["No matching objects"]
emptyMessage _ = []
evalCommand :: Command -> Eval [String]
evalCommand command = do
  domain <- gets activeDomain
  case command of
    PortState t direction opened -> do
      os <- resolveTargets t
      let name = directionText direction
      replaceWith [name] [setFields [(name,if opened then Just name else Nothing)] o | o <- os]
      pure (emptyMessage os)
    SetPattern t pattern -> do
      unless (validPattern pattern) (throwError (Blocked "Invalid exact pattern"))
      os <- resolveTargets t; replaceWith ["pattern"] (map (setPattern pattern) os); pure (emptyMessage os)
    TransformPorts t operation -> do os <- resolveTargets t; replaceWith ["pattern"] (map (transformPorts operation) os); pure (emptyMessage os)
    TransformDrawing collection operation bounds -> do
      os <- resolveCollection collection
      when (null os) (throwError (Blocked "No selected objects"))
      ps <- mapM (requirePlaced "Object is unplaced") os
      let ((x,y),(a,b)) = bounds
      qs <- mapM (transform operation (toInteger x+toInteger a,toInteger y+toInteger b)) ps
      replaceWith ["position","pattern"] [(transformPorts operation o) {positionOf=Just q} | (o,q) <- zip os qs]
      pure []
    Link a b linked -> do left <- resolve a; right <- resolve b; linkObjects left right linked; pure []
    Extend reference direction -> do
      source <- resolve reference; p <- requirePlaced "Object is unplaced" source
      q <- checkedPosition (addInteger p (offset direction))
      target <- newObject [("color",valueOf source "color")] (Just q)
      linkObjects source target True
      pure []
    Trim targets -> do
      os <- resolveTargets targets; w <- gets currentWorld
      forM_ os (requirePlaced "Object is unplaced")
      replaceWith ["pattern"] [Ports.setPorts (filter (`notElem` Graph.unmatchedPorts w o) (Ports.openPorts o)) o | o <- os]
      pure (emptyMessage os)
    BuildConnection a b color -> buildConnection a b color
    Create attrs site -> do p <- traverse resolveSquare site; newObject [(a,Just v) | (a,v) <- attrs] p; pure []
    DeleteAll -> modify (\s -> s {currentWorld=World []}) >> pure []
    Delete targets -> do
      os <- resolveTargets targets; let ids = map idOf os
      modify (\s -> s {currentWorld=World (filter ((`notElem` ids) . idOf) (objectsOf (currentWorld s)))})
      pure (emptyMessage os)
    SetAttribute targets a v -> do os <- resolveTargets targets; replaceWith [a] (map (setFields [(a,v)]) os); pure (emptyMessage os)
    SetAppearance targets attrs -> do os <- resolveTargets targets; replaceWith ["appearance"] (map (setFields attrs) os); pure (emptyMessage os)
    Unplace targets -> do os <- resolveTargets targets; replaceWith ["position"] [o {positionOf=Nothing} | o <- os]; pure (emptyMessage os)
    Move r square -> do o <- resolve r; p <- resolveSquare square; moveObjects [(o,p)]; pure []
    ExchangePositions a b -> do
      l <- resolve a; r <- resolve b
      when (idOf l /= idOf r) (replaceWith ["position"] [l {positionOf=positionOf r},r {positionOf=positionOf l}])
      pure []
    Step r d -> do o <- resolve r; p <- requirePlaced "Object is unplaced" o; q <- checkedPosition (addInteger p (offset d)); moveObjects [(o,q)]; pure []
    MoveNextTo a b -> do
      o <- resolve a; target <- resolve b; p <- requirePlaced "Reference object is unplaced" target
      world <- gets currentWorld
      let free = [q | d <- [North,East,South,West], let (x,y) = addInteger p (offset d), x>=0,x<8,y>=0,y<8,
                     let q=(fromInteger x,fromInteger y), all ((/= Just q) . positionOf) (objectsOf world)]
      q <- case free of
        [] -> throwError (Blocked "No free squares")
        [one] -> pure one
        _ -> do
          choices <- gets providedChoices
          case choices of
            SquareChoice chosen:rest | chosen `elem` free -> modify (\s -> s {providedChoices=rest}) >> pure chosen
            _ -> throwError (ChooseSquares free)
      moveObjects [(o,q)]; pure []
    CopyComponent mode a source dest -> do
      l <- resolve source; r <- resolve dest
      when (idOf l /= idOf r) $ do
        let left = componentOf domain a l; right = componentOf domain a r
        replaceWith [a] $ case mode of
          Copy -> [setFields left r]
          Transfer -> [setFields [(name,Nothing) | (name,_) <- left] l,setFields left r]
          Exchange -> [setFields right l,setFields left r]
      pure []
    Clone r site -> do source <- resolve r; p <- traverse resolveSquare site; newObject (appearanceOfWith domain source) p; pure []
    Shift c delta -> do
      os <- resolveCollection c
      pairs <- forM os $ \o -> do p <- requirePlaced "Object is unplaced" o; q <- checkedPosition (addInteger p delta); pure (o,q)
      moveObjects pairs; pure (emptyMessage os)
    Rearrange mappings -> do
      os <- mapM (resolve . fst) mappings >>= distinct
      ps <- mapM (resolveSquare . snd) mappings
      unless (length ps == length (nub ps)) (throwError (Blocked "Duplicate destinations"))
      moveObjects (zip os ps); pure []
    Permute mappings -> do
      sources <- mapM (resolve . fst) mappings >>= distinct
      dests <- mapM (resolve . snd) mappings >>= distinct
      permute sources dests; pure []
    Transformation positions c t ((x,y),(a,b)) -> do
      os <- resolveCollection c
      when (null os) (throwError (Blocked "No selected objects"))
      ps <- mapM (requirePlaced "Object is unplaced") os
      qs <- mapM (transform t (toInteger x+toInteger a,toInteger y+toInteger b)) ps
      if positions then moveObjects (zip os qs) else do
        unless (sortOn id ps == sortOn id qs) (throwError (Blocked "Appearance transformation requires the same occupied square set"))
        let dests = [o | q <- qs, o <- os, positionOf o == Just q]
        permute os dests
      pure []
  where
    permute sources dests = do
      unless (sortOn id (map idOf sources) == sortOn id (map idOf dests)) (throwError (Blocked "Appearance permutation requires identical source and destination sets"))
      domain <- gets activeDomain
      replaceWith ["appearance"] [setFields (appearanceOfWith domain source) dest | (source,dest) <- zip sources dests]
-- Doubled coordinates avoid floating point, rounding and half-cell pivot errors.
transform :: Transform -> (Integer,Integer) -> Position -> Eval Position
transform transformation (cx,cy) (x,y) = do
  let px=2*toInteger x; py=2*toInteger y
      (a,b) = case transformation of
        Rotate Clockwise -> (cx+py-cy,cy-px+cx)
        Rotate HalfTurn -> (2*cx-px,2*cy-py)
        Rotate Counterclockwise -> (cx-py+cy,cy+px-cx)
        Reflect True -> (2*cx-px,py)
        Reflect False -> (px,2*cy-py)
  when (odd a || odd b) (throwError (Blocked "Transformation does not land on square centers"))
  checkedPosition (a `div` 2,b `div` 2)

evalQuestion :: Question -> Eval [String]
evalQuestion question = case question of
  CheckIt c -> do
    referent <- resolvePronoun (conditionKinds c)
    case referent of
      D.ObjectReferent identifier -> evalQuestion (CheckObject (Ident (idToInt identifier)) c)
      D.SquareReferent p -> evalQuestion (CheckSquare (Cell p) c)
  CheckGraph expression c -> do
    (view,_) <- evalGraph expression
    predicate <- graphPredicate c
    pure [graphMembers view, answer (predicate view)]
  CheckLink a b scope c -> do
    left <- resolve a; right <- resolve b; (view,_) <- currentView scope
    unless (Analysis.contains view left && any ((== idOf right) . idOf) (Graph.neighbors view left))
      (throwError (Blocked "No reciprocal link between the objects in this graph"))
    predicate <- linkPredicate view left right c
    pure ([graphMembers view | isJust scope] ++ [answer predicate])
  GraphNumber name expression -> do
    (view,_) <- evalGraph expression
    pure [graphMembers view, show (case name of "components" -> length (Graph.components view); "links" -> length (Analysis.links view); _ -> length (objectsOf view))]
  NetworkQuery name a b scope -> do
    source <- resolve a
    target <- traverse resolve b
    (view,_) <- currentView scope
    requirePlaced "Source object is unplaced" source
    forM_ target (requirePlaced "Target object is unplaced")
    case (name,target) of
      ("degree",_) -> do
        unless (Analysis.contains view source) (throwError (Blocked "Object is outside the selected graph"))
        pure [show (length (Graph.neighbors view source))]
      (_,Just other) -> pure [case Analysis.shortestPath view source other of
        Nothing -> "no path"
        Just path -> if name == "distance" then show (length path-1) else "[" ++ intercalate ", " (map pretty path) ++ "]"]
      _ -> throwError (Blocked "Missing path target")
  Exists n -> do
    w <- gets currentWorld
    case objectAtId w n of Nothing -> pure ["false"]; Just o -> record o [] >> pure ["true"]
  CheckObject r c -> do o <- resolve r; p <- objectPredicate c; associatedWith o c >>= record o; pure [answer (p o)]
  CheckSquare square c -> do
    p <- resolveSquare square
    predicate <- squarePredicate c
    recordSquare p (squareFacts c)
    pure [answer (predicate p)]
  Query a r -> do o <- resolve r; domain <- gets activeDomain; record o (propertiesOf o a); pure [fromMaybe "none" (valueOfWith domain o a)]
  Occupant square -> do p <- resolveSquare square; w <- gets currentWorld
                        pure [case filter ((== Just p) . positionOf) (objectsOf w) of [] -> "none"; o:_ -> "#" ++ show (idToInt (idOf o))]
  Select object c -> aggregate object c Nothing (\xs _ -> "[" ++ intercalate ", " xs ++ "]")
  Count object c -> aggregate object c Nothing (\xs _ -> show (length xs))
  Quantified every object before after -> aggregate object before (Just after) $ \selected results ->
    answer ((if every then all else any) fst results, nub (concatMap snd results)) ++
    (if null selected then " — no matching " ++ (if object then "objects" else "squares") else "")
  where
    answer (b,notes) = (if b then "true" else "false") ++ (if null notes then "" else " — " ++ intercalate "; " notes)
    aggregate object c after render = if object then do
      first <- objectPredicate c
      second <- traverse objectPredicate after
      os <- sortOn idOf . objectsOf <$> gets currentWorld
      let selected = filter (fst . first) os
      pure [render ["#" ++ show (idToInt (idOf o)) | o <- selected] (maybe [] (\p -> map p selected) second)]
      else do
        first <- squarePredicate c
        second <- traverse squarePredicate after
        let selected = filter (fst . first) [(x,y) | y <- [0..7], x <- [0..7]]
        pure [render (map prettyPosition selected) (maybe [] (\p -> map p selected) second)]

changesBetweenWith :: Domain -> World -> World -> [Change]
changesBetweenWith domain before after = concatMap change identifiers
  where
    identifiers = sortOn id (nub (map (idToInt . idOf) (objectsOf before ++ objectsOf after)))
    change n = case (objectAtId before n, objectAtId after n) of
      (Nothing,Just o) -> [Change n "created" ("Created #" ++ show n ++ ": " ++ appearanceText (appearanceOfWith domain o) ++ "; " ++ placement o)]
      (Just _,Nothing) -> [Change n "deleted" ("Deleted #" ++ show n)]
      (Just old,Just new) ->
        [Change n "position" ("#" ++ show n ++ ": " ++ placement old ++ " -> " ++ placement new) | positionOf old /= positionOf new] ++
        [Change n "appearance" ("#" ++ show n ++ ": " ++ a ++ " " ++ fromMaybe "none" (valueOfWith domain old a) ++ " -> " ++ fromMaybe "none" (valueOfWith domain new a))
          | a <- (if isNetwork domain then ["color","pattern"] else appearanceAttributes), valueOfWith domain old a /= valueOfWith domain new a]
      _ -> []
    placement = maybe "unplaced" (("on " ++) . prettyPosition) . positionOf

runEntryWith :: Domain -> World -> D.SalienceRanking -> Int -> Entry -> [Choice] -> Int -> Outcome
runEntryWith domain world ranking next entry choices skip = walk initial 0 [] [] sentences
  where
    initial = EvalState domain world (D.beginEntry ranking) next choices [] Nothing []
    batch = case entry of Batch _ -> True; _ -> False
    sentences = case entry of Sequence xs -> xs; Batch cs -> map Command cs; Undo -> []
    format sentence lines' = sentenceText sentence ++ "\n  " ++ intercalate "\n  " lines'
    effectiveSkip = if batch then 0 else skip
    feedback blocks = intercalate "\n" (drop effectiveSkip blocks)
    output state blocks changes pause failed =
      let provisional = batch && (failed || isJust pause)
          prefix = if batch && failed then "Atomic batch failed; nothing was applied.\n"
                   else if batch && isJust pause then "Provisional batch; nothing was applied.\n" else ""
      in Outcome (if provisional then world else currentWorld state) (if provisional then ranking else currentRanking state)
          (freshId state) (prefix ++ feedback blocks) failed (if provisional then [] else concat (drop effectiveSkip changes)) pause
          (if batch && isJust pause then Just (currentWorld state) else Nothing)
    walk state _ blocks changes [] = output state blocks changes Nothing False
    walk state completed blocks changes (sentence:rest) =
      let action = case sentence of Command c -> evalCommand c; Question q -> evalQuestion q
          (result,attempted) = runState (runExceptT action) state {mentions=[],graphContext=Nothing,groundedConditions=[]}
          initialWorld = currentWorld state
      in case result of
        Right answers ->
          let updated = currentWorld attempted
              changes' = changesBetweenWith domain initialWorld updated
              grouped = Map.toList (Map.fromListWith (++) (mentions attempted))
              mentioned = map fst grouped
              label (D.ObjectReferent identifier) = pretty identifier
              label (D.SquareReferent p) = "square " ++ prettyPosition p
              resolved = ["Resolved " ++ intercalate ", " (map label mentioned) | not (null mentioned)]
              details = answers ++ map changeDetail changes'
              lines' = resolved ++ if null details then ["No change"] else details
              nextState = attempted {currentRanking=D.mentionManyWith (referentExists domain) (referentTruth domain) updated grouped (currentRanking state),mentions=[]}
          in walk nextState (completed+1) (blocks ++ [format sentence lines']) (changes ++ [changes']) rest
        Left (Blocked message) ->
          let stopped = state {freshId=freshId attempted,currentRanking=D.advanceUtterance (currentRanking state)}
              suffix = ["Not executed: " ++ show (length rest) ++ " remaining sentences" | not (null rest)]
          in output stopped (blocks ++ [format sentence (message:suffix)]) changes Nothing True
        Left failure ->
          let (ids,ps) = case failure of
                ChooseObjects ns -> (ns,[])
                ChooseSquares positions -> ([],positions)
                ChooseReferents candidates -> ([idToInt n | D.ObjectReferent n <- candidates],[p | D.SquareReferent p <- candidates])
              paused = state {freshId=freshId attempted}
              message = if not (null ids) && not (null ps) then "Which referent: object or square?" else if null ps then "Which object?" else "Which square?"
          in output paused (blocks ++ [format sentence [message]]) changes
               (Just (completed,sentenceText sentence,ids,ps)) False

-- Editor commands explicitly create on empty squares for attribute/pattern edits.
editWorldWith :: Domain -> Int -> World -> Editor.EditorAction -> (World,Int,String)
editWorldWith domain next world action = case action of
  _ | Just p <- createsAt action
    , inDomainBounds domain p && all ((/= Just p) . positionOf) (objectsOf world) ->
        if next >= maxBound then (world,next,"Identifier space exhausted") else
        let o = Object (Id next) Map.empty (Just p)
            seed = World (o:objectsOf world)
            (updated,message) = Editor.evaluateEditorActionWith domain seed action
        in (updated,next+1,"Created #" ++ show next ++ "; " ++ message)
  _ -> let (updated,message) = Editor.evaluateEditorActionWith domain world action in (updated,next,message)

  where
    createsAt (Editor.ApplyProperty p _) = Just p
    createsAt (Editor.ReplaceAttributes p _ _) = Just p
    createsAt _ = Nothing

-- Domain bundles use the declared stored attributes. Pattern is a four-port bundle,
-- never a second stored attribute or an absent shape.
appearanceOfWith :: Domain -> Object -> [(String,Maybe String)]
appearanceOfWith domain o = [(a,valueOf o a) | a <- appearanceAttributesFor domain]
appearanceOfWithNetwork :: Object -> [(String,Maybe String)]
appearanceOfWithNetwork o = [(a,valueOf o a) | a <- "color":portNames]
valueOfWith :: Domain -> Object -> String -> Maybe String
valueOfWith domain o "appearance" = Just (appearanceText (appearanceOfWith domain o))
valueOfWith _ o a = valueOf o a
patternOf :: Object -> String
patternOf o = [if Ports.hasPort o p then c else '-' | (p,c) <- zip Ports.ports "nesw"]
validPattern :: String -> Bool
validPattern p = length p == 4 && and [c == '-' || c == name | (c,name) <- zip p "nesw"]
expandFields :: [(String,Maybe String)] -> [(String,Maybe String)]
expandFields = concatMap expand
  where
    expand ("pattern",value) = [(name,if c == '-' then Nothing else Just name) | (name,c) <- zip portNames (fromMaybe "----" value)]
    expand field = [field]
setPattern :: String -> Object -> Object
setPattern pattern = setFields (expandFields [("pattern",Just pattern)])
transformPorts :: Transform -> Object -> Object
transformPorts operation o = Ports.setPorts (map convert (Ports.openPorts o)) o
  where
    convert p = case operation of
      Rotate angle -> toEnum ((fromEnum p + case angle of Clockwise -> 1; HalfTurn -> 2; Counterclockwise -> 3) `mod` 4)
      Reflect vertical -> if (vertical && p `elem` [Net.East,Net.West]) || (not vertical && p `elem` [Net.North,Net.South]) then Ports.opposite p else p
linkObjects :: Object -> Object -> Bool -> Eval ()
linkObjects a b linked = do
  p <- requirePlaced "Source object is unplaced" a
  q <- requirePlaced "Target object is unplaced" b
  case [direction | direction <- Ports.ports, Ports.shiftPort direction p == q] of
    [direction] -> do
      let adjust o d = Ports.setPorts (filter (\port -> port /= d || linked) (nub (Ports.openPorts o ++ [d | linked]))) o
      replaceWith ["pattern"] [adjust a direction,adjust b (Ports.opposite direction)]
    _ -> throwError (Blocked "Objects are not orthogonal neighbors")
graphMembers :: World -> String
graphMembers (World objects) = "Graph members: [" ++ intercalate ", "
  [pretty (idOf o) | o <- sortOn idOf objects] ++ "]"

buildConnection :: Endpoint -> Endpoint -> Maybe String -> Eval [String]
buildConnection a b hue = do
  from <- endpoint a
  to <- endpoint b
  explicitMentions <- gets mentions
  w <- gets currentWorld
  path <- maybe (throwError (Blocked "No path")) pure (Pathfinding.shortestConnectionPathOpeningEndpoints w from to)
  let segments = zip3 path (Nothing:map Just path) (map Just (drop 1 path) ++ [Nothing])
  forM_ segments $ \(p,previous,next) -> do
    let required = [d | d <- Ports.ports, Just neighbor <- [previous,next], Ports.shiftPort d p == neighbor]
        colors = [("color",Just color) | Just color <- [hue]]
    current <- gets currentWorld
    case Graph.atPosition current p of
      Nothing -> do
        newObject (colors ++ [(Net.portName d,Just (Net.portName d)) | d <- required]) (Just p)
        pure ()
      Just o -> do
        let opened = if p == from || p == to then Ports.setPorts (nub (Ports.openPorts o ++ required)) o else o
        replace [setFields colors opened]
  final <- gets currentWorld
  routeMentions <- gets mentions
  forM_ [from,to] $ \p -> case Graph.atPosition final p of
    Just o | any ((== D.ObjectReferent (idOf o)) . fst) routeMentions -> record o ([P p] ++ [property ("color",color) | Just color <- [hue]])
    _ -> pure ()
  -- Intermediate creations are implementation details, not discourse antecedents.
  modify (\state -> state {mentions=[mention | mention@(identifier,_) <- mentions state,
    case identifier of D.SquareReferent _ -> True; D.ObjectReferent n -> any ((== identifier) . fst) explicitMentions || any (\p -> maybe False ((== n) . idOf) (Graph.atPosition final p)) [from,to]]})
  pure ["Connected " ++ prettyPosition from ++ " to " ++ prettyPosition to ++ " (" ++ show (length path-1) ++ " steps)"]
  where
    endpoint EndpointIt = do
      referent <- resolvePronoun [ObjectKind,SquareKind]
      case referent of
        D.ObjectReferent identifier -> endpoint (ObjectEndpoint (Ident (idToInt identifier)))
        D.SquareReferent p -> resolveSquare (Cell p)
    endpoint (SquareEndpoint square) = resolveSquare square
    endpoint (ObjectEndpoint reference) = resolve reference >>= requirePlaced "Endpoint object is unplaced"

withContext :: Maybe (World,GraphExpr) -> Eval a -> Eval a
withContext context action = do
  previous <- gets graphContext
  modify (\s -> s {graphContext=context})
  result <- action
  modify (\s -> s {graphContext=previous})
  pure result
currentView :: Maybe GraphExpr -> Eval (World,GraphExpr)
currentView (Just expression) = evalGraph expression
currentView Nothing = do
  context <- gets graphContext
  maybe (evalGraph NetworkGraph) pure context

evalGraph :: GraphExpr -> Eval (World,GraphExpr)
evalGraph NetworkGraph = do w <- gets currentWorld; pure (Analysis.placed w,NetworkGraph)
evalGraph (Component reference source) = do
  o <- withContext Nothing (resolve reference)
  requirePlaced "Component seed is unplaced" o
  (view,grounded) <- maybe (evalGraph NetworkGraph) evalGraph source
  unless (Analysis.contains view o) (throwError (Blocked "Component seed is outside the selected graph"))
  pure (World (Graph.component view o),Component (Ident (idToInt (idOf o))) (Just grounded))
evalGraph (Induced source condition) = do
  (view,grounded) <- evalGraph source
  predicate <- withContext (Just (view,grounded)) (objectPredicate condition)
  selector <- groundCondition condition
  pure (World (filter (fst . predicate) (objectsOf view)),Induced grounded selector)
graphPredicate :: Condition -> Eval (Predicate World)
graphPredicate condition = case condition of
  GraphProperty name color -> pure (plain (Analysis.graphProperty name color))
  Not c -> do p <- graphPredicate c; pure (\w -> let (b,notes)=p w in (not b,notes))
  And a b -> combine (&&) <$> graphPredicate a <*> graphPredicate b
  Or a b -> combine (||) <$> graphPredicate a <*> graphPredicate b
  _ -> throwError (Blocked "Invalid graph predicate")
linkPredicate :: World -> Object -> Object -> Condition -> Eval (Bool,[String])
linkPredicate view a b c = case c of
  GraphProperty "bridge" _ -> pure (Analysis.isBridge view a b,[])
  Not p -> do (truth,notes) <- linkPredicate view a b p; pure (not truth,notes)
  And p q -> do (x,n) <- linkPredicate view a b p; (y,m) <- linkPredicate view a b q; pure (x && y,nub (n++m))
  Or p q -> do (x,n) <- linkPredicate view a b p; (y,m) <- linkPredicate view a b q; pure (x || y,nub (n++m))
  _ -> throwError (Blocked "Invalid link predicate")

-- Contextual facts contain only grounded identities and typed, immutable syntax.
-- The graph is recomputed against the current world when salience is purged.
contextFact :: Condition -> Property
contextFact condition = Defined ("v2:" ++ show condition)
remember :: Condition -> Condition -> Eval ()
remember before after = modify (\s -> s {groundedConditions=(before,after):groundedConditions s})
groundCondition :: Condition -> Eval Condition
groundCondition condition = do
  known <- gets groundedConditions
  case lookup condition known of
    Just grounded -> pure grounded
    Nothing -> case condition of
      Not c -> Not <$> groundCondition c
      And a b -> And <$> groundCondition a <*> groundCondition b
      Or a b -> Or <$> groundCondition a <*> groundCondition b
      OnSquare c -> OnSquare <$> groundCondition c
      _ -> pure condition
evidenceOptions :: Condition -> [[Property]]
evidenceOptions condition = case condition of
  ValueIs a v -> [[property (a,v)]]
  PositionIs p -> [[P p]]
  And a b -> [left ++ right | left <- evidenceOptions a, right <- evidenceOptions b]
  Or a b -> evidenceOptions a ++ evidenceOptions b
  _ -> [[contextFact condition]]
associatedWith :: Object -> Condition -> Eval [Property]
associatedWith o condition = do
  domain <- gets activeDomain
  grounded <- groundCondition condition
  pure $ if isNetwork domain then nub (associated o condition ++ facts grounded) else associated o condition
  where
    facts c = case c of
      And a b -> facts a ++ facts b ++ [contextFact c]
      Or a b -> facts a ++ facts b ++ [contextFact c]
      ValueIs a v -> [property (a,v)]
      PositionIs p -> [P p]
      _ -> [contextFact c]
chooseAnaphoric :: (Object -> Bool) -> [[Property]] -> World -> D.SalienceRanking -> Eval Object
chooseAnaphoric predicate alternatives w ranking = do
  domain <- gets activeDomain
  let clean = D.objectRanking (purgeRanking domain w ranking)
      candidates = [o | o <- objectsOf w, predicate o]
      costs o = [(sum scores,length properties)
        | properties <- alternatives
        , let matches property = [10*entry+utterance | ((entry,utterance),identifier,mentioned) <- clean,
                identifier == idOf o, property `elem` mentioned]
        , all (not . null . matches) properties
        , let scores = map (minimum . matches) properties]
      ranked = sortOn (fst . snd) [(o,minimum (costs o)) | o <- candidates, not (null (costs o))]
      selected = case ranked of
        [] -> candidates
        (_, (best,_)):_ -> [o | (o,(score,width)) <- ranked, score-best < width+1]
  case selected of
    [] -> throwError (Blocked "No matching object")
    [o] -> pure o
    os -> selectChoice (map (idToInt . idOf) os) >>= getObject
truthFor :: Domain -> World -> Object -> Property -> Bool
truthFor domain w o fact = case fact of
  Defined source | "v2:" `isPrefixOf` source -> case readMaybe (drop 3 source) of
    Nothing -> False
    Just condition -> case fst (runState (runExceptT (objectPredicate condition)) (EvalState domain w [] 0 [] [] Nothing [])) of
      Right predicate -> fst (predicate o)
      Left _ -> False
  _ -> holdsProperty o fact
purgeRanking :: Domain -> World -> D.SalienceRanking -> D.SalienceRanking
purgeRanking domain = D.purgeWith (referentExists domain) (referentTruth domain)
referentExists :: Domain -> World -> D.Referent -> Bool
referentExists _ w (D.ObjectReferent identifier) = isJust (objectAtId w (idToInt identifier))
referentExists domain _ (D.SquareReferent p) = inDomainBounds domain p
referentTruth :: Domain -> World -> D.Referent -> Property -> Bool
referentTruth domain w (D.ObjectReferent identifier) fact = maybe False (\o -> truthFor domain w o fact) (objectAtId w (idToInt identifier))
referentTruth domain w (D.SquareReferent p) (Defined source)
  | "square:" `isPrefixOf` source = case readMaybe (drop 7 source) of
      Just c -> case fst (runState (runExceptT (squarePredicate c)) (EvalState domain w [] 0 [] [] Nothing [])) of
        Right predicate -> fst (predicate p)
        Left _ -> False
      Nothing -> False
referentTruth _ _ (D.SquareReferent _) _ = False
squareFacts :: Condition -> [Property]
squareFacts c = nub (squareFact c : case c of
  And a b -> squareFacts a ++ squareFacts b
  Or a b -> squareFacts a ++ squareFacts b
  _ -> [])

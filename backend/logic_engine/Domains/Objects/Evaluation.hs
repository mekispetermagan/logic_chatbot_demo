module Domains.Objects.Evaluation where

import Data.List (nub, intercalate)
import Domain
import Domains.Objects.Definition (objectsDomain)
import Ontology
import DomainLibrary
import Layer2Syntax
import Discourse (holds, descriptorsOf, subjectsOf)
import AtomicPerformative
import AtomicPropertyQuery
import AtomicEvaluation
import AtomicSentence
import ReferenceResolution (inBoundsWith)
import Pretty

-- Semantic results remain independent of HTTP, persistence, and presentation.


adjacent :: Position -> Position -> Bool
adjacent (x,y) (a,b) = abs (x-a) + abs (y-b) == 1

neighborsWith :: Domain -> Position -> [Position]
neighborsWith domain (x,y) = filter (inBoundsWith domain) [(x,y+1),(x,y-1),(x-1,y),(x+1,y)]

atEdgeWith :: Domain -> Object -> Bool
atEdgeWith domain object = maybe False (\(x,y) -> x == 0 || x == boardWidth domain - 1 || y == 0 || y == boardHeight domain - 1) (positionOf object)

inCornerWith :: Domain -> Object -> Bool
inCornerWith domain object = maybe False (\(x,y) -> x `elem` [0,boardWidth domain - 1] && y `elem` [0,boardHeight domain - 1]) (positionOf object)

attributeValue :: Attribute -> Object -> Maybe QueryAnswer
attributeValue attribute object = case attribute of
  Stored attribute -> PropertyValue . AttributeValue attribute <$> attributeOf attribute object
  PositionAttribute -> PropertyValue . P <$> positionOf object
  RowAttribute -> RowValue . snd <$> positionOf object
  ColumnAttribute -> ColumnValue . fst <$> positionOf object

storedAttribute :: RemovableAttribute -> Attribute
storedAttribute (RemoveStored attribute) = Stored attribute
storedAttribute RemoveSquare = PositionAttribute

shift :: Direction -> Position -> Position
shift Up (x,y) = (x,y+1)
shift Down (x,y) = (x,y-1)
shift Leftward (x,y) = (x-1,y)
shift Rightward (x,y) = (x+1,y)

evaluateDerivedWith :: Domain -> World -> [Identifier] -> Sentence -> Maybe Position -> Maybe DerivedResult
evaluateDerivedWith domain world@(World objects) identifiers sentence chosen = case sentence of
  StepMove _ direction -> unary $ \object -> case positionOf object of
    Nothing -> unchanged "Object is unplaced"
    Just position -> move object (shift direction position)
  RelativeMove _ direction _ -> binary $ \object target -> case positionOf target of
    Nothing -> unchanged "Reference object is unplaced"
    Just position -> move object (shift direction position)
  NeighborMove _ _ -> binary $ \object target -> case positionOf target of
    Nothing -> unchanged "Reference object is unplaced"
    Just position ->
      let free = [p | p <- (neighborsWith domain) position, all ((/= Just p) . positionOf) objects]
      in case chosen of
        Just p | p `elem` free -> move object p
        Just _ -> unchanged "Square is not available"
        Nothing -> case free of
          [] -> unchanged "No free squares"
          [p] -> move object p
          several -> ChooseSquares several
  CopyAttribute _ attribute _ -> binary $ \object target ->
    let operation = case attributeValue (storedAttribute attribute) target of
          Just (PropertyValue property) -> AP (ById (idOf object)) property
          _ -> RemoveAttribute (ById (idOf object)) attribute
    in perform operation
  SpatialQuestion _ relation _ -> case relation of
    NextTo -> binary $ \object target -> spatialAnswer object (Just target)
    Same _ -> binary $ \object target -> spatialAnswer object (Just target)
    _ -> unary $ \object -> spatialAnswer object Nothing
    where spatialAnswer object target = let (result, explanation) = (spatialTruthWith domain) relation object target
                                        in answer result explanation
  CountObjects predicate -> case predicate of
    Neighboring _ -> unary $ \target -> case positionOf target of
      Nothing -> unchanged "Reference object is unplaced"
      Just position -> count [object | object <- objects, maybe False (adjacent position) (positionOf object)]
    Described properties -> Just (count (filter (\object -> all (holds object) properties) objects))
    AtEdge -> Just (count (filter (atEdgeWith domain) objects))
    InCorner -> Just (count (filter (inCornerWith domain) objects))
  CountSquares occupied -> Just (unchanged (show (if occupied then placed else boardWidth domain * boardHeight domain - placed)))
    where placed = length [() | object <- objects, positionOf object /= Nothing]
  Quantified universal before predicates ->
    let selected = filter (\object -> all (holds object) before) objects
        targetFor subject = lookup subject (zip (subjectsOf sentence) resolved)
        evaluatePredicate object predicate = case predicate of
          PropertyPredicate properties -> (all (holds object) properties, "")
          RelationPredicate relation target -> (spatialTruthWith domain) relation object (target >>= targetFor)
        results object = map (evaluatePredicate object) predicates
        satisfies = all fst . results
        result = (if universal then all else any) satisfies selected
        nullNotes = nub [note | object <- selected, (_, note) <- results object, not (null note)]
        explanation = if null selected then " — no matching objects"
                      else intercalate ";" nullNotes
    in Just (answer result explanation)
  _ -> Nothing
  where
    resolved = [object | identifier <- identifiers, object <- objects, idOf object == identifier]
    unary action = Just $ case resolved of
      [object] -> action object
      _ -> unchanged "Expected one object"
    binary action = Just $ case resolved of
      [object,target] -> action object target
      _ -> unchanged "Expected two objects"
    associations updated =
      [descriptorsOf subject ++ associated object
      | (identifier,subject) <- zip identifiers (subjectsOf sentence)
      , object <- case updated of World os -> filter ((== identifier) . idOf) os]
    associated object = case sentence of
      StepMove _ _ -> positionProperties object
      RelativeMove _ _ _ -> positionProperties object
      NeighborMove _ _ -> positionProperties object
      CopyAttribute _ attribute _ -> valueProperties (storedAttribute attribute) object
      SpatialQuestion _ (Has attribute) _ -> valueProperties (storedAttribute attribute) object
      SpatialQuestion _ (Same attribute) _ -> valueProperties attribute object
      Quantified _ _ predicates -> concat
        [valueProperties attribute object
        | RelationPredicate (Same attribute) (Just target) <- predicates
        , (identifier, subject) <- zip identifiers (subjectsOf sentence)
        , subject == target, identifier == idOf object]
      _ -> []
    positionProperties object = maybe [] ((:[]) . P) (positionOf object)
    valueProperties attribute object = case attributeValue attribute object of
      Just (PropertyValue property) -> [property]
      Just (RowValue _) -> positionProperties object
      Just (ColumnValue _) -> positionProperties object
      _ -> []
    unchanged message = DerivedComplete world [message] (associations world)
    answer result explanation = unchanged ((if result then "true" else "false") ++ explanation)
    count selected = unchanged (show (length selected))
    perform operation =
      let (updated, feedback) = (evaluateAtomicSentenceWith domain) world (Performative operation)
      in DerivedComplete updated [pretty (feedbackAnswer feedback)] (associations updated)
    move object position
      | not ((inBoundsWith domain) position) = unchanged "Outside board"
      | otherwise = perform (AP (ById (idOf object)) (P position))

-- Missing values compare equal, while unplaced objects have no spatial relation.
spatialTruthWith :: Domain -> SpatialCheck -> Object -> Maybe Object -> (Bool, String)
spatialTruthWith domain relation object target = case relation of
  OnBoard -> plain (positionOf object /= Nothing)
  Has attribute -> plain (attributeValue (storedAttribute attribute) object /= Nothing)
  Edge -> plain ((atEdgeWith domain) object)
  Corner -> plain ((inCornerWith domain) object)
  NextTo -> plain $ case (positionOf object, target >>= positionOf) of
    (Just p, Just q) -> adjacent p q
    _ -> False
  Same attribute -> case target of
    Nothing -> plain False
    Just other ->
      let left = attributeValue attribute object
          right = attributeValue attribute other
          explanation = if left == Nothing && right == Nothing
            then " — both lack " ++ (if attribute == PositionAttribute then "a square" else pretty attribute)
            else ""
      in (left == right, explanation)
  where plain result = (result, "")

-- Current-domain convenience entry points.
neighbors :: Position -> [Position]
neighbors = neighborsWith objectsDomain
atEdge :: Object -> Bool
atEdge = atEdgeWith objectsDomain
inCorner :: Object -> Bool
inCorner = inCornerWith objectsDomain
evaluateDerived :: World -> [Identifier] -> Sentence -> Maybe Position -> Maybe DerivedResult
evaluateDerived = evaluateDerivedWith objectsDomain
spatialTruth :: SpatialCheck -> Object -> Maybe Object -> (Bool, String)
spatialTruth = spatialTruthWith objectsDomain

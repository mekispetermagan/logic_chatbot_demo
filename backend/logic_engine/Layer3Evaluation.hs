module Layer3Evaluation where

import Ontology
import Layer2Syntax
import Discourse (holds, descriptorsOf, subjectsOf)
import AtomicPerformative
import AtomicPropertyQuery
import AtomicEvaluation
import AtomicSentence
import ReferenceResolution (inBounds)
import Pretty

-- Semantic results remain independent of HTTP, persistence, and presentation.
data DerivedResult = DerivedComplete World [String] [[Property]] | ChooseSquares [Position]

adjacent :: Position -> Position -> Bool
adjacent (x,y) (a,b) = abs (x-a) + abs (y-b) == 1

neighbors :: Position -> [Position]
neighbors (x,y) = filter inBounds [(x,y+1),(x,y-1),(x-1,y),(x+1,y)]

atEdge :: Object -> Bool
atEdge object = maybe False (\(x,y) -> x == 0 || x == 7 || y == 0 || y == 7) (positionOf object)

inCorner :: Object -> Bool
inCorner object = maybe False (\(x,y) -> x `elem` [0,7] && y `elem` [0,7]) (positionOf object)

attributeValue :: Attribute -> Object -> Maybe QueryAnswer
attributeValue attribute object = case attribute of
  ColorAttribute -> PropertyValue . C <$> colorOf object
  SizeAttribute -> PropertyValue . S <$> sizeOf object
  ShapeAttribute -> PropertyValue . Sh <$> shapeOf object
  PositionAttribute -> PropertyValue . P <$> positionOf object
  RowAttribute -> RowValue . snd <$> positionOf object
  ColumnAttribute -> ColumnValue . fst <$> positionOf object

storedAttribute :: RemovableAttribute -> Attribute
storedAttribute RemoveColor = ColorAttribute
storedAttribute RemoveSize = SizeAttribute
storedAttribute RemoveShape = ShapeAttribute
storedAttribute RemoveSquare = PositionAttribute

shift :: Direction -> Position -> Position
shift Up (x,y) = (x,y+1)
shift Down (x,y) = (x,y-1)
shift Leftward (x,y) = (x-1,y)
shift Rightward (x,y) = (x+1,y)

evaluateDerived :: World -> [Identifier] -> Sentence -> Maybe Position -> Maybe DerivedResult
evaluateDerived world@(World objects) identifiers sentence chosen = case sentence of
  StepMove _ direction -> unary $ \object -> case positionOf object of
    Nothing -> unchanged "Object is unplaced"
    Just position -> move object (shift direction position)
  RelativeMove _ direction _ -> binary $ \object target -> case positionOf target of
    Nothing -> unchanged "Reference object is unplaced"
    Just position -> move object (shift direction position)
  NeighborMove _ _ -> binary $ \object target -> case positionOf target of
    Nothing -> unchanged "Reference object is unplaced"
    Just position ->
      let free = [p | p <- neighbors position, all ((/= Just p) . positionOf) objects]
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
    NextTo -> binary $ \object target -> answer (case (positionOf object, positionOf target) of
      (Just p, Just q) -> adjacent p q
      _ -> False) ""
    Same attribute -> binary $ \object target ->
      let left = attributeValue attribute object
          right = attributeValue attribute target
          explanation = if left == Nothing && right == Nothing
            then " — both lack " ++ (if attribute == PositionAttribute then "a square" else pretty attribute)
            else ""
      in answer (left == right) explanation
    OnBoard -> unary $ \object -> answer (positionOf object /= Nothing) ""
    Has attribute -> unary $ \object -> answer (attributeValue (storedAttribute attribute) object /= Nothing) ""
    Edge -> unary $ \object -> answer (atEdge object) ""
    Corner -> unary $ \object -> answer (inCorner object) ""
  CountObjects predicate -> case predicate of
    Neighboring _ -> unary $ \target -> case positionOf target of
      Nothing -> unchanged "Reference object is unplaced"
      Just position -> count [object | object <- objects, maybe False (adjacent position) (positionOf object)]
    Described properties -> Just (count (filter (\object -> all (holds object) properties) objects))
    AtEdge -> Just (count (filter atEdge objects))
    InCorner -> Just (count (filter inCorner objects))
  CountSquares occupied -> Just (unchanged (show (if occupied then placed else 64 - placed)))
    where placed = length [() | object <- objects, positionOf object /= Nothing]
  Quantified universal before after ->
    let selected = filter (\object -> all (holds object) before) objects
        satisfies object = all (holds object) after
        result = (if universal then all else any) satisfies selected
    in Just (answer result (if null selected then " — no matching objects" else ""))
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
      let (updated, feedback) = evaluateAtomicSentence world (Performative operation)
      in DerivedComplete updated [pretty (feedbackAnswer feedback)] (associations updated)
    move object position
      | not (inBounds position) = unchanged "Outside board"
      | otherwise = perform (AP (ById (idOf object)) (P position))


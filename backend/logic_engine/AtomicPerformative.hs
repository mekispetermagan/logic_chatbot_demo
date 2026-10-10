module AtomicPerformative where

import Ontology
import Pretty
import ReferenceResolution
import Result

data AtomicPerformative = AP
                        { subjectPart :: ObjectReference
                        , propPart    :: Property
                        }
                        | RemoveAttribute ObjectReference RemovableAttribute
                        | Remove ObjectReference
                        | Swap ObjectReference ObjectReference
                        | Delete ObjectReference
                        deriving (Eq, Show)

-- Only whole stored attributes can be cleared; row and column are derived.
data RemovableAttribute = RemoveColor | RemoveSize | RemoveShape | RemoveSquare
  deriving (Eq, Show)

instance PrettyShow RemovableAttribute where
  pretty RemoveColor = "color"
  pretty RemoveSize = "size"
  pretty RemoveShape = "shape"
  pretty RemoveSquare = "square"

instance PrettyShow AtomicPerformative where
  pretty (AP identifier property) =
    pretty identifier ++ " " ++ pretty property ++ "."
  pretty (RemoveAttribute reference attribute) = pretty reference ++ " remove " ++ pretty attribute ++ "."
  pretty (Remove reference) = "remove " ++ pretty reference ++ "."
  pretty (Swap first second) = "swap " ++ pretty first ++ " and " ++ pretty second ++ "."
  pretty (Delete reference) = "delete " ++ pretty reference ++ "."

updateObjectWith :: Object -> Property -> Object
updateObjectWith (Object i mc ms msh mp) (C c)    = (Object i (Just c) ms msh mp)
updateObjectWith (Object i mc ms msh mp) (S s)    = (Object i mc (Just s) msh mp)
updateObjectWith (Object i mc ms msh mp) (Sh sh)  = (Object i mc ms (Just sh) mp)
updateObjectWith (Object i mc ms msh mp) (P p)    = (Object i mc ms msh (Just p))

data UpdateChange = ObjectCreated Identifier Property
                  | PropertyChanged Identifier (Maybe Property) Property
                  | PropertyCleared Identifier Property
                  | ObjectRemoved Identifier Position
                  | ObjectsSwapped Identifier Identifier
                  | ObjectDeleted Identifier
                  | NoChange
                  | UpdateBlocked (Maybe Identifier) String
                  deriving (Eq, Show)

instance PrettyShow UpdateChange where
  pretty (ObjectCreated identifier property) = "Created " ++ pretty identifier ++ ": " ++ pretty property
  pretty (PropertyChanged identifier previous property) =
    pretty identifier ++ ": " ++ maybe "none" pretty previous ++ " -> " ++ pretty property
  pretty (PropertyCleared identifier property) = pretty identifier ++ ": " ++ pretty property ++ " -> none"
  pretty (ObjectRemoved identifier position) = pretty identifier ++ ": on " ++ prettyPosition position ++ " -> unplaced"
  pretty (ObjectsSwapped first second) = "Swapped " ++ pretty first ++ " and " ++ pretty second
  pretty (ObjectDeleted identifier) = "Deleted " ++ pretty identifier
  pretty NoChange = "No change"
  pretty (UpdateBlocked Nothing message) = message
  pretty (UpdateBlocked (Just identifier) message) = "Created " ++ pretty identifier ++ "; " ++ message

evaluateAtomicPerformative :: World -> AtomicPerformative -> (World, Result UpdateChange)
evaluateAtomicPerformative world (AP reference property) =
  case resolvePerformativeReference world reference of
    Message message -> (world, Message message)
    Result (resolved@(World objects), object, created) ->
      let identifier = idOf object
          blocked message = (resolved, Result (UpdateBlocked
            (if created then Just identifier else Nothing) message))
          apply =
            let updatedObject = updateObjectWith object property
                updated = World (map (\o -> if idOf o == identifier then updatedObject else o) objects)
                change = if created then ObjectCreated identifier property else
                  case previousProperty object property of
                    Just old | old == property -> NoChange
                    old -> PropertyChanged identifier old property
            in (updated, Result change)
      in case property of
        P position
          | not (inBounds position) -> blocked "Outside board"
          | any (\o -> idOf o /= identifier && positionOf o == Just position) objects ->
              blocked (prettyPosition position ++ " occupied")
        _ -> apply

-- Structural operations resolve existing objects only; failure leaves the world intact.
evaluateAtomicPerformative world (Remove reference) =
  evaluateAtomicPerformative world (RemoveAttribute reference RemoveSquare)
evaluateAtomicPerformative world@(World objects) (RemoveAttribute reference attribute) =
  case resolveReference world reference of
    Message message -> (world, Message message)
    Result object ->
      let (old, updated) = case attribute of
            RemoveColor -> (C <$> colorOf object, object {colorOf = Nothing})
            RemoveSize -> (S <$> sizeOf object, object {sizeOf = Nothing})
            RemoveShape -> (Sh <$> shapeOf object, object {shapeOf = Nothing})
            RemoveSquare -> (P <$> positionOf object, object {positionOf = Nothing})
          change = case old of
            Nothing -> NoChange
            Just (P position) -> ObjectRemoved (idOf object) position
            Just property -> PropertyCleared (idOf object) property
      in (World [if sameId current object then updated else current | current <- objects], Result change)
evaluateAtomicPerformative world@(World objects) (Delete reference) =
  case resolveReference world reference of
    Message message -> (world, Message message)
    Result object -> (World (filter (not . sameId object) objects), Result (ObjectDeleted (idOf object)))
evaluateAtomicPerformative world@(World objects) (Swap first second) =
  case (resolveReference world first, resolveReference world second) of
    (Message message, _) -> (world, Message message)
    (_, Message message) -> (world, Message message)
    (Result left, Result right)
      | sameId left right || positionOf left == positionOf right -> (world, Result NoChange)
      | otherwise ->
          let exchange object
                | sameId object left = object {positionOf = positionOf right}
                | sameId object right = object {positionOf = positionOf left}
                | otherwise = object
          in (World (map exchange objects), Result (ObjectsSwapped (idOf left) (idOf right)))

updateWorldWith :: World -> AtomicPerformative -> World
updateWorldWith world performative = fst (evaluateAtomicPerformative world performative)

previousProperty :: Object -> Property -> Maybe Property
previousProperty object (C _)   = C <$> colorOf object
previousProperty object (S _)   = S <$> sizeOf object
previousProperty object (Sh _)  = Sh <$> shapeOf object
previousProperty object (P _)   = P <$> positionOf object

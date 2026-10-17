module AtomicPerformative where

import Domain
import Domains.Objects.Definition (objectsDomain)
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
data RemovableAttribute = RemoveStored AttributeId | RemoveSquare
  deriving (Eq, Show)

instance PrettyShow RemovableAttribute where
  pretty (RemoveStored attribute) = pretty attribute
  pretty RemoveSquare = "square"

instance PrettyShow AtomicPerformative where
  pretty (AP identifier property) =
    pretty identifier ++ " " ++ pretty property ++ "."
  pretty (RemoveAttribute reference attribute) = pretty reference ++ " remove " ++ pretty attribute ++ "."
  pretty (Remove reference) = "remove " ++ pretty reference ++ "."
  pretty (Swap first second) = "swap " ++ pretty first ++ " and " ++ pretty second ++ "."
  pretty (Delete reference) = "delete " ++ pretty reference ++ "."

updateObjectWith :: Object -> Property -> Object
updateObjectWith object (AttributeValue attribute value) = setAttribute attribute (Just value) object
updateObjectWith object (Defined _) = object
updateObjectWith object (P position) = object {positionOf = Just position}

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

isPosition :: Property -> Bool
isPosition (P _) = True
isPosition _ = False

evaluateAtomicPerformativeWith :: Domain -> World -> AtomicPerformative -> (World, Result UpdateChange)
evaluateAtomicPerformativeWith domain world (AP reference property)
  | Defined _ <- property = (world, Message "Defined attribution requires domain evaluation")
  | not (validProperty domain property) && not (isPosition property) = (world, Message "Invalid property")
  | otherwise = case (resolvePerformativeReferenceWith domain) world reference of
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
          | not ((inBoundsWith domain) position) -> blocked "Outside board"
          | any (\o -> idOf o /= identifier && positionOf o == Just position) objects ->
              blocked (prettyPosition position ++ " occupied")
        _ -> apply

-- Structural operations resolve existing objects only; failure leaves the world intact.
evaluateAtomicPerformativeWith domain world (Remove reference) =
  (evaluateAtomicPerformativeWith domain) world (RemoveAttribute reference RemoveSquare)
evaluateAtomicPerformativeWith domain world@(World objects) (RemoveAttribute reference attribute)
  | RemoveStored name <- attribute, name `notElem` map attributeId (domainAttributes domain) = (world, Message "Invalid attribute")
  | otherwise = case resolveReference world reference of
    Message message -> (world, Message message)
    Result object ->
      let (old, updated) = case attribute of
            RemoveStored attribute -> (AttributeValue attribute <$> attributeOf attribute object, setAttribute attribute Nothing object)
            RemoveSquare -> (P <$> positionOf object, object {positionOf = Nothing})
          change = case old of
            Nothing -> NoChange
            Just (P position) -> ObjectRemoved (idOf object) position
            Just property -> PropertyCleared (idOf object) property
      in (World [if sameId current object then updated else current | current <- objects], Result change)
evaluateAtomicPerformativeWith domain world@(World objects) (Delete reference) =
  case resolveReference world reference of
    Message message -> (world, Message message)
    Result object -> (World (filter (not . sameId object) objects), Result (ObjectDeleted (idOf object)))
evaluateAtomicPerformativeWith domain world@(World objects) (Swap first second) =
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

updateWorldWithWith :: Domain -> World -> AtomicPerformative -> World
updateWorldWithWith domain world performative = fst ((evaluateAtomicPerformativeWith domain) world performative)

previousProperty :: Object -> Property -> Maybe Property
previousProperty object (AttributeValue attribute _) = AttributeValue attribute <$> attributeOf attribute object
previousProperty _ (Defined _) = Nothing
previousProperty object (P _) = P <$> positionOf object

-- Current-domain convenience entry points.
evaluateAtomicPerformative :: World -> AtomicPerformative -> (World, Result UpdateChange)
evaluateAtomicPerformative = evaluateAtomicPerformativeWith objectsDomain
updateWorldWith :: World -> AtomicPerformative -> World
updateWorldWith = updateWorldWithWith objectsDomain

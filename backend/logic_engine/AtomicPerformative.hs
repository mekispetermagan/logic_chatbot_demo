module AtomicPerformative where

import Ontology
import Pretty
import ReferenceResolution
import Result

data AtomicPerformative = AP
                        { subjectPart :: ObjectReference
                        , propPart    :: Property
                        }
                        deriving (Eq, Show)

instance PrettyShow AtomicPerformative where
  pretty (AP identifier property) =
    pretty identifier ++ " " ++ pretty property ++ "."

updateObjectWith :: Object -> Property -> Object
updateObjectWith (Object i mc ms msh mp) (C c)    = (Object i (Just c) ms msh mp)
updateObjectWith (Object i mc ms msh mp) (S s)    = (Object i mc (Just s) msh mp)
updateObjectWith (Object i mc ms msh mp) (Sh sh)  = (Object i mc ms (Just sh) mp)
updateObjectWith (Object i mc ms msh mp) (P p)    = (Object i mc ms msh (Just p))

data UpdateChange = ObjectCreated Identifier Property
                  | PropertyChanged Identifier (Maybe Property) Property
                  | NoChange
                  | UpdateBlocked (Maybe Identifier) String
                  deriving (Eq, Show)

instance PrettyShow UpdateChange where
  pretty (ObjectCreated identifier property) = "Created " ++ pretty identifier ++ ": " ++ pretty property
  pretty (PropertyChanged identifier previous property) =
    pretty identifier ++ ": " ++ maybe "none" pretty previous ++ " -> " ++ pretty property
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

updateWorldWith :: World -> AtomicPerformative -> World
updateWorldWith world performative = fst (evaluateAtomicPerformative world performative)

previousProperty :: Object -> Property -> Maybe Property
previousProperty object (C _)   = C <$> colorOf object
previousProperty object (S _)   = S <$> sizeOf object
previousProperty object (Sh _)  = Sh <$> shapeOf object
previousProperty object (P _)   = P <$> positionOf object

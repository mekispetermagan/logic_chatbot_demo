module Ontology where

import Data.Char (chr, ord)
import qualified Data.Map.Strict as Map
import Pretty

newtype Identifier      = Id Int                      deriving (Eq, Show)
newtype AttributeId = AttributeId String deriving (Eq, Ord, Show)
newtype ValueId = ValueId String deriving (Eq, Ord, Show)

instance PrettyShow AttributeId where pretty (AttributeId name) = name
instance PrettyShow ValueId where pretty (ValueId name) = name

type Position           = (Int, Int)

instance Ord Identifier where
  (<=) :: Identifier -> Identifier -> Bool
  (Id n) <= (Id m) = n <= m

data Property = AttributeValue AttributeId ValueId | P Position deriving (Eq, Show)

data Object = Object
  { idOf :: Identifier
  , attributesOf :: Map.Map AttributeId ValueId
  , positionOf :: Maybe Position
  } deriving (Eq, Show)

attributeOf :: AttributeId -> Object -> Maybe ValueId
attributeOf attribute = Map.lookup attribute . attributesOf

setAttribute :: AttributeId -> Maybe ValueId -> Object -> Object
setAttribute attribute value object = object { attributesOf =
  maybe (Map.delete attribute) (Map.insert attribute) value (attributesOf object) }

holdsProperty :: Object -> Property -> Bool
holdsProperty object (AttributeValue attribute value) = attributeOf attribute object == Just value
holdsProperty object (P position) = positionOf object == Just position

data ObjectReference = ById Identifier | AtSquare Position deriving (Eq, Show)

instance PrettyShow Identifier where
  pretty identifier = "#" ++ show (idToInt identifier)

prettyPosition :: Position -> String
prettyPosition (x, y)
  | x >= 0 && x < 26 && y >= 0 = [chr (ord 'A' + x)] ++ show (toInteger y + 1)
  | otherwise = show (x, y)

instance PrettyShow ObjectReference where
  pretty (ById identifier) = pretty identifier
  pretty (AtSquare position) = prettyPosition position

newtype World = World [Object] deriving (Eq, Show)

instance PrettyShow Property where
  pretty (AttributeValue _ value) = pretty value
  pretty (P position) = "on " ++ prettyPosition position

instance PrettyShow Object where
  pretty object = pretty (idOf object) ++ ": " ++ unwords
    [pretty attribute ++ "=" ++ pretty value | (attribute,value) <- Map.toAscList (attributesOf object)]
    ++ " on " ++ maybe "?" prettyPosition (positionOf object)

instance PrettyShow World where
  pretty (World []) = "(empty world)"
  pretty (World objects) = unlines (map pretty objects)

idToInt :: Identifier -> Int
idToInt (Id n) = n

hasId :: World -> Identifier -> Bool
hasId (World objects) id = any (\o -> idOf o == id) objects

-- Error on empty world
maxId :: World -> Identifier
maxId (World os) = maximum $ map idOf os

nextId :: World -> Identifier
nextId (World []) = Id 0
nextId world = Id $ succ $ idToInt $ maxId world

sameId :: Object -> Object -> Bool
sameId o o' = idOf o == idOf o'

emptyObject :: Identifier -> Object
emptyObject i = Object i Map.empty Nothing

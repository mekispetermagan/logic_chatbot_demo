module Ontology where

import Data.Char (chr, ord, toLower)
import Pretty

newtype Identifier      = Id Int                      deriving (Eq, Show)
data Color              = Blue | Green | Red | Yellow deriving (Eq, Show)
data Size               = Small | Medium | Large      deriving (Eq, Show)
data Shape              = Bloom | Spark | Drop | Loop     deriving (Eq, Show)
type Position           = (Int, Int)

instance Ord Identifier where
  (<=) :: Identifier -> Identifier -> Bool
  (Id n) <= (Id m) = n <= m

data Property           = C Color | S Size | Sh Shape | P Position
                        deriving (Eq, Show)

data Object             = Object
                        { idOf        :: Identifier
                        , colorOf     :: Maybe Color
                        , sizeOf      :: Maybe Size
                        , shapeOf     :: Maybe Shape
                        , positionOf  :: Maybe Position
                        }
                        deriving (Eq, Show)

data ObjectReference = ById Identifier | AtSquare Position deriving (Eq, Show)

instance PrettyShow Identifier where
  pretty identifier = "#" ++ show (idToInt identifier)

prettyPosition :: Position -> String
prettyPosition (x, y)
  | x >= 0 && x < 8 && y >= 0 && y < 8 = [chr (ord 'A' + x)] ++ show (y + 1)
  | otherwise = show (x, y)

instance PrettyShow ObjectReference where
  pretty (ById identifier) = pretty identifier
  pretty (AtSquare position) = prettyPosition position

newtype World = World [Object] deriving (Eq, Show)

instance PrettyShow Property where
  pretty (C color) = map toLower (show color)
  pretty (S size) = map toLower (show size)
  pretty (Sh shape) = map toLower (show shape)
  pretty (P (x, y))
    | x >= 0 && x < 8 && y >= 0 && y < 8 =
        "on " ++ [chr (ord 'A' + x)] ++ show (y + 1)
    | otherwise = "on " ++ show (x, y)

instance PrettyShow Object where
  pretty object = pretty (idOf object) ++ ": " ++ unwords
    [ attribute (colorOf object)
    , attribute (sizeOf object)
    , attribute (shapeOf object)
    , "on"
    , maybe "?" square (positionOf object)
    ]
    where
      attribute :: Show a => Maybe a -> String
      attribute = maybe "?" (map toLower . show)
      square (x, y)
        | x >= 0 && x < 8 && y >= 0 && y < 8 =
            [chr (ord 'A' + x)] ++ show (y + 1)
        | otherwise = show (x, y)

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
emptyObject i = Object i Nothing Nothing Nothing Nothing

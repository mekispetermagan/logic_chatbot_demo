module AtomicPropertyQuery where

import Data.Char (chr, ord)
import Ontology
import Pretty
import Result
import ReferenceResolution

data Attribute = ColorAttribute | SizeAttribute | ShapeAttribute
               | PositionAttribute | RowAttribute | ColumnAttribute
               deriving (Eq, Show)

data AtomicPropertyQuery = APQ
  { queryAttribute :: Attribute
  , querySubject :: ObjectReference
  } deriving (Eq, Show)

-- Row and column values remain zero-based internally.
data QueryAnswer = PropertyValue Property | RowValue Int | ColumnValue Int
                 | Absent
                 deriving (Eq, Show)

instance PrettyShow Attribute where
  pretty ColorAttribute = "color"
  pretty SizeAttribute = "size"
  pretty ShapeAttribute = "shape"
  pretty PositionAttribute = "position"
  pretty RowAttribute = "row"
  pretty ColumnAttribute = "column"

instance PrettyShow AtomicPropertyQuery where
  pretty (APQ attribute identifier) =
    pretty attribute ++ " of " ++ pretty identifier ++ "?"

instance PrettyShow QueryAnswer where
  pretty (PropertyValue (P position)) = prettyPosition position
  pretty (PropertyValue property) = pretty property
  pretty (RowValue row) = show (row + 1)
  pretty (ColumnValue column)
    | column >= 0 && column < 8 = [chr (ord 'A' + column)]
    | otherwise = show column
  pretty Absent = "none"

evaluateAtomicPropertyQuery :: World -> AtomicPropertyQuery -> Result QueryAnswer
evaluateAtomicPropertyQuery world (APQ attribute identifier) =
  case resolveReference world identifier of
    Message message -> Message message
    Result object -> Result $ case attribute of
      ColorAttribute -> maybe Absent (PropertyValue . C) (colorOf object)
      SizeAttribute -> maybe Absent (PropertyValue . S) (sizeOf object)
      ShapeAttribute -> maybe Absent (PropertyValue . Sh) (shapeOf object)
      PositionAttribute -> maybe Absent (PropertyValue . P) (positionOf object)
      RowAttribute -> maybe Absent (RowValue . snd) (positionOf object)
      ColumnAttribute -> maybe Absent (ColumnValue . fst) (positionOf object)

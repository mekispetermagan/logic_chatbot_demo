module AtomicPropertyQuery where

import Data.Char (chr, ord)
import Domain
import Domains.Objects.Definition (objectsDomain)
import Ontology
import Pretty
import Result
import ReferenceResolution

data Attribute = Stored AttributeId
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
  pretty (Stored attribute) = pretty attribute
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
    | column >= 0 && column < 26 = [chr (ord 'A' + column)]
    | otherwise = show column
  pretty Absent = "none"

evaluateAtomicPropertyQueryWith :: Domain -> World -> AtomicPropertyQuery -> Result QueryAnswer
evaluateAtomicPropertyQueryWith domain world (APQ attribute identifier)
  | Stored name <- attribute, name `notElem` map attributeId (domainAttributes domain) = Message "Invalid attribute"
  | otherwise = case resolveReference world identifier of
    Message message -> Message message
    Result object -> Result $ case attribute of
      Stored attribute -> maybe Absent (PropertyValue . AttributeValue attribute) (attributeOf attribute object)
      PositionAttribute -> maybe Absent (PropertyValue . P) (positionOf object)
      RowAttribute -> maybe Absent (RowValue . snd) (positionOf object)
      ColumnAttribute -> maybe Absent (ColumnValue . fst) (positionOf object)

-- Current-domain convenience entry points.
evaluateAtomicPropertyQuery :: World -> AtomicPropertyQuery -> Result QueryAnswer
evaluateAtomicPropertyQuery = evaluateAtomicPropertyQueryWith objectsDomain

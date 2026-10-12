{-# LANGUAGE PatternSynonyms, ViewPatterns #-}
module Domains.Objects.Vocabulary where

import Data.Char (toLower, toUpper)
import qualified Data.Map.Strict as Map
import Ontology
import AtomicPropertyQuery (Attribute(..))
import AtomicPerformative (RemovableAttribute(..))

data Color = Blue | Green | Red | Yellow deriving (Eq, Show, Read)
data Size = Small | Medium | Large deriving (Eq, Show, Read)
data Shape = Bloom | Spark | Drop | Loop deriving (Eq, Show, Read)

value :: Show a => a -> ValueId
value = ValueId . map toLower . show
readValue :: Read a => ValueId -> Maybe a
readValue (ValueId name) = case reads (case name of c:cs -> toUpper c:cs; [] -> []) of
  [(result, "")] -> Just result
  _ -> Nothing

pattern C :: Color -> Property
pattern C color <- AttributeValue (AttributeId "color") (readValue -> Just color)
  where C color = AttributeValue (AttributeId "color") (value color)
pattern S :: Size -> Property
pattern S size <- AttributeValue (AttributeId "size") (readValue -> Just size)
  where S size = AttributeValue (AttributeId "size") (value size)
pattern Sh :: Shape -> Property
pattern Sh shape <- AttributeValue (AttributeId "shape") (readValue -> Just shape)
  where Sh shape = AttributeValue (AttributeId "shape") (value shape)

pattern ColorAttribute = Stored (AttributeId "color")
pattern SizeAttribute = Stored (AttributeId "size")
pattern ShapeAttribute = Stored (AttributeId "shape")
pattern RemoveColor = RemoveStored (AttributeId "color")
pattern RemoveSize = RemoveStored (AttributeId "size")
pattern RemoveShape = RemoveStored (AttributeId "shape")

colorOf :: Object -> Maybe Color
colorOf object = attributeOf (AttributeId "color") object >>= readValue
sizeOf :: Object -> Maybe Size
sizeOf object = attributeOf (AttributeId "size") object >>= readValue
shapeOf :: Object -> Maybe Shape
shapeOf object = attributeOf (AttributeId "shape") object >>= readValue

objectWith :: Identifier -> Maybe Color -> Maybe Size -> Maybe Shape -> Maybe Position -> Object
objectWith identifier color size shape position = Object identifier
  (Map.fromList [(attribute, stored) | (attribute, Just stored) <-
    [(AttributeId "color", value <$> color), (AttributeId "size", value <$> size), (AttributeId "shape", value <$> shape)]]) position

{-# LANGUAGE OverloadedStrings #-}
module EditorJson (processRequest) where

import Control.Monad (unless)
import Data.Aeson hiding (Object)
import Data.Aeson.Types (Parser, parseEither)
import Data.List (nub)
import Ontology
import ReferenceResolution (inBounds)
import WorldEditor

parsePosition :: Value -> Parser Position
parsePosition = withObject "position" $ \value -> (,) <$> value .: "x" <*> value .: "y"

parseColor :: String -> Parser Color
parseColor value = case value of
  "red" -> pure Red
  "blue" -> pure Blue
  "green" -> pure Green
  "yellow" -> pure Yellow
  _ -> fail "Invalid color"

parseSize :: String -> Parser Size
parseSize value = case value of
  "small" -> pure Small
  "medium" -> pure Medium
  "large" -> pure Large
  _ -> fail "Invalid size"

parseShape :: String -> Parser Shape
parseShape value = case value of
  "cube" -> pure Cube
  "sphere" -> pure Sphere
  "pyramid" -> pure Pyramid
  _ -> fail "Invalid shape"

parseObject :: Value -> Parser Object
parseObject = withObject "world object" $ \value -> do
  identifier <- value .: "id"
  unless (identifier >= 0 && identifier < maxBound) (fail "Invalid identifier")
  color <- value .:? "color" >>= traverse parseColor
  size <- value .:? "size" >>= traverse parseSize
  shape <- value .:? "shape" >>= traverse parseShape
  position <- value .:? "position" >>= traverse parsePosition
  pure (Object (Id identifier) color size shape position)

parseWorld :: Value -> Parser World
parseWorld = withObject "world" $ \value -> do
  width <- value .: "width" :: Parser Int
  height <- value .: "height" :: Parser Int
  unless (width == 8 && height == 8) (fail "Only 8x8 worlds supported")
  objects <- value .: "objects" >>= mapM parseObject
  let identifiers = map idOf objects
      positions = [position | Just position <- map positionOf objects]
  unless (length identifiers == length (nub identifiers)) (fail "Duplicate identifiers")
  unless (all inBounds positions) (fail "Object outside board")
  unless (length positions == length (nub positions)) (fail "Colliding objects")
  pure (World objects)

parseProperty :: String -> Parser Property
parseProperty value
  | value `elem` ["red", "blue", "green", "yellow"] = C <$> parseColor value
  | value `elem` ["small", "medium", "large"] = S <$> parseSize value
  | otherwise = Sh <$> parseShape value

parseAction :: Value -> Parser EditorAction
parseAction = withObject "action" $ \value -> do
  kind <- value .: "type" :: Parser String
  case kind of
    "property" -> ApplyProperty <$> (value .: "position" >>= parsePosition)
                                <*> (value .: "property" >>= parseProperty)
    "place" -> PlaceObject <$> (Id <$> value .: "objectId")
                           <*> (value .: "position" >>= parsePosition)
    "erase" -> EraseSquare <$> (value .: "position" >>= parsePosition)
    "clear" -> pure ClearWorld
    _ -> fail "Invalid editor action"

parseRequest :: Value -> Parser (World, EditorAction)
parseRequest = withObject "request" $ \value ->
  (,) <$> (value .: "world" >>= parseWorld) <*> (value .: "action" >>= parseAction)

positionJson :: Position -> Value
positionJson (x, y) = object ["x" .= x, "y" .= y]

objectJson :: Object -> Value
objectJson value = object
  [ "id" .= idToInt (idOf value)
  , "color" .= fmap colorName (colorOf value)
  , "size" .= fmap sizeName (sizeOf value)
  , "shape" .= fmap shapeName (shapeOf value)
  , "position" .= fmap positionJson (positionOf value)
  ]
  where
    colorName :: Color -> String
    colorName Red = "red"
    colorName Blue = "blue"
    colorName Green = "green"
    colorName Yellow = "yellow"
    sizeName :: Size -> String
    sizeName Small = "small"
    sizeName Medium = "medium"
    sizeName Large = "large"
    shapeName :: Shape -> String
    shapeName Cube = "cube"
    shapeName Sphere = "sphere"
    shapeName Pyramid = "pyramid"

processRequest :: Value -> Either String Value
processRequest input = do
  (world, action) <- parseEither parseRequest input
  let (World objects, feedback) = evaluateEditorAction world action
  pure (object ["world" .= object ["width" .= (8 :: Int), "height" .= (8 :: Int),
                                  "objects" .= map objectJson objects],
                "feedback" .= feedback])

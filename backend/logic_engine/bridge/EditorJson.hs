{-# LANGUAGE OverloadedStrings #-}
module EditorJson (processRequest) where

import Control.Monad (unless)
import Data.Aeson hiding (Object)
import Data.Aeson.Types (Parser, parseEither)
import Data.List (nub, intercalate)
import Layer2Parser (parseSentences, isUndoEntry)
import Discourse
import Layer2Evaluation
import Pretty (pretty)
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

data Operation = Chat String | Clarify Identifier | Edit EditorAction

parseRanking :: Value -> Parser SalienceRanking
parseRanking = withArray "salience" $ mapM parseMention . foldr (:) []
  where
    parseMention = withObject "mention" $ \value -> do
      entry <- value .: "entry"
      utterance <- value .: "utterance"
      identifier <- Id <$> value .: "objectId"
      properties <- value .: "properties" >>= mapM parseMentionProperty
      unless (entry >= 0 && utterance >= 0) (fail "Invalid recency")
      pure ((entry, utterance), identifier, properties)
    parseMentionProperty = withObject "property" $ \value -> do
      kind <- value .: "kind" :: Parser String
      if kind == "position" then P <$> (value .: "value" >>= parsePosition)
      else value .: "value" >>= parseProperty

parsePending :: Value -> Parser Pending
parsePending = withObject "pending" $ \value -> do
  text <- value .: "remaining"
  sentences <- either fail pure (parseSentences text)
  identifiers <- map Id <$> value .: "candidateIds"
  unless (not (null sentences) && not (null identifiers)) (fail "Invalid pending entry")
  resolved <- map Id <$> (value .:? "resolvedSubjects" .!= [])
  pure (Pending sentences identifiers resolved)

parseRequest :: Value -> Parser (World, SalienceRanking, Maybe Pending, Operation)
parseRequest = withObject "request" $ \value -> do
  world <- value .: "world" >>= parseWorld
  ranking <- value .:? "salience" .!= Array mempty >>= parseRanking
  pending <- value .:? "pending" >>= traverse parsePending
  action <- value .: "action"
  operation <- withObject "action" (\fields -> do
    kind <- fields .: "type" :: Parser String
    case kind of
      "chat" -> Chat <$> fields .: "text"
      "clarify" -> Clarify . Id <$> fields .: "objectId"
      _ -> Edit <$> parseAction action) action
  pure (world, ranking, pending, operation)

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

rankingJson :: SalienceRanking -> Value
rankingJson ranking = toJSON [object
  ["entry" .= entry, "utterance" .= utterance, "objectId" .= idToInt identifier,
   "properties" .= map propertyJson properties]
  | ((entry, utterance), identifier, properties) <- ranking]
  where
    propertyJson (P position) = object ["kind" .= ("position" :: String), "value" .= positionJson position]
    propertyJson property = object ["kind" .= ("descriptor" :: String), "value" .= pretty property]

pendingJson :: World -> Pending -> Value
pendingJson (World objects) pending = object
  [ "remaining" .= intercalate " " (map pretty (remainingSentences pending))
  , "sentence" .= case remainingSentences pending of sentence:_ -> pretty sentence; [] -> ""
  , "candidateIds" .= map idToInt (candidateIds pending)
  , "resolvedSubjects" .= map idToInt (resolvedSubjects pending)
  , "candidates" .= [object ["objectId" .= idToInt identifier, "label" .= pretty value]
       | identifier <- candidateIds pending, value <- objects, idOf value == identifier]
  ]

processRequest :: Value -> Either String Value
processRequest input = do
  (world, ranking, pending, action) <- parseEither parseRequest input
  let undoRequested = case action of Chat text -> isUndoEntry text; _ -> False
      (updated@(World objects), salience, nextPending, feedback, isError) = case (pending, action) of
        (_, Chat _) | undoRequested -> (world, ranking, pending, "", False)
        (Just paused, Clarify identifier) ->
          let (w, r, p, message) = resumeEntry world ranking paused identifier
          in (w, r, p, message, False)
        (Just _, _) -> (world, ranking, pending, "Choose an object or undo", True)
        (Nothing, Clarify _) -> (world, ranking, Nothing, "No clarification pending", True)
        (Nothing, Chat text) -> case parseSentences text of
          Left message -> (world, ranking, Nothing, message, True)
          Right sentences -> let (w, r, p, message) = evaluateEntry world ranking sentences
                             in (w, r, p, message, False)
        (Nothing, Edit edit) ->
          let (w, message) = evaluateEditorAction world edit
          in (w, purge w ranking, Nothing, message, False)
  pure (object (["world" .= object ["width" .= (8 :: Int), "height" .= (8 :: Int),
                                  "objects" .= map objectJson objects],
                "salience" .= rankingJson salience,
                "pending" .= fmap (pendingJson updated) nextPending,
                "feedback" .= feedback, "isError" .= isError] ++
                ["undoRequested" .= True | undoRequested]))

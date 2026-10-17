{-# LANGUAGE OverloadedStrings #-}
module EditorJson (processRequest) where

import Control.Monad (unless)
import Data.Aeson hiding (Object)
import Data.Aeson.Types (Parser, parseEither)
import Data.List (nub, intercalate)
import Layer2Parser (parseSentencesWith, isUndoEntry)
import Discourse
import Layer2Evaluation
import Pretty (pretty)
import Ontology
import Domain
import qualified Data.Map.Strict as Map
import DomainLibrary (DomainLibrary, ontology, propertyTruth)
import Domains.Objects.Library (objectsLibrary)
import Domains.Network.Library (networkLibrary)
import ReferenceResolution (inBoundsWith)
import WorldEditor

parsePosition :: Value -> Parser Position
parsePosition = withObject "position" $ \value -> (,) <$> value .: "x" <*> value .: "y"

-- Attribute identifiers and values are canonical transport names, not aliases.
parseProperty :: Domain -> Value -> Parser Property
parseProperty domain = withObject "attribute property" $ \value -> do
  attribute <- AttributeId <$> value .: "attribute"
  stored <- ValueId <$> value .: "value"
  let property = AttributeValue attribute stored
  unless (validProperty domain property) (fail "Invalid attribute/value")
  pure property

parseObject :: Domain -> Value -> Parser Object
parseObject domain = withObject "world object" $ \value -> do
  identifier <- value .: "id"
  unless (identifier >= 0 && identifier < maxBound) (fail "Invalid identifier")
  attributes <- value .: "attributes" :: Parser (Map.Map String String)
  let stored = Map.fromList [(AttributeId name, ValueId item) | (name,item) <- Map.toList attributes]
  unless (all (validProperty domain . uncurry AttributeValue) (Map.toList stored))
    (fail "Invalid object attribute/value")
  position <- value .:? "position" >>= traverse parsePosition
  pure (Object (Id identifier) stored position)

parseWorld :: Domain -> Value -> Parser World
parseWorld domain = withObject "world" $ \value -> do
  width <- value .: "width" :: Parser Int
  height <- value .: "height" :: Parser Int
  unless (width == boardWidth domain && height == boardHeight domain) (fail "Only 8x8 worlds supported")
  objects <- value .: "objects" >>= mapM (parseObject domain)
  let identifiers = map idOf objects
      positions = [position | Just position <- map positionOf objects]
  unless (length identifiers == length (nub identifiers)) (fail "Duplicate identifiers")
  unless (all (inBoundsWith domain) positions) (fail "Object outside board")
  unless (length positions == length (nub positions)) (fail "Colliding objects")
  pure (World objects)

parseAction :: Domain -> Value -> Parser EditorAction
parseAction domain = withObject "action" $ \value -> do
  kind <- value .: "type" :: Parser String
  case kind of
    "property" -> ApplyProperty <$> (value .: "position" >>= parsePosition)
                                <*> (value .: "property" >>= parseProperty domain)
    "ports" -> do
      unless (domainId domain == "network") (fail "Ports require network domain")
      position <- value .: "position" >>= parsePosition
      ports <- value .: "ports" :: Parser [String]
      let names = ["north", "east", "south", "west"]
      unless (all (`elem` names) ports && length ports == length (nub ports)) (fail "Invalid ports")
      pure (ReplaceAttributes position (map AttributeId names)
        [AttributeValue (AttributeId port) (ValueId port) | port <- ports])
    "place" -> PlaceObject <$> (Id <$> value .: "objectId")
                           <*> (value .: "position" >>= parsePosition)
    "erase" -> EraseSquare <$> (value .: "position" >>= parsePosition)
    "clear" -> pure ClearWorld
    _ -> fail "Invalid editor action"

data Operation = Chat String | Clarify Identifier | ClarifySquare Position | Edit EditorAction

parseRanking :: Domain -> Value -> Parser SalienceRanking
parseRanking domain = withArray "salience" $ mapM parseMention . foldr (:) []
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
      else if kind == "defined" then do
        name <- value .: "value"
        unless (validProperty domain (Defined name)) (fail "Invalid defined property")
        pure (Defined name)
      else if kind == "attribute" then parseProperty domain (toJSON value)
      else fail "Invalid salience property kind"

parsePending :: DomainLibrary -> Value -> Parser Pending
parsePending library = withObject "pending" $ \value -> do
  text <- value .: "remaining"
  sentences <- either fail pure (parseSentencesWith library text)
  identifiers <- map Id <$> value .: "candidateIds"
  squares <- value .:? "squareChoices" .!= [] >>= mapM parsePosition
  unless (not (null sentences) && (not (null identifiers) /= not (null squares)) && all (inBoundsWith (ontology library)) squares)
    (fail "Invalid pending entry")
  resolved <- map Id <$> (value .:? "resolvedSubjects" .!= [])
  pure (if null squares then Pending sentences identifiers resolved
        else SquarePending sentences identifiers resolved squares)

parseRequest :: Value -> Parser (DomainLibrary, World, SalienceRanking, Maybe Pending, Operation)
parseRequest = withObject "request" $ \value -> do
  identifier <- value .: "domain"
  library <- case identifier :: String of
    "objects" -> pure objectsLibrary
    "network" -> pure networkLibrary
    _ -> fail ("Unsupported domain: " ++ identifier)
  let domain = ontology library
  either fail pure (validateDomain domain)
  world <- value .: "world" >>= parseWorld domain
  ranking <- value .:? "salience" .!= Array mempty >>= parseRanking domain
  pending <- value .:? "pending" >>= traverse (parsePending library)
  action <- value .: "action"
  operation <- withObject "action" (\fields -> do
    kind <- fields .: "type" :: Parser String
    case kind of
      "chat" -> Chat <$> fields .: "text"
      "clarify" -> do
        identifier <- fields .:? "objectId"
        position <- fields .:? "position"
        case (identifier, position) of
          (Just i, Nothing) -> pure (Clarify (Id i))
          (Nothing, Just p) -> ClarifySquare <$> parsePosition p
          _ -> fail "Choose an object or a square"
      _ -> Edit <$> parseAction domain action) action
  pure (library, world, ranking, pending, operation)

positionJson :: Position -> Value
positionJson (x, y) = object ["x" .= x, "y" .= y]

objectJson :: Object -> Value
objectJson value = object
  [ "id" .= idToInt (idOf value)
  , "attributes" .= Map.fromList [(pretty name, pretty stored) | (name,stored) <- Map.toList (attributesOf value)]
  , "position" .= fmap positionJson (positionOf value)
  ]

rankingJson :: SalienceRanking -> Value
rankingJson ranking = toJSON [object
  ["entry" .= entry, "utterance" .= utterance, "objectId" .= idToInt identifier,
   "properties" .= map propertyJson properties]
  | ((entry, utterance), identifier, properties) <- ranking]
  where
    propertyJson (P position) = object ["kind" .= ("position" :: String), "value" .= positionJson position]
    propertyJson (Defined name) = object ["kind" .= ("defined" :: String), "value" .= name]
    propertyJson (AttributeValue attribute value) = object
      ["kind" .= ("attribute" :: String), "attribute" .= pretty attribute, "value" .= pretty value]

pendingJson :: Domain -> World -> Pending -> Value
pendingJson domain (World objects) pending = object
  [ "remaining" .= intercalate " " (map pretty (remainingSentences pending))
  , "sentence" .= case remainingSentences pending of sentence:_ -> pretty sentence; [] -> ""
  , "candidateIds" .= map idToInt (candidateIds pending)
  , "squareChoices" .= case pending of
      SquarePending {squareChoices = positions} -> map positionJson positions
      _ -> []
  , "resolvedSubjects" .= map idToInt (resolvedSubjects pending)
  , "candidates" .= [object ["objectId" .= idToInt identifier, "label" .= prettyObjectIn domain value]
       | identifier <- candidateIds pending, value <- objects, idOf value == identifier]
  ]

processRequest :: Value -> Either String Value
processRequest input = do
  (library, world, ranking, pending, action) <- parseEither parseRequest input
  let domain = ontology library
      undoRequested = case action of Chat text -> isUndoEntry text; _ -> False
      (updated@(World objects), salience, nextPending, feedback, isError) = case (pending, action) of
        (_, Chat _) | undoRequested -> (world, ranking, pending, "", False)
        (Just paused, Clarify identifier) ->
          let (w, r, p, message) = resumeEntryIn library world ranking paused identifier
          in (w, r, p, message, False)
        (Just paused, ClarifySquare position) ->
          let (w, r, p, message) = resumeSquareEntryIn library world ranking paused position
          in (w, r, p, message, False)
        (Just _, _) -> (world, ranking, pending, "Choose an object or square, or undo", True)
        (Nothing, Clarify _) -> (world, ranking, Nothing, "No clarification pending", True)
        (Nothing, ClarifySquare _) -> (world, ranking, Nothing, "No clarification pending", True)
        (Nothing, Chat text) -> case parseSentencesWith library text of
          Left message -> (world, ranking, Nothing, message, True)
          Right sentences -> let (w, r, p, message) = evaluateEntryIn library world ranking sentences
                             in (w, r, p, message, False)
        (Nothing, Edit edit) ->
          let (w, message) = evaluateEditorActionWith domain world edit
          in (w, purgeWith (propertyTruth library) w ranking, Nothing, message, False)
  pure (object (["domain" .= domainId domain, "world" .= object ["width" .= boardWidth domain, "height" .= boardHeight domain,
                                  "objects" .= map objectJson objects],
                "salience" .= rankingJson salience,
                "pending" .= fmap (pendingJson domain updated) nextPending,
                "feedback" .= feedback, "isError" .= isError] ++
                ["undoRequested" .= True | undoRequested]))

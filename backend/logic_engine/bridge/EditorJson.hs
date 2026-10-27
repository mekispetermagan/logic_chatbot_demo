{-# LANGUAGE OverloadedStrings #-}
module EditorJson (processRequest) where

import Control.Monad (unless)
import Data.Aeson hiding (Object)
import qualified Data.Aeson as Json
import Data.Aeson.Types (Parser, parseEither)
import Data.List (nub, isPrefixOf)
import Text.Read (readMaybe)
import ControlledLanguage.Domain (lookupDomain,languageVersion)
import ControlledLanguage.Discourse
import Pretty (pretty)
import Ontology
import Domain
import qualified Data.Map.Strict as Map
import ReferenceResolution (inBoundsWith)
import WorldEditor
import qualified ControlledLanguage.Parser as V2
import qualified ControlledLanguage.Pretty as V2
import qualified ControlledLanguage.Syntax as V2
import qualified ControlledLanguage.Evaluation as V2
import qualified Domains.Calendar.Language as Calendar
import qualified CellularJson

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

data Operation = Chat String | CheckSyntax String | Clarify Identifier | ClarifySquare Position | ClarifyGrouping Int | Edit EditorAction

parseRanking :: Domain -> Value -> Parser SalienceRanking
parseRanking domain = withArray "salience" $ mapM parseMention . foldr (:) []
  where
    parseMention = withObject "mention" $ \value -> do
      entry <- value .: "entry"
      utterance <- value .: "utterance"
      identifier <- value .:? "objectId"
      position <- value .:? "position"
      referent <- case (identifier,position) of
        (Just n,Nothing) | n >= 0 && n < maxBound -> pure (ObjectReferent (Id n))
        (Nothing,Just raw) -> do
          p <- parsePosition raw
          unless (inDomainBounds domain p) (fail "Square mention outside board")
          pure (SquareReferent p)
        _ -> fail "A mention must identify exactly one object or square"
      properties <- value .: "properties" >>= mapM (case referent of ObjectReferent _ -> parseMentionProperty; SquareReferent _ -> parseSquareProperty)
      unless (entry >= 0 && utterance >= 0) (fail "Invalid recency")
      pure ((entry, utterance), referent, properties)
    parseSquareProperty = withObject "square property" $ \value -> do
      kind <- value .: "kind" :: Parser String
      source <- value .: "value"
      unless (kind == "defined" && validSquareFact domain source) (fail "Invalid square property")
      pure (Defined source)
    parseMentionProperty = withObject "property" $ \value -> do
      kind <- value .: "kind" :: Parser String
      if kind == "position" then P <$> (value .: "value" >>= parsePosition)
      else if kind == "defined" then do
        name <- value .: "value"
        unless (validFact domain name) (fail "Invalid contextual property")
        pure (Defined name)
      else if kind == "attribute" then parseProperty domain (toJSON value)
      else fail "Invalid salience property kind"

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
  (["entry" .= entry, "utterance" .= utterance, "properties" .= map propertyJson properties] ++ referentJson referent)
  | ((entry,utterance),referent,properties) <- ranking]
  where
    referentJson (ObjectReferent identifier) = ["objectId" .= idToInt identifier]
    referentJson (SquareReferent position) = ["position" .= positionJson position]
    propertyJson (P position) = object ["kind" .= ("position" :: String), "value" .= positionJson position]
    propertyJson (Defined name) = object ["kind" .= ("defined" :: String), "value" .= name]
    propertyJson (AttributeValue attribute value) = object
      ["kind" .= ("attribute" :: String), "attribute" .= pretty attribute, "value" .= pretty value]

data Replay = Replay String World SalienceRanking Int [V2.Choice] Int
            | GroupingReplay [String]

worldJson :: Domain -> World -> Value
worldJson domain (World objects) = object ["width" .= boardWidth domain,"height" .= boardHeight domain,"objects" .= map objectJson objects]

parseReplay :: Domain -> Value -> Parser Replay
parseReplay domain = withObject "pending" $ \pending -> do
  payload <- pending .: "payload"
  withObject "continuation payload" (\v -> do
    version <- v .: "version" :: Parser String
    if version == languageVersion domain ++ "-grouping" then do
      alternatives <- v .: "alternatives"
      unless (length alternatives >= 2) (fail "Invalid grouping choices")
      mapM_ (either fail (const (pure ())) . V2.parseCanonicalWith domain) alternatives
      pure (GroupingReplay alternatives)
    else do
      unless (version == languageVersion domain) (fail "Unsupported continuation version")
      source <- v .: "source"
      w <- v .: "world" >>= parseWorld domain
      r <- v .: "salience" >>= parseRanking domain
      next <- v .: "nextObjectId"
      choices <- v .: "choices" >>= mapM (withObject "choice" $ \choice -> do
        n <- choice .:? "objectId"
        p <- choice .:? "position"
        case (n,p) of
          (Just i,Nothing) -> pure (V2.ObjectChoice i)
          (Nothing,Just pos) -> V2.SquareChoice <$> parsePosition pos
          _ -> fail "Invalid choice")
      completed <- v .: "completed"
      unless (next >= 0 && completed >= 0) (fail "Invalid continuation state")
      pure (Replay source w r next choices completed)) payload

parseV2Request :: Value -> Parser (Domain,World,SalienceRanking,Int,Maybe (Value,Replay),Operation)
parseV2Request = withObject "request" $ \v -> do
  name <- v .: "domain"
  domain <- maybe (fail "Unsupported domain") pure (lookupDomain name)
  version <- v .:? "languageVersion" .!= languageVersion domain
  unless (version == languageVersion domain) (fail "Unsupported language version")
  world@(World os) <- v .: "world" >>= parseWorld domain
  ranking <- v .:? "salience" .!= Array mempty >>= parseRanking domain
  let floorId = case os of [] -> 0; _ -> 1 + maximum (map (idToInt . idOf) os)
  next <- v .:? "nextObjectId" .!= floorId
  unless (next >= floorId && next >= 0) (fail "Identifier allocation is behind the world")
  paused <- v .:? "pending" >>= traverse (\p -> (,) p <$> parseReplay domain p)
  action <- v .: "action"
  operation <- withObject "action" (\fields -> do
    kind <- fields .: "type" :: Parser String
    case kind of
      "chat" -> Chat <$> fields .: "text"
      "checkSyntax" -> CheckSyntax <$> fields .: "text"
      "clarify" -> do
        n <- fields .:? "objectId"; p <- fields .:? "position"; g <- fields .:? "groupingId"
        case (n,p,g) of
          (Just i,Nothing,Nothing) -> pure (Clarify (Id i))
          (Nothing,Just pos,Nothing) -> ClarifySquare <$> parsePosition pos
          (Nothing,Nothing,Just i) | i >= 1 -> pure (ClarifyGrouping i)
          _ -> fail "Choose an object, square, or grouping"
      _ -> Edit <$> parseAction domain action) action
  pure (domain,world,ranking,next,paused,operation)

processRequest :: Value -> Either String Value
processRequest input = do
  name <- parseEither (withObject "request" (.: "domain")) input :: Either String String
  if name == "calendar" then Calendar.processRequest input
  else if name == "cellular" then CellularJson.processRequest input else processObjectRequest input

processObjectRequest :: Value -> Either String Value
processObjectRequest input = do
  (domain,world,ranking,next,pending,operation) <- parseEither parseV2Request input
  let reply :: World -> SalienceRanking -> Int -> Maybe Value -> String -> Bool -> Bool -> Bool -> [V2.Change] -> Value
      reply w r n p feedback failed syntax undo changes = object
        ["domain" .= domainId domain,"languageVersion" .= languageVersion domain,
         "world" .= worldJson domain w,"salience" .= rankingJson r,"nextObjectId" .= n,
         "pending" .= p,"feedback" .= feedback,"isError" .= failed,"syntaxError" .= syntax,"undoRequested" .= undo,
         "changes" .= [object ["objectId" .= V2.changeObject c,"kind" .= V2.changeKind c,"detail" .= V2.changeDetail c] | c <- changes]]
      unchanged message failed syntax undo = reply world ranking next (fmap fst pending) message failed syntax undo []
      groupingPending source entries =
        let alternatives = map V2.canonicalEntryText entries
            labels = map V2.entryText entries
            value = object ["sentence" .= source,"remaining" .= source,
              "candidateIds" .= ([] :: [Int]),"candidates" .= ([] :: [Value]),
              "groupingChoices" .= [object ["groupingId" .= i,"label" .= label] | (i,label) <- zip [1::Int ..] labels],
              "payload" .= object ["version" .= (languageVersion domain ++ "-grouping"),"alternatives" .= alternatives]]
        in reply world ranking next (Just value) "Which grouping? Nothing was applied." False False False []
      evaluateWith parseSource source seed seedRanking seedNext choices completed = case parseSource domain source of
        Left message -> unchanged message True True False
        Right [entry] ->
          let outcome = V2.runEntryWith domain seed seedRanking seedNext entry choices completed
              w = V2.resultWorld outcome
              newPending = case V2.resultPause outcome of
                Nothing -> Nothing
                Just (count,sentence,ids,ps) ->
                  let candidateWorld = maybe w id (V2.stagedWorld outcome)
                  in Just (object ["sentence" .= sentence,"remaining" .= V2.canonicalEntryText entry,
                     "candidateIds" .= ids,"squareChoices" .= map positionJson ps,"resolvedSubjects" .= ([] :: [Int]),
                     "candidates" .= [object ["objectId" .= n,"label" .= prettyObjectIn domain o] | n <- ids, Just o <- [V2.objectAtId candidateWorld n]],
                     "stagedWorld" .= fmap (worldJson domain) (V2.stagedWorld outcome),
                     "payload" .= object ["version" .= languageVersion domain,"source" .= V2.canonicalEntryText entry,
                       "world" .= worldJson domain seed,"salience" .= rankingJson seedRanking,"nextObjectId" .= seedNext,
                       "completed" .= count,"choices" .= map choiceJson choices]])
          in reply w (V2.resultRanking outcome) (max next (V2.resultNextId outcome)) newPending
                   (V2.resultFeedback outcome) (V2.resultError outcome) False False (V2.resultChanges outcome)
        Right entries -> groupingPending source entries
      continue choice = case pending of
        Nothing -> unchanged "No clarification pending" True False False
        Just (value,Replay source seed r n choices completed) ->
          case parseEither (withObject "pending" $ \p -> (,) <$> (p .: "candidateIds" :: Parser [Int]) <*> ((p .: "squareChoices" :: Parser [Value]) >>= mapM parsePosition)) value of
            Right (ids,ps) | (case choice of V2.ObjectChoice i -> i `elem` ids; V2.SquareChoice p -> p `elem` ps) ->
              evaluateWith canonicalReadings source seed r n (choices ++ [choice]) completed
            _ -> unchanged "Choose one of the listed objects or squares" True False False
        Just (_,GroupingReplay _) -> unchanged "Choose one of the listed groupings" True False False
      continueGrouping choice = case pending of
        Just (_,GroupingReplay alternatives) | choice >= 1 && choice <= length alternatives ->
          evaluateWith canonicalReadings (alternatives !! (choice-1)) world ranking next [] 0
        _ -> unchanged "Choose one of the listed groupings" True False False
  pure $ case operation of
    Chat source | V2.parseEntryWith domain source == Right V2.Undo -> unchanged "" False False True
    Clarify n -> continue (V2.ObjectChoice (idToInt n))
    ClarifySquare p -> continue (V2.SquareChoice p)
    ClarifyGrouping n -> continueGrouping n
    _ | pendingPresent pending -> unchanged "Choose an object, square, or grouping, or undo" True False False
    CheckSyntax source -> case V2.parseEntryAlternativesWith domain source of
      Left message -> unchanged message True True False
      Right [entry] -> unchanged (V2.entryText entry) False False False
      Right entries -> unchanged ("Which grouping?\n" ++ unlines (map V2.entryText entries)) False False False
    Chat source -> evaluateWith V2.parseEntryAlternativesWith source world ranking next [] 0
    Edit action -> let (w,n,message) = V2.editWorldWith domain next world action
                   in reply w (V2.purgeRanking domain w ranking) n Nothing message False False False (V2.changesBetweenWith domain world w)
  where
    canonicalReadings domain source = (:[]) <$> V2.parseCanonicalWith domain source
    pendingPresent Nothing = False
    pendingPresent (Just _) = True
    choiceJson (V2.ObjectChoice n) = object ["objectId" .= n]
    choiceJson (V2.SquareChoice p) = object ["position" .= positionJson p]

validFact :: Domain -> String -> Bool
validFact domain source
  | "v2:" `isPrefixOf` source = case readMaybe (drop 3 source) of
      Just c -> case V2.parseCanonicalWith domain (V2.canonicalEntryText (V2.Sequence [V2.Question (V2.CheckObject (V2.Ident 0) c)])) of
        Right _ -> True
        Left _ -> False
      Nothing -> False
  | otherwise = False

validSquareFact :: Domain -> String -> Bool
validSquareFact domain source
  | "square:" `isPrefixOf` source = case readMaybe (drop 7 source) of
      Just c -> case V2.parseCanonicalWith domain (V2.canonicalEntryText (V2.Sequence [V2.Question (V2.CheckSquare (V2.Cell (0,0)) c)])) of
        Right _ -> True
        Left _ -> False
      Nothing -> False
  | otherwise = False

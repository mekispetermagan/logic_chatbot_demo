{-# LANGUAGE OverloadedStrings #-}
module CellularJson (processRequest) where

import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.Types (Parser, parseEither)
import Data.Char (chr, ord)
import Data.Word (Word64)
import Text.Read (readMaybe)
import qualified ControlledLanguage.Discourse as D
import Ontology (Property(..))
import qualified Domains.Cellular.Language.Parser as Language
import qualified Domains.Cellular.Language.Pretty as Language
import qualified Domains.Cellular.Language.Syntax as Language
import qualified Domains.Cellular.Language.Evaluation as Language
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Domains.Cellular.Types
import qualified Domains.Cellular.Evaluation as Cellular

data Action = Step | PaintCell (Int, Int) Color | ReplaceRuleset Ruleset (Maybe Word64)

parseAction :: Value -> Parser Action
parseAction = withObject "cellular action" $ \action -> do
  kind <- action .: "type" :: Parser String
  case kind of
    "step" -> pure Step
    "cell" -> do
      position <- action .: "position" >>= withObject "cell position" (\p -> (,) <$> p .: "x" <*> p .: "y")
      color <- action .: "color" >>= parseColor
      pure (PaintCell position color)
    "ruleset" -> do
      config <- action .: "ruleset" >>= parseRuleset
      refill <- action .:? "refill" .!= False
      seed <- if refill then Just <$> action .: "randomSeed" else pure Nothing
      pure (ReplaceRuleset config seed)
    _ -> fail "Cellular worlds support only step, cell and ruleset actions"

colorName :: Color -> String
colorName White = "white"
colorName Black = "black"
colorName Red = "red"
colorName Green = "green"
colorName Blue = "blue"
colorName Yellow = "yellow"

parseColor :: String -> Parser Color
parseColor name = case lookup name [(colorName color, color) | color <- [minBound..maxBound]] of
  Just color -> pure color
  Nothing -> fail "Unsupported cellular color"

parseRuleset :: Value -> Parser Ruleset
parseRuleset = withObject "cellular ruleset" $ \value -> do
  colors <- value .: "palette" >>= mapM parseColor
  unless (length colors == Set.size (Set.fromList colors)) (fail "Duplicate palette color")
  count <- value .: "neighborhood" :: Parser Int
  mode <- case count of
    4 -> pure Orthogonal
    8 -> pure Moore
    _ -> fail "Neighborhood must be 4 or 8"
  raw <- value .: "rules" :: Parser (Map.Map String Value)
  entries <- mapM parseRule (Map.toList raw)
  pure (Ruleset (Set.fromList colors) mode (Map.fromList entries))
  where
    parseRule (name, raw) = do
      source <- parseColor name
      rule <- withObject "cellular rule" (\value -> do
        target <- value .: "targetColor" >>= parseColor
        neighbor <- value .: "neighborColor" >>= parseColor
        counts <- value .: "counts" :: Parser [Int]
        unless (length counts == Set.size (Set.fromList counts)) (fail "Duplicate neighbor count")
        active <- value .:? "enabled" .!= True
        pure (Rule target neighbor (Set.fromList counts) active)) raw
      pure (source, rule)

parseWorld :: Value -> Parser Automaton
parseWorld = withObject "cellular world" $ \value -> do
  width <- value .: "width" :: Parser Int
  height <- value .: "height" :: Parser Int
  topology <- value .: "topology" :: Parser String
  unless (width == boardSize && height == boardSize && topology == "torus") (fail "Cellular worlds must be 16x16 tori")
  colors <- value .: "cells" >>= mapM parseColor
  unless (length colors == boardSize * boardSize) (fail "Cellular worlds need exactly 256 cell colors")
  config <- value .: "ruleset" >>= parseRuleset
  time <- value .: "generation"
  revision <- value .: "rulesetRevision"
  either fail pure (validateAutomaton (Automaton (Map.fromList (zip boardPositions colors)) config time revision))

worldJson :: Automaton -> Value
worldJson world = object
  [ "width" .= boardSize, "height" .= boardSize, "topology" .= ("torus" :: String)
  , "cells" .= [colorName (cells world Map.! position) | position <- boardPositions]
  , "generation" .= generation world, "rulesetRevision" .= rulesetRevision world
  , "ruleset" .= object
      [ "palette" .= map colorName (Set.toList (palette config))
      , "neighborhood" .= neighborLimit (neighborhood config)
      , "rules" .= Map.fromList [(colorName source, ruleJson rule) | (source,rule) <- Map.toList (rules config)]
      ]
  ]
  where
    config = ruleset world
    ruleJson rule = object
      [ "targetColor" .= colorName (targetColor rule), "neighborColor" .= colorName (neighborColor rule)
      , "counts" .= Set.toList (neighborCounts rule), "enabled" .= enabled rule ]

positionJson :: (Int,Int) -> Value
positionJson (x,y) = object ["x" .= x,"y" .= y]
parsePosition :: Value -> Parser (Int,Int)
parsePosition = withObject "cell coordinate" $ \v -> do
  p <- (,) <$> v .: "x" <*> v .: "y"
  unless (Language.validPosition p) (fail "Cell is outside A1 to P16")
  pure p
rankingJson :: D.SalienceRanking -> Value
rankingJson r = toJSON [object ["entry" .= e,"utterance" .= u,"position" .= positionJson p,
  "properties" .= [object ["kind" .= ("defined" :: String),"value" .= value] | Defined value <- facts]]
  | ((e,u),D.SquareReferent p,facts) <- r]
parseRanking :: Value -> Parser D.SalienceRanking
parseRanking = withArray "cell salience" $ mapM mention . foldr (:) []
  where
    mention = withObject "cell mention" $ \v -> do
      e <- v .: "entry"; u <- v .: "utterance"
      identifier <- v .:? "objectId" :: Parser (Maybe Int)
      unless (e>=0 && u>=0 && identifier==Nothing) (fail "Invalid cell mention")
      p <- v .: "position" >>= parsePosition
      facts <- v .: "properties" >>= mapM property
      pure ((e,u),D.SquareReferent p,facts)
    property = withObject "cell fact" $ \v -> do
      kind <- v .: "kind" :: Parser String
      source <- v .: "value"
      let stored = Defined source
      unless (kind=="defined" && maybe False Language.validGroundCondition (Language.readFact stored)) (fail "Invalid cellular fact")
      pure stored

processRequest :: Value -> Either String Value
processRequest input = do
  (world,originalWorld,r,paused,action,seed) <- parseEither (withObject "cellular request" $ \v -> do
    version <- v .:? "languageVersion" .!= ("cellular-v2" :: String)
    unless (version == "cellular-v2") (fail "Unsupported cellular version")
    counter <- v .:? "nextObjectId" .!= (0 :: Int)
    unless (counter == 0) (fail "Cellular worlds do not allocate object identifiers")
    original <- v .: "world"
    world <- parseWorld original
    r <- v .:? "salience" .!= Array mempty >>= parseRanking
    paused <- v .:? "pending" :: Parser (Maybe Value)
    action <- v .: "action"
    seed <- withObject "action" (\a -> a .:? "randomSeed" .!= (0 :: Word64)) action
    pure (world,original,r,paused,action,seed)) input
  kind <- parseEither (withObject "action" (.: "type")) action :: Either String String
  let reply :: Automaton -> D.SalienceRanking -> Maybe Value -> String -> Bool -> Bool -> Bool -> Value
      reply next ranking pending feedback failed syntax undo = object
        [ "domain" .= ("cellular" :: String),"languageVersion" .= ("cellular-v2" :: String)
        , "world" .= (if next==world then originalWorld else worldJson next),"nextObjectId" .= (0 :: Int)
        , "salience" .= rankingJson ranking,"pending" .= pending,"feedback" .= feedback
        , "changedCells" .= Language.changedCount world next,"changes" .= ([] :: [Value])
        , "isError" .= failed,"syntaxError" .= syntax,"undoRequested" .= undo ]
      unchanged message failed syntax undo = reply world r paused message failed syntax undo
      groupingPending entries frozenSeed =
        let sources = map Language.entryText entries
            pending = object ["sentence" .= ("Choose Boolean grouping" :: String),"remaining" .= ("" :: String),
              "candidateIds" .= ([] :: [Int]),"candidates" .= ([] :: [Value]),"squareChoices" .= ([] :: [Value]),
              "groupingChoices" .= [object ["groupingId" .= n,"label" .= source] | (n,source) <- zip [1::Int ..] sources],
              "payload" .= object ["version" .= ("cellular-v2-grouping" :: String),"alternatives" .= sources,"randomSeed" .= frozenSeed]]
        in reply world r (Just pending) "Which grouping? Nothing was applied." False False False
      evaluate source start startRanking frozenSeed choices completed = case Language.parseEntryAlternatives source of
        Left message -> unchanged message True True False
        Right [entry] ->
          let result = Language.runEntry start startRanking frozenSeed entry choices completed
              pending = case Language.resultPause result of
                Nothing -> Nothing
                Just (count,sentence,ps) -> Just (object
                  ["sentence" .= sentence,"remaining" .= Language.entryText entry,
                   "candidateIds" .= ([] :: [Int]),"candidates" .= ([] :: [Value]),"squareChoices" .= map positionJson ps,
                   "stagedWorld" .= fmap worldJson (Language.stagedWorld result),
                   "payload" .= object ["version" .= ("cellular-v2" :: String),"source" .= Language.entryText entry,
                     "world" .= worldJson start,"salience" .= rankingJson startRanking,"randomSeed" .= frozenSeed,
                     "choices" .= map positionJson choices,"completed" .= count]])
          in reply (Language.resultWorld result) (Language.resultRanking result) pending
               (Language.resultFeedback result) (Language.resultError result) False False
        Right entries -> groupingPending entries frozenSeed
      resume = case paused of
        Nothing -> Right (unchanged "No clarification pending" True False False)
        Just pending -> do
          (ps,payload) <- parseEither (withObject "pending" $ \p -> (,) <$> (p .:? "squareChoices" .!= [] >>= mapM parsePosition) <*> p .: "payload") pending
          (version,frozenSeed) <- parseEither (withObject "continuation" $ \v -> (,) <$> v .: "version" <*> v .: "randomSeed") payload
          if version == ("cellular-v2-grouping" :: String) then do
            alternatives <- parseEither (withObject "grouping" (.: "alternatives")) payload
            n <- parseEither (withObject "choice" (.: "groupingId")) action
            if n>=1 && n<=length alternatives
              then Right (evaluate (alternatives !! (n-1)) world r frozenSeed [] 0)
              else Right (unchanged "Choose one of the listed groupings" True False False)
          else do
            unless (version=="cellular-v2") (Left "Unsupported cellular continuation")
            p <- parseEither (withObject "choice" (\a -> a .: "position" >>= parsePosition)) action
            if p `notElem` ps then Right (unchanged "Choose one of the listed cells" True False False) else do
              (source,start,startRanking,choices,completed) <- parseEither (withObject "continuation" $ \v -> do
                source <- v .: "source"; start <- v .: "world" >>= parseWorld
                sr <- v .: "salience" >>= parseRanking
                cs <- v .: "choices" >>= mapM parsePosition
                count <- v .: "completed"
                unless (count>=0) (fail "Invalid continuation offset")
                pure (source,start,sr,cs,count)) payload
              Right (evaluate source start startRanking frozenSeed (choices++[p]) completed)
  case kind of
    "chat" -> do
      source <- parseEither (withObject "chat" (.: "text")) action
      Right $ if Language.parseEntry source == Right Language.Undo then unchanged "" False False True
        else if paused /= Nothing then unchanged "Choose a cell or grouping, or undo" True False False
        else evaluate source world r seed [] 0
    "clarify" -> resume
    "checkSyntax" -> do
      source <- parseEither (withObject "syntax check" (.: "text")) action
      Right $ case Language.parseEntryAlternatives source of
        Left message -> unchanged message True True False
        Right entries -> unchanged (unlines (map Language.entryText entries)) False False False
    _ | paused /= Nothing -> Right (unchanged "Choose a cell or grouping, or undo" True False False)
    _ -> do
      operation <- parseEither parseAction action
      (next,feedback) <- case operation of
        Step -> do
          (next,n) <- Cellular.step world
          pure (next,"Generation " ++ show (generation next) ++ ": " ++ show n ++ " cells changed")
        PaintCell position color -> do
          (next,n) <- Cellular.paintCell world position color
          pure (next,if n==0 then "No change" else Language.positionText position ++ ": " ++ colorName (cells world Map.! position) ++ " -> " ++ colorName color)
        ReplaceRuleset config refillSeed -> do
          (next,n) <- Cellular.replaceRuleset world config refillSeed
          pure (next,if next==world then "No change" else if n>0 || generation next /= generation world then "Ruleset updated; board randomly refilled (generation 0)" else "Ruleset updated")
      Right (reply next (Language.purgeRanking next r) Nothing feedback False False False)

module Layer2Parser (parseSentence, parseSentences) where

import Control.Applicative (some, (<|>))
import Data.Char (isSpace, toLower, ord, isDigit)
import Data.Maybe (mapMaybe)
import Data.Void (Void)
import Text.Read (readMaybe)
import Text.Megaparsec (Parsec, parse, eof, errorBundlePretty, takeWhile1P, oneOf)
import Text.Megaparsec.Char (space)
import Ontology
import AtomicPropertyQuery
import Layer2Syntax

type Parser = Parsec Void String

-- Megaparsec handles entry boundaries and locations; the finite sentence grammar
-- enumerates legal subject boundaries and rejects multiple complete parses.
entry :: Parser [([String], Maybe Char)]
entry = space *> some sentenceTokens <* eof
  where
    word = map toLower <$> takeWhile1P (Just "word") (\c -> not (isSpace c) && c /= '.' && c /= '?') <* space
    sentenceTokens = do
      words' <- some word
      mark <- (Just <$> oneOf ".?" <* space) <|> (Nothing <$ eof)
      pure (words', mark)

parseSentences :: String -> Either String [Sentence]
parseSentences input = case parse entry "controlled English" input of
  Left message -> Left (errorBundlePretty message)
  Right chunks -> traverse parseChunk chunks

parseSentence :: String -> Either String Sentence
parseSentence input = do
  sentences <- parseSentences input
  case sentences of
    [sentence] -> Right sentence
    _ -> Left "Expected exactly one sentence"

descriptor :: String -> Maybe Property
descriptor word = lookup word
  [("red", C Red), ("blue", C Blue), ("green", C Green), ("yellow", C Yellow),
   ("small", S Small), ("medium", S Medium), ("large", S Large),
   ("cube", Sh Cube), ("sphere", Sh Sphere), ("pyramid", Sh Pyramid)]

attribute :: String -> Maybe Attribute
attribute word = lookup word
  [("color", ColorAttribute), ("size", SizeAttribute), ("shape", ShapeAttribute),
   ("position", PositionAttribute), ("row", RowAttribute), ("column", ColumnAttribute)]

square :: String -> Maybe Position
square [column, row] | column >= 'a' && column <= 'h' && row >= '1' && row <= '8' =
  Just (ord column - ord 'a', ord row - ord '1')
square _ = Nothing

reference :: String -> Maybe ObjectReference
reference ('#':digits) | not (null digits) && all isDigit digits = do
  number <- readMaybe digits :: Maybe Integer
  if number >= 0 && number <= toInteger (maxBound :: Int)
    then Just (ById (Id (fromInteger number))) else Nothing
reference word = AtSquare <$> square word

subject :: [String] -> Maybe Subject
subject ["it"] = Just It
subject [word] | Just ref <- reference word = Just (Reference ref)
subject ("the":words') = Definite <$> description words'
subject ("a":words') = Indefinite <$> description words'
subject words' = Indefinite <$> description words'

description :: [String] -> Maybe [Property]
description words' = case stripOne words' of
  [] -> Nothing
  descriptors -> traverse descriptor descriptors
  where
    stripOne tokens | not (null tokens) && last tokens == "one" = init tokens
    stripOne tokens = tokens

dropWord :: String -> [String] -> [String]
dropWord word (first:rest) | word == first = rest
dropWord _ words' = words'

destination :: [String] -> Maybe Property
destination words' = case dropWord "on" (dropWord "to" words') of
  [position] -> P <$> square position
  _ -> Nothing

-- A destination can occur once, only at the end of a predicate.
predicate :: [String] -> Maybe [Property]
predicate words' = let tokens = dropWord "a" (dropWord "to" (dropWord "is" words')) in
  case destination tokens of
    Just position -> Just [position]
    Nothing -> case span (\word -> descriptor word /= Nothing) tokens of
      ([], _) -> Nothing
      (descriptors, rest) -> do
        properties <- traverse descriptor descriptors
        case rest of
          [] -> Just properties
          _ -> (properties ++) . (:[]) <$> destination rest

splits :: [a] -> [([a], [a])]
splits tokens = [splitAt index tokens | index <- [1 .. length tokens - 1]]

isIndefinite :: Subject -> Bool
isIndefinite (Indefinite _) = True
isIndefinite _ = False

hasBoundary :: [String] -> Bool
hasBoundary (word:_) = word == "is" || word == "to"
hasBoundary _ = False

isPosition :: Property -> Bool
isPosition (P _) = True
isPosition _ = False

attribution :: [String] -> [Sentence]
attribution words' = mapMaybe candidate (splits tokens)
  where
    (verb, tokens) = case words' of
      "move":rest -> ("move", rest)
      "turn":rest -> ("turn", rest)
      _ -> ("", words')
    candidate (before, after) = do
      who <- subject before
      properties <- predicate after
      let positional = all isPosition properties
          namedBoundary = case who of
            Definite _ -> positional || hasBoundary after
            Indefinite _ -> positional || hasBoundary after
            _ -> True
      if not namedBoundary || (isIndefinite who && not (any isPosition properties))
        || (verb == "move" && not positional) || (verb == "turn" && positional)
        then Nothing else Just (Attribution who properties)

questions :: [String] -> [Sentence]
questions words' = valueQueries ++ checks
  where
    valueTokens = case words' of
      "what":"is":rest -> dropWord "the" rest
      _ -> words'
    valueQueries = case valueTokens of
      name:"of":rest -> maybe [] (:[]) $ do
        attr <- attribute name
        who <- subject rest
        if isIndefinite who then Nothing else Just (Query attr who)
      _ -> mapMaybe shorthand (splits words')
    shorthand (before, after) = do
      who <- subject before
      attr <- case dropWord "is" after of [name] -> attribute name; _ -> Nothing
      if isIndefinite who then Nothing else Just (Query attr who)
    (inverted, tokens) = case words' of "is":rest -> (True, rest); _ -> (False, words')
    checks = mapMaybe check (splits tokens)
    check (before, after) = do
      who <- subject before
      if isIndefinite who then Nothing else pure ()
      properties <- predicate after
      property <- case properties of [value] -> Just value; _ -> Nothing
      -- Preserve the core rule that positional 'to' is performative-only.
      if isPosition property && "to" `elem` after then Nothing else pure ()
      let boundary = case who of Definite _ -> inverted || hasBoundary after; _ -> True
      if boundary then Just (Check who property) else Nothing

parseChunk :: ([String], Maybe Char) -> Either String Sentence
parseChunk (tokens, mark) = case (if mark == Just '?' then questions tokens else attribution tokens) of
  [sentence] -> Right sentence
  [] -> Left ("Unsupported syntax: " ++ unwords tokens ++ maybe "" (:[]) mark)
  _ -> Left ("Ambiguous subject/predicate boundary: " ++ unwords tokens)

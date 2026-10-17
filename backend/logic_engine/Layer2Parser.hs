module Layer2Parser (parseSentence, parseSentences, parseSentenceWith, parseSentencesWith, isUndoEntry) where

import Control.Applicative (some, (<|>))
import Data.Char (isSpace, toLower)
import Data.List (isPrefixOf)
import Data.Maybe (mapMaybe)
import Data.Void (Void)
import Text.Megaparsec (Parsec, parse, eof, errorBundlePretty, takeWhile1P, oneOf)
import Text.Megaparsec.Char (space)
import Domain
import Ontology
import AtomicPerformative (RemovableAttribute(..))
import AtomicPropertyQuery
import SyntaxVocabulary
import DomainLibrary
import Domains.Objects.Library (objectsLibrary)
import Layer2Syntax

-- Undo is an entry-level request: all text following the prefix is ignored.
isUndoEntry :: String -> Bool
isUndoEntry = isPrefixOf "undo" . map toLower . dropWhile isSpace

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

parseSentencesWith :: DomainLibrary -> String -> Either String [Sentence]
parseSentencesWith library input = case parse entry "controlled English" input of
  Left message -> Left (errorBundlePretty message)
  Right chunks -> traverse (parseChunkWith library) chunks

parseSentenceWith :: DomainLibrary -> String -> Either String Sentence
parseSentenceWith library input = do
  sentences <- (parseSentencesWith library) input
  case sentences of
    [sentence] -> Right sentence
    _ -> Left "Expected exactly one sentence"

attributionWith :: Domain -> [String] -> [Sentence]
attributionWith domain words' = mapMaybe candidate (splits tokens)
  where
    (verb, tokens) = case words' of
      "move":rest -> ("move", rest)
      "turn":rest -> ("turn", rest)
      _ -> ("", words')
    candidate (before, after) = do
      who <- (subjectWith domain) before
      properties <- (predicateWith domain) after
      let canAttribute (Defined name) = any (\definition -> definedName definition == name && assignable definition) (domainDefined domain)
          canAttribute _ = True
      if all canAttribute properties && (case who of Indefinite descriptors -> all canAttribute descriptors; _ -> True)
        then pure () else Nothing
      let positional = all isPosition properties
          namedBoundary = case who of
            Definite _ -> positional || hasBoundary after
            Indefinite _ -> positional || hasBoundary after
            _ -> True
      if not namedBoundary || (isIndefinite who && not (any isPosition properties))
        || (verb == "move" && not positional) || (verb == "turn" && positional)
        then Nothing else Just (Attribution who properties)

-- Structural operands must denote existing objects. Description boundaries
-- are enumerated just like attribution boundaries, with optional 'and'.
structuralWith :: Domain -> [String] -> [Sentence]
structuralWith _ tokens | tokens `elem` [["clear","the","world"],["clear","everything"],["clear","all"]] = [ClearingWorld]
structuralWith domain ("remove":tokens) = (unaryWith domain) Removal (stripFromBoard tokens)
  where
    stripFromBoard words' = case reverse words' of
      "board":"from":rest -> reverse rest
      _ -> words'
structuralWith domain ("erase":tokens) = (unaryWith domain) Deletion tokens
structuralWith domain ("delete":tokens) = (unaryWith domain) Deletion tokens
structuralWith domain ("swap":tokens) = mapMaybe candidate (splits tokens)
  where
    candidate (before, after) = Swapping <$> (existingSubjectWith domain) before
                                          <*> (existingSubjectWith domain) (dropWord "and" after)
structuralWith domain tokens = mapMaybe candidate (splits tokens)
  where
    candidate (before, ["remove", name]) = do
      who <- (existingSubjectWith domain) before
      attr <- (removableWith domain) name
      pure (AttributeRemoval who attr)
    candidate _ = Nothing

questionsWith :: Domain -> [String] -> [Sentence]
questionsWith domain words' = squareQuestions ++ valueQueries ++ checks
  where
    squareQuestions = case dropWord "the" (dropWord "is" words') of
      ["square", coordinate, name] | name `elem` ["occupied", "taken"] ->
        maybe [] (pure . SquareOccupancy) (squareWith domain coordinate)
      _ -> []
    valueTokens = case words' of
      "what":"is":rest -> dropWord "the" rest
      _ -> words'
    valueQueries = case valueTokens of
      name:"of":rest -> maybe [] (:[]) $ do
        attr <- (attributeWith domain) name
        who <- (subjectWith domain) rest
        if isIndefinite who then Nothing else Just (Query attr who)
      _ -> mapMaybe shorthand (splits words')
    shorthand (before, after) = do
      who <- (subjectWith domain) before
      -- Unary descriptors are Boolean checks, not shorthand value queries.
      if any (\word -> descriptorWith domain word /= Nothing) after then Nothing else pure ()
      attr <- case dropWord "is" after of [name] -> (attributeWith domain) name; _ -> Nothing
      if isIndefinite who then Nothing else Just (Query attr who)
    (inverted, tokens) = case words' of "is":rest -> (True, rest); _ -> (False, words')
    checks = mapMaybe check (splits tokens)
    check (before, after) = do
      who <- (subjectWith domain) before
      if isIndefinite who then Nothing else pure ()
      properties <- (predicateWith domain) after
      property <- case properties of [value] -> Just value; _ -> Nothing
      -- Preserve the core rule that positional 'to' is performative-only.
      if isPosition property && "to" `elem` after then Nothing else pure ()
      let boundary = case who of Definite _ -> inverted || hasBoundary after; _ -> True
      if boundary then Just (Check who property) else Nothing

parseChunkWith :: DomainLibrary -> ([String], Maybe Char) -> Either String Sentence
parseChunkWith library (rawTokens, mark) = case candidates of
  [sentence] -> Right sentence
  [] -> Left ("Unsupported syntax: " ++ unwords tokens ++ maybe "" (:[]) mark)
  _ -> Left ("Ambiguous subject/predicate boundary: " ++ unwords tokens)
  where
    domain = ontology library
    tokens = normalizeTokens library rawTokens
    candidates = if mark == Just '?'
      then questionsWith domain tokens ++ parseDerivedQuestions library tokens
      else structuralWith domain tokens ++ attributionWith domain tokens ++ parseDerivedPerformatives library tokens

-- Current-domain convenience entry points.
parseSentences :: String -> Either String [Sentence]
parseSentences = parseSentencesWith objectsLibrary
parseSentence :: String -> Either String Sentence
parseSentence = parseSentenceWith objectsLibrary

module AtomicParser
  ( parseAtomicPerformative
  , parseAtomicPerformatives
  , atomicPerformative
  , parseAtomicSentence
  , parseAtomicSentences
  , atomicSentence
  , parseAtomicPerformativeWith
  , parseAtomicPerformativesWith
  , atomicPerformativeWith
  , parseAtomicSentenceWith
  , parseAtomicSentencesWith
  , atomicSentenceWith
  ) where

import Control.Applicative (optional, some, (<|>))
import Control.Monad (void, when)
import Data.Char (isAlphaNum, ord, toUpper)
import Data.Void (Void)
import Domain
import Domains.Objects.Definition (objectsDomain)
import Ontology
import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import AtomicSentence
import AtomicSquareCheck
import Text.Megaparsec
  ( Parsec, choice, eof, errorBundlePretty, notFollowedBy, oneOf
  , parse, satisfy, try, (<?>)
  )
import Text.Megaparsec.Char (char, space, space1, string')
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void String

-- Parse all input before returning any performatives. No world updates occur here.
parseAtomicPerformativesWith :: Domain -> String -> Either String [AtomicPerformative]
parseAtomicPerformativesWith domain = runParser (space *> some (atomicPerformativeWith domain) <* eof)

parseAtomicPerformativeWith :: Domain -> String -> Either String AtomicPerformative
parseAtomicPerformativeWith domain = runParser (space *> (atomicPerformativeWith domain) <* eof)

parseAtomicSentenceWith :: Domain -> String -> Either String AtomicSentence
parseAtomicSentenceWith domain = runParser (space *> (atomicSentenceWith domain) <* eof)

parseAtomicSentencesWith :: Domain -> String -> Either String [AtomicSentence]
parseAtomicSentencesWith domain = runParser (space *> some (atomicSentenceWith domain) <* eof)

runParser :: Parser a -> String -> Either String a
runParser parser input = case parse parser "controlled English" input of
  Left err -> Left (errorBundlePretty err)
  Right value -> Right value

atomicPerformativeWith :: Domain -> Parser AtomicPerformative
atomicPerformativeWith domain = do
  sentence <- (atomicSentenceWith domain)
  case sentence of
    Performative performative -> pure performative
    _ -> fail "expected a performative, not a question"

atomicSentenceWith :: Domain -> Parser AtomicSentence
atomicSentenceWith domain = (SquareCheck <$> try (atomicSquareCheckWith domain))
  <|> (structuralPerformativeWith domain) <|> (PropertyQuery <$> (atomicPropertyQueryWith domain)) <|> (atomicAssertionOrCheckWith domain)

atomicSquareCheckWith :: Domain -> Parser AtomicSquareCheck
atomicSquareCheckWith domain = do
  void (optional (keyword "is" *> space1))
  void (optional (keyword "the" *> space1))
  keyword "square" *> space1
  position <- positionParserWith domain
  space1 *> (keyword "occupied" <|> keyword "taken")
  questionEnd
  pure (ASC position)

structuralPerformativeWith :: Domain -> Parser AtomicSentence
structuralPerformativeWith domain = do
  performative <- removal <|> deletion <|> swapping
  mark <- sentenceEnd
  when (mark == Just '?') $ fail "structural operations are performative-only"
  pure (Performative performative)
  where
    removal = do
      keyword "remove" *> space1
      reference <- (referenceParserWith domain)
      void (optional (try (space1 *> keyword "from" *> space1 *> keyword "board")))
      pure (Remove reference)
    deletion = do
      (keyword "erase" <|> keyword "delete") *> space1
      Delete <$> (referenceParserWith domain)
    swapping = do
      keyword "swap" *> space1
      first <- (referenceParserWith domain)
      space1
      void (optional (keyword "and" *> space1))
      Swap first <$> (referenceParserWith domain)

atomicPropertyQueryWith :: Domain -> Parser AtomicPropertyQuery
atomicPropertyQueryWith domain = do
  attribute <- (attributeParserWith domain)
  space1
  keyword "of"
  space1
  reference <- (referenceParserWith domain)
  questionEnd
  pure (APQ attribute reference)

attributeParserWith :: Domain -> Parser Attribute
attributeParserWith domain = choice
  ([Stored identifier <$ keyword word | (word,identifier) <- attributeVocabulary domain] ++
   [PositionAttribute <$ keyword "position", RowAttribute <$ keyword "row", ColumnAttribute <$ keyword "column"])

questionEnd :: Parser ()
questionEnd = space *> void (char '?') *> space

referenceParserWith :: Domain -> Parser ObjectReference
referenceParserWith domain = (ById <$> identifierParser) <|> (AtSquare <$> (positionParserWith domain))

atomicAssertionOrCheckWith :: Domain -> Parser AtomicSentence
atomicAssertionOrCheckWith domain = do
  identifier <- (referenceParserWith domain)
  space1
  copula <- optional (keyword "is" *> space1)
  let removal = do
        keyword "remove"
        when (copula /= Nothing) $ fail "remove follows its subject directly"
        space1
        attribute <- choice
          ([RemoveStored identifier <$ keyword word | (word,identifier) <- attributeVocabulary domain] ++
           [RemoveSquare <$ keyword "square"])
        mark <- sentenceEnd
        when (mark == Just '?') $ fail "attribute removal is performative-only"
        pure (Performative (RemoveAttribute identifier attribute))
      shorthand = do
        attribute <- choice
          ([Stored name <$ keyword word | (word,name) <- attributeVocabulary domain,
            lookup word (descriptorVocabulary domain) == Nothing] ++
           [PositionAttribute <$ keyword "position", RowAttribute <$ keyword "row", ColumnAttribute <$ keyword "column"])
        questionEnd
        pure (PropertyQuery (APQ attribute identifier))
      move = do
        keyword "to"
        space1
        position <- (positionParserWith domain)
        mark <- sentenceEnd
        when (mark == Just '?') $ fail "to is performative-only"
        pure (Performative (AP identifier (P position)))
      assertion = do
        property <- (keyword "on" *> space1 *> (P <$> (positionParserWith domain))) <|> (propertyParserWith domain)
        mark <- sentenceEnd
        pure $ case mark of
          Just '?' -> PropertyCheck (APC identifier property)
          _ -> Performative (AP identifier property)
  removal <|> shorthand <|> move <|> assertion

sentenceEnd :: Parser (Maybe Char)
sentenceEnd = do
  space
  mark <- (Just <$> oneOf ".?")
    <|> (Nothing <$ eof)
  space
  pure mark

identifierParser :: Parser Identifier
identifierParser = do
  void (char '#')
  number <- L.decimal :: Parser Integer
  when (number > toInteger (maxBound :: Int)) $
    fail "object identifier exceeds the supported integer range"
  pure (Id (fromInteger number))

keyword :: String -> Parser ()
keyword word = try $ void (string' word) <* notFollowedBy (satisfy isAlphaNum)

propertyParserWith :: Domain -> Parser Property
propertyParserWith domain = choice
  ([property <$ keyword word | (word,property) <- descriptorVocabulary domain] ++
   [P <$> (positionParserWith domain)]) <?> "property or grid square"

positionParserWith :: Domain -> Parser Position
positionParserWith domain = do
  column <- oneOf (take (boardWidth domain) ['A'..'Z'] ++ take (boardWidth domain) ['a'..'z'])
  notFollowedBy (char '0')
  row <- L.decimal :: Parser Integer
  when (row < 1 || row > toInteger (boardHeight domain)) $ fail "row outside board"
  notFollowedBy (satisfy isAlphaNum)
  pure (ord (toUpper column) - ord 'A', fromInteger row - 1)

-- Current-domain convenience entry points.
parseAtomicPerformative :: String -> Either String AtomicPerformative
parseAtomicPerformative = parseAtomicPerformativeWith objectsDomain
parseAtomicPerformatives :: String -> Either String [AtomicPerformative]
parseAtomicPerformatives = parseAtomicPerformativesWith objectsDomain
atomicPerformative :: Parser AtomicPerformative
atomicPerformative = atomicPerformativeWith objectsDomain
parseAtomicSentence :: String -> Either String AtomicSentence
parseAtomicSentence = parseAtomicSentenceWith objectsDomain
parseAtomicSentences :: String -> Either String [AtomicSentence]
parseAtomicSentences = parseAtomicSentencesWith objectsDomain
atomicSentence :: Parser AtomicSentence
atomicSentence = atomicSentenceWith objectsDomain

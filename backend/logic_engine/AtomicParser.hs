module AtomicParser
  ( parseAtomicPerformative
  , parseAtomicPerformatives
  , atomicPerformative
  , parseAtomicSentence
  , parseAtomicSentences
  , atomicSentence
  ) where

import Control.Applicative (optional, some, (<|>))
import Control.Monad (void, when)
import Data.Char (digitToInt, isAlphaNum, ord, toUpper)
import Data.Void (Void)
import Ontology
import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import AtomicSentence
import Text.Megaparsec
  ( Parsec, choice, eof, errorBundlePretty, notFollowedBy, oneOf
  , parse, satisfy, try, (<?>)
  )
import Text.Megaparsec.Char (char, space, space1, string')
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void String

-- Parse all input before returning any performatives. No world updates occur here.
parseAtomicPerformatives :: String -> Either String [AtomicPerformative]
parseAtomicPerformatives = runParser (space *> some atomicPerformative <* eof)

parseAtomicPerformative :: String -> Either String AtomicPerformative
parseAtomicPerformative = runParser (space *> atomicPerformative <* eof)

parseAtomicSentence :: String -> Either String AtomicSentence
parseAtomicSentence = runParser (space *> atomicSentence <* eof)

parseAtomicSentences :: String -> Either String [AtomicSentence]
parseAtomicSentences = runParser (space *> some atomicSentence <* eof)

runParser :: Parser a -> String -> Either String a
runParser parser input = case parse parser "controlled English" input of
  Left err -> Left (errorBundlePretty err)
  Right value -> Right value

atomicPerformative :: Parser AtomicPerformative
atomicPerformative = do
  sentence <- atomicSentence
  case sentence of
    Performative performative -> pure performative
    _ -> fail "expected a performative, not a question"

atomicSentence :: Parser AtomicSentence
atomicSentence = (PropertyQuery <$> atomicPropertyQuery) <|> atomicAssertionOrCheck

atomicPropertyQuery :: Parser AtomicPropertyQuery
atomicPropertyQuery = do
  attribute <- attributeParser
  space1
  keyword "of"
  space1
  reference <- referenceParser
  questionEnd
  pure (APQ attribute reference)

attributeParser :: Parser Attribute
attributeParser = choice
    [ ColorAttribute <$ keyword "color", SizeAttribute <$ keyword "size"
    , ShapeAttribute <$ keyword "shape", PositionAttribute <$ keyword "position"
    , RowAttribute <$ keyword "row", ColumnAttribute <$ keyword "column"
    ]

questionEnd :: Parser ()
questionEnd = space *> void (char '?') *> space

referenceParser :: Parser ObjectReference
referenceParser = (ById <$> identifierParser) <|> (AtSquare <$> positionParser)

atomicAssertionOrCheck :: Parser AtomicSentence
atomicAssertionOrCheck = do
  identifier <- referenceParser
  space1
  void (optional (keyword "is" *> space1))
  let shorthand = do
        attribute <- attributeParser
        questionEnd
        pure (PropertyQuery (APQ attribute identifier))
      move = do
        keyword "to"
        space1
        position <- positionParser
        mark <- sentenceEnd
        when (mark == Just '?') $ fail "to is performative-only"
        pure (Performative (AP identifier (P position)))
      assertion = do
        property <- (keyword "on" *> space1 *> (P <$> positionParser)) <|> propertyParser
        mark <- sentenceEnd
        pure $ case mark of
          Just '?' -> PropertyCheck (APC identifier property)
          _ -> Performative (AP identifier property)
  shorthand <|> move <|> assertion

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

propertyParser :: Parser Property
propertyParser = choice
  [ C Blue <$ keyword "blue", C Green <$ keyword "green"
  , C Red <$ keyword "red", C Yellow <$ keyword "yellow"
  , S Small <$ keyword "small", S Medium <$ keyword "medium"
  , S Large <$ keyword "large"
  , Sh Cube <$ keyword "cube", Sh Sphere <$ keyword "sphere"
  , Sh Pyramid <$ keyword "pyramid"
  , P <$> positionParser
  ] <?> "color, size, shape, or square A1-H8"

positionParser :: Parser Position
positionParser = do
  column <- oneOf (['A'..'H'] ++ ['a'..'h'])
  row <- oneOf ['1'..'8']
  notFollowedBy (satisfy isAlphaNum)
  pure (ord (toUpper column) - ord 'A', digitToInt row - 1)

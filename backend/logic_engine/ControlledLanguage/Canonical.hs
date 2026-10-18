module ControlledLanguage.Canonical (parseCanonicalWith) where

import Control.Monad (void, when)
import Data.Char (ord)
import Data.Void (Void)
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L
import ControlledLanguage.Grammar
import Domain (Domain, domainId)
import ControlledLanguage.Syntax

type Parser = Parsec Void String
sc :: Parser ()
sc = L.space space1 empty empty
symbol :: String -> Parser String
symbol = L.symbol sc
word :: String -> Parser ()
word text = void $ lexeme $ try (string' text <* notFollowedBy alphaNumChar)
lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc
integer :: Bool -> Parser Int
integer signed = lexeme $ do
  negative <- if signed then optional (char '-') else pure Nothing
  digits <- some digitChar
  notFollowedBy alphaNumChar
  case digits of '0':_:_ -> fail "Leading zeroes are not canonical"; _ -> pure ()
  let n = read digits :: Integer
      value = if negative == Just '-' then negate n else n
  when (negative == Just '-' && n == 0) (fail "Negative zero is not canonical")
  when (value < toInteger (minBound :: Int) || value >= toInteger (maxBound :: Int)) (fail "Integer outside supported range")
  pure (fromInteger value)
identifier :: Parser Int
identifier = char '#' *> integer False
cell :: Parser (Int,Int)
cell = lexeme $ try $ do
  col <- oneOf "ABCDEFGHabcdefgh"
  row <- oneOf "12345678"
  notFollowedBy alphaNumChar
  pure ((ord col - if col >= 'a' then ord 'a' else ord 'A'), ord row - ord '1')
rowNumber :: Parser Int
rowNumber = do n <- integer False; when (n < 1 || n > 8) (fail "Row outside board"); pure (n-1)
columnNumber :: Parser Int
columnNumber = lexeme $ do c <- oneOf "ABCDEFGHabcdefgh"; notFollowedBy alphaNumChar; pure (ord c - if c >= 'a' then ord 'a' else ord 'A')

parseCanonicalWith :: Domain -> String -> Either String Entry
parseCanonicalWith domain = either (Left . errorBundlePretty) Right . parse parser (domainId domain ++ " language v2")
  where
    parser = entryGrammar domain (Backend sc symbol word integer identifier cell rowNumber columnNumber try eof) False

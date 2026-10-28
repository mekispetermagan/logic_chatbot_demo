module ControlledLanguage.Parser (parseEntryWith, parseEntryAlternativesWith, parseCanonicalWith) where

import Control.Applicative ((<|>))
import Control.Monad (void, when)
import Data.Char (isAlphaNum, isDigit, ord, toLower)
import Data.List (nub)
import qualified Text.ParserCombinators.ReadP as R
import ControlledLanguage.Canonical (parseCanonicalWith)
import ControlledLanguage.Parsing
import ControlledLanguage.Grammar
import ControlledLanguage.Pretty (entryText, canonicalEntryText)
import Domain (Domain, domainId)
import ControlledLanguage.Syntax

-- Surface normalization is grammar driven. ReadP retains every complete reading;
-- canonical parsing then validates the fully delimited form of each one.
parseEntryAlternativesWith :: Domain -> String -> Either String [Entry]
parseEntryAlternativesWith domain source = case nub [entry | (entry, "") <- R.readP_to_S parser source] of
  [] -> Left (diagnose (domainId domain) (entryGrammar domain surfaceBackend True) source)
  readings -> traverse (parseCanonicalWith domain . canonicalEntryText) readings
  where parser = entryGrammar domain surfaceBackend True

-- Callers that cannot ask for clarification must explicitly group ambiguous input.
parseEntryWith :: Domain -> String -> Either String Entry
parseEntryWith domain source = do
  readings <- parseEntryAlternativesWith domain source
  case readings of
    [entry] -> Right entry
    _ -> Left ("Which grouping?\n" ++ unlines [show n ++ ". " ++ entryText entry | (n,entry) <- zip [1::Int ..] readings])

surfaceBackend :: Parsing p => Backend p
surfaceBackend = Backend skipSpaces symbol word integer identifier cell rowNumber columnNumber id eof
  where
    lexeme p = p <* skipSpaces
    symbol = lexeme . string
    boundary = do rest <- look; ensure (case rest of c:_ -> not (isAlphaNum c); _ -> True) "Expected a word boundary."
    word text = keywordToken text $ lexeme $ void (traverse (\c -> satisfy ((== toLower c) . toLower)) text) <* boundary
    integer signed = lexeme $ do
      negative <- if signed then (True <$ char '-') <|> pure False else pure False
      digits <- munch1 isDigit
      boundary
      case digits of '0':_:_ -> fail "Leading zeroes are not allowed."; _ -> pure ()
      let magnitude = read digits :: Integer
          value = if negative then negate magnitude else magnitude
      when ((negative && magnitude == 0) || value < toInteger (minBound :: Int) || value >= toInteger (maxBound :: Int)) (fail "Integer outside supported range, or negative zero.")
      pure (fromInteger value)
    identifier = char '#' *> integer False
    cell = labelled "a board coordinate A1–H8" $ lexeme $ do
      col <- satisfy (`elem` "ABCDEFGHabcdefgh")
      row <- satisfy (`elem` "12345678")
      boundary
      pure (ord (toLower col) - ord 'a', ord row - ord '1')
    rowNumber = do n <- integer False; when (n < 1 || n > 8) (fail "Row must be between 1 and 8."); pure (n-1)
    columnNumber = lexeme $ do c <- satisfy (`elem` "ABCDEFGHabcdefgh"); boundary; pure (ord (toLower c) - ord 'a')

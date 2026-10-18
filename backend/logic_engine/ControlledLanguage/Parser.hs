module ControlledLanguage.Parser (parseEntryWith, parseEntryAlternativesWith, parseCanonicalWith) where

import Control.Applicative ((<|>))
import Control.Monad (void, when)
import Data.Char (isAlphaNum, isDigit, ord, toLower)
import Data.List (nub)
import qualified Text.ParserCombinators.ReadP as R
import ControlledLanguage.Canonical (parseCanonicalWith)
import ControlledLanguage.Grammar
import ControlledLanguage.Pretty (entryText, canonicalEntryText)
import Domain (Domain)
import ControlledLanguage.Syntax

-- Surface normalization is grammar driven. ReadP retains every complete reading;
-- canonical parsing then validates the fully delimited form of each one.
parseEntryAlternativesWith :: Domain -> String -> Either String [Entry]
parseEntryAlternativesWith domain source = case nub [entry | (entry, "") <- R.readP_to_S parser source] of
  [] -> case parseCanonicalWith domain source of
    Left diagnostic -> Left diagnostic
    Right _ -> Left "Invalid controlled language surface syntax"
  readings -> traverse (parseCanonicalWith domain . canonicalEntryText) readings
  where parser = entryGrammar domain surfaceBackend True

-- Callers that cannot ask for clarification must explicitly group ambiguous input.
parseEntryWith :: Domain -> String -> Either String Entry
parseEntryWith domain source = do
  readings <- parseEntryAlternativesWith domain source
  case readings of
    [entry] -> Right entry
    _ -> Left ("Which grouping?\n" ++ unlines [show n ++ ". " ++ entryText entry | (n,entry) <- zip [1::Int ..] readings])

surfaceBackend :: Backend R.ReadP
surfaceBackend = Backend R.skipSpaces symbol word integer identifier cell rowNumber columnNumber id R.eof
  where
    lexeme p = p <* R.skipSpaces
    symbol = lexeme . R.string
    boundary = do rest <- R.look; case rest of c:_ | isAlphaNum c -> R.pfail; _ -> pure ()
    word text = lexeme $ void (traverse (\c -> R.satisfy ((== toLower c) . toLower)) text) <* boundary
    integer signed = lexeme $ do
      negative <- if signed then (True <$ R.char '-') <|> pure False else pure False
      digits <- R.munch1 isDigit
      boundary
      case digits of '0':_:_ -> R.pfail; _ -> pure ()
      let magnitude = read digits :: Integer
          value = if negative then negate magnitude else magnitude
      when ((negative && magnitude == 0) || value < toInteger (minBound :: Int) || value >= toInteger (maxBound :: Int)) R.pfail
      pure (fromInteger value)
    identifier = R.char '#' *> integer False
    cell = lexeme $ do
      col <- R.satisfy (`elem` "ABCDEFGHabcdefgh")
      row <- R.satisfy (`elem` "12345678")
      boundary
      pure (ord (toLower col) - ord 'a', ord row - ord '1')
    rowNumber = do n <- integer False; when (n < 1 || n > 8) R.pfail; pure (n-1)
    columnNumber = lexeme $ do c <- R.satisfy (`elem` "ABCDEFGHabcdefgh"); boundary; pure (ord (toLower c) - ord 'a')

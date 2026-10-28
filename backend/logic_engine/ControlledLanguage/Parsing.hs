{-# LANGUAGE FlexibleInstances, GeneralizedNewtypeDeriving #-}
-- Shared primitives: ReadP enumerates readings; Diagnostic only explains rejection.
module ControlledLanguage.Parsing where

import Control.Applicative (Alternative(empty, (<|>)))
import qualified Control.Applicative as A
import Control.Monad (void)
import Control.Monad.State.Strict (State, runState, modify, lift)
import qualified Data.List.NonEmpty as NE
import qualified Text.ParserCombinators.ReadP as R
import qualified Text.Megaparsec as M
import Data.Void (Void)
import Data.Char (isSpace, isAlphaNum)
import qualified Data.Set as Set

class (Monad p, MonadFail p, Alternative p) => Parsing p where
  satisfy :: (Char -> Bool) -> p Char
  look :: p String
  gather :: p a -> p (String,a)
  labelled :: String -> p a -> p a
  keywordToken :: String -> p a -> p a
  eof :: p ()
  string :: String -> p String
  string s = labelled (show s) (traverse char s)
  many :: p a -> p [a]
  many = A.many
  many1 :: p a -> p [a]
  many1 = A.some
  skipSpaces :: p ()
  skipSpaces = void (many (satisfy isSpace))
  munch1 :: (Char -> Bool) -> p String
  munch1 = A.some . satisfy

instance Parsing R.ReadP where
  satisfy = R.satisfy
  look = R.look
  gather = R.gather
  labelled _ = id
  keywordToken _ = id
  eof = R.eof
  string = R.string
  many = R.many
  many1 = R.many1
  skipSpaces = R.skipSpaces
  munch1 = R.munch1

newtype Diagnostic a = Diagnostic { diagnosticParser :: M.ParsecT Void String (State (Maybe (M.ParseError String Void))) a }
  deriving (Functor, Applicative, Monad, MonadFail)
-- ReadP alternatives backtrack unconditionally. Match that surface behaviour
-- during diagnosis, without using this backend to select accepted readings.
instance Alternative Diagnostic where
  empty = Diagnostic empty
  Diagnostic a <|> Diagnostic b = Diagnostic $ do
    result <- M.observing (M.try a)
    case result of
      Right value -> pure value
      Left failure -> lift (modify (Just . maybe failure (<> failure))) *> b
instance Parsing Diagnostic where
  satisfy = Diagnostic . M.satisfy
  look = Diagnostic M.getInput
  gather (Diagnostic p) = Diagnostic (M.match p)
  labelled name (Diagnostic p) = Diagnostic (M.label name p)
  -- A misspelled keyword fails at its start, with its complete expected name.
  -- Do not retain a character-level mismatch farther into the same token.
  keywordToken name (Diagnostic p) = Diagnostic $ do
    result <- M.observing (M.try p)
    case result of
      Right value -> pure value
      Left _ -> do
        rest <- M.getInput
        let token = case span isAlphaNum rest of
              ([], _) -> take 1 rest
              (word, _) -> word
            unexpected = case NE.nonEmpty token of
              Nothing -> M.EndOfInput
              Just characters -> M.Tokens characters
        M.failure (Just unexpected) (Set.singleton (M.Label (NE.fromList (show name))))
  eof = Diagnostic M.eof
  skipSpaces = Diagnostic (void (M.takeWhileP Nothing isSpace))
  munch1 predicate = Diagnostic (M.takeWhile1P Nothing predicate)

char :: Parsing p => Char -> p Char
char c = labelled (show c) (satisfy (==c))
get :: Parsing p => p Char
get = labelled "a character" (satisfy (const True))
count :: Applicative p => Int -> p a -> p [a]
count n p = sequenceA (replicate n p)
choice :: Alternative p => [p a] -> p a
choice = foldr (<|>) empty
option :: Alternative p => a -> p a -> p a
option x p = p <|> pure x
sepBy1 :: Parsing p => p a -> p sep -> p [a]
sepBy1 p sep = (:) <$> p <*> many (sep *> p)
sepBy :: Parsing p => p a -> p sep -> p [a]
sepBy p sep = sepBy1 p sep <|> pure []
between :: Applicative p => p open -> p close -> p a -> p a
between a b p = a *> p <* b
pfail :: Alternative p => p a
pfail = empty
ensure :: MonadFail p => Bool -> String -> p ()
ensure True _ = pure ()
ensure False message = fail message

-- The underlying State retains failures even when an optional branch succeeds
-- after backtracking. Megaparsec hints alone can lose those deeper failures.
-- A successful diagnostic pass can never override a ReadP rejection.
diagnose :: String -> Diagnostic a -> String -> String
diagnose domain parser source =
  let (result, furthest) = runState (M.runParserT (diagnosticParser parser) (domain ++ " controlled English") source) Nothing
  in case result of
    Left errors ->
      let final = foldr1 (<>) (NE.toList (M.bundleErrors errors))
          best = maybe final (<> final) furthest
      in M.errorBundlePretty errors { M.bundleErrors = best NE.:| [] }
    Right _ -> "Invalid " ++ domain ++ " controlled English; no complete reading was accepted."

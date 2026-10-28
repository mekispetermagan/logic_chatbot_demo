{-# LANGUAGE NoMonomorphismRestriction, FlexibleContexts #-}
module Domains.Cellular.Language.Parser (parseEntry, parseEntryAlternatives) where

import Control.Applicative ((<|>))
import Control.Monad (guard)
import Data.Char (isAlphaNum, isDigit, ord, toLower)
import Data.List (nub)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Text.ParserCombinators.ReadP as R
import ControlledLanguage.Parsing
import Domains.Cellular.Types
import Domains.Cellular.Language.Syntax
import Domains.Cellular.Language.Pretty (entryText)

parseEntryAlternatives :: String -> Either String [Entry]
parseEntryAlternatives source = case nub [e | (e,"") <- R.readP_to_S (skipSpaces *> entry <* eof) source] of
  [] -> Left (diagnose "Cellular" (skipSpaces *> entry <* eof) source)
  xs -> Right xs
parseEntry :: String -> Either String Entry
parseEntry source = do
  xs <- parseEntryAlternatives source
  case xs of
    [x] -> Right x
    _ -> Left ("Which grouping?\n" ++ unlines (map entryText xs))

lexeme :: Parsing p => p a -> p a
lexeme p = p <* skipSpaces
symbol :: Parsing p => String -> p String
symbol = lexeme . string
word :: Parsing p => String -> p ()
word text = keywordToken text $ lexeme $ do
  _ <- traverse (\c -> satisfy ((==c) . toLower)) text
  rest <- look
  guard (case rest of c:_ -> not (isAlphaNum c); [] -> True)
phrase :: Parsing p => String -> p ()
phrase = mapM_ word . words
options :: Parsing p => [(String,a)] -> p a
options = choice . map (\(s,a) -> a <$ phrase s)
number :: Parsing p => Bool -> p Int
number signed = lexeme $ do
  negative <- (True <$ char '-' <* guard signed) <|> pure False
  digits <- munch1 isDigit
  rest <- look
  guard (case rest of c:_ -> not (isAlphaNum c); [] -> True)
  ensure (case digits of '0':_:_ -> False; _ -> True) "Leading zeroes are not allowed in a number."
  let n = read digits :: Integer
      value = if negative then negate n else n
  ensure (not (negative && n == 0) && value >= toInteger (minBound :: Int) && value <= toInteger (maxBound :: Int)) "Integer outside supported range, or negative zero."
  pure (fromInteger value)
boundedNumber :: Parsing p => Int -> Int -> p Int
boundedNumber lo hi = do n <- number False; ensure (n>=lo && n<=hi) ("Number must be between "++show lo++" and "++show hi++"."); pure n
square :: Parsing p => p (Int,Int)
square = labelled "a cell coordinate A1–P16" $ lexeme $ do
  c <- satisfy (\c -> toLower c `elem` ['a'..'p'])
  n <- boundedNumber 1 16
  pure (ord (toLower c)-ord 'a',n-1)
color :: Parsing p => p Color
color = options [(map toLower (show c),c) | c <- [minBound..maxBound]]
mode :: Parsing p => p Neighborhood
mode = options [("moore",Moore),("von neumann",Orthogonal)]
boolean :: Parsing p => p Bool
boolean = options [("true",True),("false",False)]
brackets :: Parsing p => p a -> p a
brackets p = symbol "[" *> p <* symbol "]"
uniqueList :: (Parsing p, Eq a) => p a -> p [a]
uniqueList p = do xs <- brackets (sepBy p (symbol ",")); ensure (length xs == length (nub xs)) "List entries must not be repeated."; pure xs
counts :: Parsing p => p [Int]
counts = Set.toAscList . Set.fromList <$> uniqueList (boundedNumber 0 8)
rule :: Parsing p => p Rule
rule = do
  phrase "target"; c <- color; symbol ","; word "counts"; ns <- counts
  symbol ","; word "enabled"; active <- boolean
  pure (Rule c c (Set.fromList ns) active)
config :: Parsing p => p Ruleset
config = options [("preset game of life",life),("preset rgb cycle",rgb)] <|> do
  word "palette"; cs <- uniqueList color; ensure (length cs >= 2) "A palette requires at least two colors."
  symbol ","; word "neighborhood"; n <- mode; symbol ","; word "rules"
  rs <- brackets (sepBy ((,) <$> (color <* symbol ":") <*> rule) (symbol ","))
  ensure (length rs == length (nub (map fst rs))) "Each source color may have only one rule."
  let r = Ruleset (Set.fromList cs) n (Map.fromList rs)
  either fail pure (validateRuleset r)
  where
    make c ns = Rule c c (Set.fromList ns) True
    life = Ruleset (Set.fromList [White,Black]) Moore (Map.fromList [(White,make Black [3]),(Black,make White [0,1,2,3,4,7,8])])
    rgb = Ruleset (Set.fromList [Red,Green,Blue]) Moore (Map.fromList [(Red,make Green [2..8]),(Green,make Blue [2..8]),(Blue,make Red [2..8])])
baseReference :: Parsing p => p Reference
baseReference = (Cell <$> square) <|> (It <$ word "it") <|> (WithColor <$> (phrase "the cell with color" *> color))
reference :: Parsing p => p Reference
reference = baseReference <|> (Matching False <$> (phrase "the cell matching" *> cellCondition True))
  <|> (Matching True <$> (phrase "the unique cell matching" *> cellCondition True))
  <|> (Relative <$> (phrase "the cell" *> options [(d,d) | d <- ["north","east","south","west"]]) <*> (word "of" *> baseReference))

-- Enumerate scope instead of assigning operator precedence. Same-operator
-- associations normalize to one reading; explicit parentheses delimit a subtree.
condition :: (Parsing p, Eq a) => p a -> p (Condition a)
condition atom = do
  first <- primary
  rest <- many ((,) <$> options [("and",True),("or",False)] <*> primary)
  choice (map (pure . normalize) (trees first rest))
  where
    primary = (Atom <$> atom) <|> (Not <$> (word "not" *> condition atom))
      <|> (symbol "(" *> condition atom <* symbol ")")
    trees a [] = [a]
    trees a rest | all fst rest = [foldr1 And (a:map snd rest)]
                 | all (not . fst) rest = [foldr1 Or (a:map snd rest)]
    trees a rest = [if op then And l r else Or l r
      | i <- [0..length rest-1], let (before,(op,b):after) = splitAt i rest
      , l <- trees a before, r <- trees b after]
    normalize (And a b) = foldr1 And (ands (normalize a) ++ ands (normalize b))
    normalize (Or a b) = foldr1 Or (ors (normalize a) ++ ors (normalize b))
    normalize (Not a) = Not (normalize a)
    normalize a = a
    ands (And a b) = ands a ++ ands b
    ands a = [a]
    ors (Or a b) = ors a ++ ors b
    ors a = [a]
cellCondition :: Parsing p => Bool -> p (Condition CellPredicate)
cellCondition baseOnly = condition $ choice
  [ Always <$ word "true", ColorIs <$> (phrase "color is" *> color)
  , RowIs . subtract 1 <$> (phrase "row is" *> boundedNumber 1 16)
  , ColumnIs <$> (phrase "column is" *> lexeme (do c <- satisfy (\c -> toLower c `elem` ['a'..'p']); rest <- look; guard (case rest of c:_ -> not (isAlphaNum c); [] -> True); pure (ord (toLower c)-ord 'a')))
  , SameCell <$> (phrase "same cell as" *> ref), SameColor <$> (phrase "color equals that of" *> ref)
  , NeighborOf <$> (phrase "neighbor of" *> ref), ConnectedTo <$> (phrase "connected to" *> ref)
  , NeighborCount <$> (phrase "neighbor count for color" *> color) <*> (phrase "is in" *> counts)
  , Changes <$ phrase "changes in the next generation" ]
  where ref = if baseOnly then baseReference else reference
boardCondition :: Parsing p => p (Condition BoardPredicate)
boardCondition = condition ((FixedPoint <$ phrase "fixed point") <|> (Monochromatic <$> (word "monochromatic" *> option Nothing (Just <$> (phrase "with color" *> color)))))
collection :: Parsing p => p Collection
collection = (Cells <$> (word "cells" *> brackets (sepBy1 reference (symbol ","))))
  <|> (Filter <$> (phrase "cells matching" *> cellCondition False))
  <|> (Component <$> (phrase "cells connected to" *> reference))
  <|> (Rectangle <$> (phrase "cells in rectangle" *> square) <*> (word "to" *> square))
  <|> (Cells . (:[]) <$> reference)
generations :: Parsing p => Bool -> p Int
generations allowZero = do
  n <- boundedNumber (if allowZero then 0 else 1) 256
  word (if n == 1 then "generation" else "generations")
  pure n
command :: Parsing p => p Command
command = choice
  [ Paint <$> (phrase "set color of" *> collection) <*> (word "to" *> color)
  , Advance <$> (word "advance" *> generations False)
  , SetRule <$> (phrase "set rule for" *> color) <*> (word "to" *> rule)
  , ClearRule <$> (phrase "clear rule for" *> color)
  , ToggleRule <$> (phrase "enable rule for" *> color) <*> pure True
  , ToggleRule <$> (phrase "disable rule for" *> color) <*> pure False
  , SetNeighborhood <$> (phrase "set neighborhood to" *> mode)
  , ReplaceRuleset <$> (phrase "replace ruleset with" *> config) <*> (symbol "," *> options [("preserving the board",False),("randomly refilling the board if required",True)])
  , Initialize <$ phrase "initialize the board randomly"
  , Copy <$> (phrase "copy color from" *> reference) <*> (word "to" *> reference)
  , Exchange <$> (phrase "exchange color of" *> reference) <*> (word "and" *> reference)
  , ReplaceColors <$> (phrase "replace colors by" *> brackets (sepBy1 ((,) <$> reference <*> (word "to" *> color)) (symbol ",")))
  , Permute <$> (phrase "permute colors by" *> brackets (sepBy1 ((,) <$> reference <*> (word "to" *> reference)) (symbol ",")))
  , Shift <$> (phrase "shift colors of the board by east" *> number True) <*> (symbol "," *> word "north" *> number True)
  , do phrase "rotate colors of"; xs <- collection; word "by"
       n <- options [("90 degrees clockwise",90),("180 degrees",180),("90 degrees counterclockwise",270)]
       word "about"; (p,q) <- pivot; pure (Spatial xs (Rotation n) p q)
  , do phrase "reflect colors of"; xs <- collection; word "across"
       v <- options [("vertical",True),("horizontal",False)]; word "through"
       (p,q) <- pivot; pure (Spatial xs (Reflection v) p q) ]
  where pivot = (,) <$> (phrase "the center of rectangle" *> square) <*> (word "to" *> square)
stateQuestion :: Parsing p => p Question
stateQuestion = choice
  [ ColorOf <$> (phrase "what is the color of" *> reference)
  , Check <$> (word "does" *> reference) <*> (word "satisfy" *> cellCondition False)
  , CheckBoard <$> (phrase "does the board satisfy" *> boardCondition)
  , Select False Nothing <$> (phrase "which cells match" *> cellCondition False)
  , Select True Nothing <$> (phrase "how many cells match" *> cellCondition False)
  , Select False <$> (Just <$> (phrase "which neighbors of" *> reference)) <*> (word "match" *> cellCondition False)
  , Select True <$> (Just <$> (phrase "how many neighbors of" *> reference)) <*> (word "match" *> cellCondition False)
  , Quantify True <$> (phrase "does every cell matching" *> cellCondition False) <*> (word "satisfy" *> cellCondition False)
  , Quantify False <$> (phrase "does some cell matching" *> cellCondition False) <*> (word "satisfy" *> cellCondition False)
  , Transition <$> (phrase "what is the next transition of" *> reference) ]
question :: Parsing p => p Question
question = stateQuestion <|> choice
  [ Meta <$> (phrase "what is the" *> options [("generation",Generation),("palette",Palette),("neighborhood",NeighborhoodName),("ruleset revision",Revision),("ruleset",CompleteRuleset)])
  , RuleOf <$> (phrase "what is the rule for" *> color)
  , Forecast <$> (word "after" *> generations True <* symbol ",") <*> stateQuestion
  , ReturnTime <$> (phrase "what is the least return time of the board within" *> generations False)
  , FirstCell <$> (phrase "what is the first generation offset within" *> generations False) <*> (phrase "at which" *> reference) <*> (word "satisfies" *> cellCondition False)
  , FirstBoard <$> (phrase "what is the first generation offset within" *> generations False) <*> (phrase "at which the board satisfies" *> boardCondition)
  , Stabilization True <$> (phrase "does the board reach a fixed point within" *> generations False)
  , Stabilization False <$> (phrase "what is the stabilization time of the board within" *> generations False)
  , CountReaches <$> (phrase "does the count of cells matching" *> cellCondition False)
                 <*> (word "reach" *> boundedNumber 0 (boardSize * boardSize))
                 <*> (word "within" *> generations False) ]
entry :: Parsing p => p Entry
entry = (Undo <$ (word "undo" *> symbol "."))
  <|> (Batch <$> (word "atomically" *> symbol "{" *> many1 (command <* symbol ".") <* symbol "}" <* symbol "."))
  <|> (Sequence <$> many1 ((Command <$> command <* symbol ".") <|> (Question <$> question <* symbol "?")))

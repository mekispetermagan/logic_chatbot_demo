module Domains.Network.Parser where

import Control.Applicative ((<|>))
import Data.Maybe (mapMaybe)
import Domain
import Ontology
import AtomicPropertyQuery
import Layer2Syntax
import SyntaxVocabulary
import Domains.Network.Definition
import qualified Domains.Network.Syntax as N
import qualified Domains.Objects.Parser as Core

normalizeNetworkTokens :: [String] -> [String]
normalizeNetworkTokens ("dead":"ends":rest) = "endpoint" : normalizeNetworkTokens rest
normalizeNetworkTokens ("dead":"end":rest) = "endpoint" : normalizeNetworkTokens rest
normalizeNetworkTokens (word:rest) = maybe word id (lookup word
  [("dots","dot"),("tips","tip"),("straights","straight"),("bends","bend"),
   ("tees","tee"),("crosses","cross"),("endpoints","endpoint"),("junctions","junction")]) : normalizeNetworkTokens rest
normalizeNetworkTokens [] = []

port :: String -> Maybe N.Port
port word = lookup word [("north",N.North),("up",N.North),("east",N.East),("right",N.East),
  ("south",N.South),("down",N.South),("west",N.West),("left",N.West)]

subject :: [String] -> Maybe Subject
subject = existingSubjectWith networkDomain

descriptions :: [String] -> Maybe [Property]
descriptions = descriptionWith networkDomain

performatives :: [String] -> [Sentence]
performatives tokens = specific ++ Core.derivedPerformativesWith networkDomain movement
  where
    movement = case tokens of
      "move":rest -> case reverse rest of
        last:before | Just p <- port last -> "move" : reverse before ++ [case p of
          N.North -> "up"; N.East -> "right"; N.South -> "down"; N.West -> "left"]
        _ -> tokens
      _ -> tokens
    specific = case tokens of
      "rotate":rest -> mapMaybe rotate (splits rest)
      "flip":rest -> mapMaybe reflect (splits rest)
      "make":rest -> mapMaybe copy (splits rest)
      "connect":rest -> mapMaybe connection (splits rest)
      verb:rest | verb `elem` ["link","extend","disconnect"] -> mapMaybe (link (verb /= "disconnect")) (splits rest)
      "remove":"unmatched":"ports":"from":rest -> maybe [] (pure . Network . N.TrimUnmatched) (subject rest)
      "color":"the":"component":"of":rest -> mapMaybe colorComponent (splits rest)
      _ -> []
    rotate (before, [name]) = do
      clockwise <- lookup name [("clockwise",True),("counterclockwise",False)]
      Network . (`N.Rotate` clockwise) <$> subject before
    rotate _ = Nothing
    reflect (before,[name]) = do
      horizontal <- lookup name [("horizontally",True),("vertically",False)]
      Network . (`N.Reflect` horizontal) <$> subject before
    reflect _ = Nothing
    copy (before,after) = do
      source <- subject before
      target <- case dropWord "the" after of
        "same":"pattern":"as":rest -> subject rest
        "same":"as":rest -> subject rest
        _ -> Nothing
      pure (Network (N.CopyPattern source target))
    link connect (before,after) = do
      source <- subject before
      case after of
        [direction] -> Network . (\p -> N.LinkDirection source p connect) <$> port direction
        delimiter:rest | delimiter == (if connect then "to" else "from") ->
          Network . (\target -> N.LinkPair source target connect) <$> subject rest
        _ -> Nothing
    colorComponent (before,[name]) = do
      source <- subject before
      AttributeValue (AttributeId "color") color <- descriptorWith networkDomain name
      pure (Network (N.ColorComponent source color))
    colorComponent _ = Nothing
    endpoint [word] | Just position <- squareWith networkDomain word = Just (N.Square position)
    endpoint words = N.Existing <$> subject words
    connection (before,"to":after) = do
      source <- endpoint before
      let (targetTokens, suffix) = break (== "with") after
      target <- endpoint targetTokens
      color <- case suffix of
        [] -> Just Nothing
        ["with",name] -> do
          AttributeValue (AttributeId "color") value <- descriptorWith networkDomain name
          Just (Just value)
        _ -> Nothing
      pure (Network (N.Connect source target color))
    connection _ = Nothing

relation :: [String] -> Maybe QuantifiedPredicate
relation tokens = networkRelation <|> Core.relationPredicateWith networkDomain tokens
  where
    networkRelation = case tokens of
      "linked":"to":rest -> RelationPredicate (NetworkRelation N.Linked) . Just <$> subject rest
      "connected":"to":rest -> do
        let (targetTokens, path) = break (== "by") rest
        target <- subject targetTokens
        color <- case path of
          [] -> Just Nothing
          ["by","a",name,"path"] -> do
            AttributeValue (AttributeId "color") value <- descriptorWith networkDomain name
            Just (Just value)
          _ -> Nothing
        pure (RelationPredicate (NetworkRelation (N.Connected color)) (Just target))
      _ -> Nothing

predicates :: [String] -> Maybe [QuantifiedPredicate]
predicates tokens = traverse clause (clauses tokens)
  where
    clauses words = case break (== "and") words of
      (first,[]) -> [first]
      (first,_:rest) -> first : clauses rest
    clause words = (PropertyPredicate <$> descriptions (dropWord "a" words)) <|> relation words

questions :: [String] -> [Sentence]
questions ("how":"many":"connections":"does":rest) = case reverse rest of
  "have":before -> maybe [] (pure . Network . N.ConnectionCount) (subject (reverse before))
  _ -> []
questions ["how","many","components"] = [Network N.ComponentCount]
questions ("what":"is":"the":"distance":"from":rest) = distanceQuestions rest
questions ("distance":rest) = distanceQuestions (dropWord "from" rest)
questions ("how":"many":tokens) = countQuestions tokens
questions words = quantified ++ ordinary
  where
    quantified = case words of
      "is":"every":rest -> quantify True rest
      "does":"every":rest -> quantify True rest
      "every":rest -> quantify True rest
      _ -> case dropWord "do" (dropWord "are" words) of
        "some":rest -> quantify False rest
        _ -> []
    quantify universal rest = mapMaybe candidate (splits rest)
      where
        candidate (before,after) = do
          let noun = if universal then "object" else "objects"
              copula = if universal then "is" else "are"
          following <- case after of
            word:rest | word == noun -> Just (dropWord copula rest)
            word:rest | word == copula -> Just rest
            _ -> Nothing
          Quantified universal <$> descriptions before <*> predicates following
    tokens = case words of "is":rest -> rest; "does":rest -> rest; _ -> words
    ordinary = mapMaybe ordinaryQuestion (splits tokens)
    ordinaryQuestion (before,after) = do
      source <- subject before
      case after of
        ["have","an","unmatched","port"] -> Just (Check source (Defined "unmatched"))
        _ -> do
          RelationPredicate check target <- relation after
          pure (SpatialQuestion source check target)

distanceQuestions :: [String] -> [Sentence]
distanceQuestions tokens = mapMaybe candidate (splits tokens)
  where
    candidate (before,"to":after) = Network <$> (N.Distance <$> subject before <*> subject after)
    candidate _ = Nothing

countQuestions :: [String] -> [Sentence]
countQuestions tokens = squareCounts ++ counts
  where
    squareTokens = dropWord "are" (dropWord "squares" tokens)
    squareCounts = case squareTokens of
      [name] | name `elem` ["empty","free","occupied","taken"] &&
        (take 1 tokens == ["squares"] || name /= "empty") -> [CountSquares (name `elem` ["occupied","taken"])]
      _ -> []
    -- A noun/copula provides the subject/predicate boundary when filters are mixed.
    counts = case break (`elem` ["objects","are"]) tokens of
      (before, marker:after) -> maybe [] pure $ do
        properties <- if null before then Just [] else descriptions before
        let following = if marker == "objects" then dropWord "are" after else after
        followingPredicates <- if null following then Just [] else predicates following
        pure (CountMatching properties followingPredicates)
      (_,[]) | not (null squareCounts) -> []
      (_,[]) -> maybe [] (pure . (`CountMatching` [])) (descriptions tokens)

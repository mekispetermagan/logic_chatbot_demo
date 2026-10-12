module Domains.Objects.Parser where
import Control.Applicative ((<|>))
import Data.Maybe (mapMaybe)
import Domain
import Ontology
import AtomicPerformative
import AtomicPropertyQuery
import Layer2Syntax
import SyntaxVocabulary

derivedPerformativesWith :: Domain -> [String] -> [Sentence]
derivedPerformativesWith domain ("move":tokens) = mapMaybe candidate (splits tokens)
  where
    candidate (before, after) = do
      who <- (existingSubjectWith domain) before
      case after of
        [name] -> StepMove who <$> direction name
        "next":"to":rest -> NeighborMove who <$> (existingSubjectWith domain) rest
        _ -> do
          (whereTo, rest) <- relative after
          RelativeMove who whereTo <$> (existingSubjectWith domain) rest
derivedPerformativesWith domain ("make":tokens) = mapMaybe candidate (splits tokens)
  where
    candidate (before, after) = do
      who <- (existingSubjectWith domain) before
      case dropWord "the" after of
        "same":name:"as":rest -> do
          attr <- (removableWith domain) name
          if attr == RemoveSquare then Nothing else CopyAttribute who attr <$> (existingSubjectWith domain) rest
        _ -> Nothing
derivedPerformativesWith domain _ = []


derivedQuestionsWith :: Domain -> [String] -> [Sentence]
derivedQuestionsWith domain ("how":"many":tokens) = squareCounts ++ objectCounts
  where
    stripped = dropWord "are" (dropWord "squares" tokens)
    squareCounts = case stripped of
      [name] | name `elem` ["empty", "free", "occupied", "taken"] ->
        [CountSquares (name `elem` ["occupied", "taken"])]
      _ -> []
    objectTokens = dropWord "are" (dropWord "objects" tokens)
    objectCounts = case objectTokens of
      "next":"to":rest -> maybe [] ((:[]) . CountObjects . Neighboring) ((existingSubjectWith domain) rest)
      ["at", "the", "edge"] -> [CountObjects AtEdge]
      ["in", "a", "corner"] -> [CountObjects InCorner]
      _ -> maybe [] ((:[]) . CountObjects . Described) (traverse (descriptorWith domain) objectTokens)
derivedQuestionsWith domain words' = quantified ++ relations
  where
    tokens = case words' of
      "is":rest -> rest
      "does":rest -> rest
      _ -> words'
    quantified = case words' of
      "is":"every":rest -> universalCandidates rest
      "does":"every":rest -> universalCandidates rest
      "every":rest -> universalCandidates rest
      _ -> case dropWord "do" (dropWord "are" words') of
        "some":rest -> mapMaybe (quantifiedCandidate False) (splits rest)
        _ -> []
    universalCandidates rest = mapMaybe (quantifiedCandidate True) (splits rest)
    quantifiedCandidate universal (before, after) = do
      -- A noun or copula marks the boundary between the two descriptions.
      let noun = if universal then "object" else "objects"
          copula = if universal then "is" else "are"
      following <- case after of
        word:rest | word == noun -> Just (dropWord copula rest)
        word:rest | word == copula -> Just rest
        _ -> Nothing
      first <- (descriptionWith domain) before
      second <- (quantifiedPredicatesWith domain) following
      pure (Quantified universal first second)
    relations = mapMaybe relation (splits tokens)
    relation (before, after) = do
      who <- (existingSubjectWith domain) before
      RelationPredicate relation target <- (relationPredicateWith domain) after
      pure (SpatialQuestion who relation target)

-- Explicit conjunction boundaries avoid consuming descriptors of a target.
quantifiedPredicatesWith :: Domain -> [String] -> Maybe [QuantifiedPredicate]
quantifiedPredicatesWith domain tokens = traverse clause (clauses tokens)
  where
    clauses words' = case break (== "and") words' of
      (first, []) -> [first]
      (first, _:rest) -> first : clauses rest
    clause words' = (PropertyPredicate <$> (descriptionWith domain) (dropWord "a" words'))
                    <|> (relationPredicateWith domain) words'

-- Shared by ordinary and quantified questions. Targets must already exist.
relationPredicateWith :: Domain -> [String] -> Maybe QuantifiedPredicate
relationPredicateWith domain tokens = case tokens of
  ["on", "board"] -> (unaryWith domain) OnBoard
  ["on", "the", "board"] -> (unaryWith domain) OnBoard
  ["at", "the", "edge"] -> (unaryWith domain) Edge
  ["in", "a", "corner"] -> (unaryWith domain) Corner
  "next":"to":rest -> binary NextTo rest
  _ -> sameOrHas tokens
  where
    (unaryWith domain) relation = Just (RelationPredicate relation Nothing)
    binary relation rest = RelationPredicate relation . Just <$> (existingSubjectWith domain) rest
    sameOrHas words' = case dropWord "the" (dropWord "have" words') of
      ["a", name] -> do
        attr <- (removableWith domain) name
        if take 1 words' == ["have"] then (unaryWith domain) (Has attr) else Nothing
      "same":name:"as":rest -> do
        attr <- (comparisonAttributeWith domain) name
        binary (Same attr) rest
      _ -> case dropWord "the" (dropWord "in" words') of
        "same":name:"as":rest | name `elem` ["square", "row", "column"] -> do
          attr <- (comparisonAttributeWith domain) name
          binary (Same attr) rest
        _ -> Nothing


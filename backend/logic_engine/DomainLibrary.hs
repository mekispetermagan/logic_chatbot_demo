module DomainLibrary where

import Domain
import Ontology
import Layer2Syntax

-- Pure domain hooks: no IO, HTTP, persistence, or remembered conversation state.
data DerivedResult = DerivedComplete World [String] [[Property]]
                   | DerivedCompleteWithMentions World [String] [(Identifier, [Property])]
                   | ChooseSquares [Position]
data DomainLibrary = DomainLibrary
  { ontology :: Domain
  , parseDerivedPerformatives :: [String] -> [Sentence]
  , parseDerivedQuestions :: [String] -> [Sentence]
  , evaluateDerivedSentence :: World -> [Identifier] -> Sentence -> Maybe Position -> Maybe DerivedResult
  , propertyTruth :: World -> Object -> Property -> Bool
  , mentionProperties :: Property -> [Property]
  , normalizeTokens :: [String] -> [String]
  }

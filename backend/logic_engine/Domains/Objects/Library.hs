module Domains.Objects.Library where

import Ontology (holdsProperty)
import DomainLibrary
import Domains.Objects.Definition
import qualified Domains.Objects.Parser as Parser
import qualified Domains.Objects.Evaluation as Evaluation

objectsLibrary :: DomainLibrary
objectsLibrary = DomainLibrary
  { ontology = objectsDomain
  , parseDerivedPerformatives = Parser.derivedPerformativesWith objectsDomain
  , parseDerivedQuestions = Parser.derivedQuestionsWith objectsDomain
  , evaluateDerivedSentence = Evaluation.evaluateDerivedWith objectsDomain
  , propertyTruth = \_ -> holdsProperty
  , mentionProperties = (:[])
  , normalizeTokens = id
  }

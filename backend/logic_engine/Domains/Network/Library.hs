module Domains.Network.Library where

import DomainLibrary
import Domains.Network.Definition
import Domains.Network.Patterns (expandMention)
import Domains.Network.Graph
import Domains.Network.Parser
import Domains.Network.Evaluation

networkLibrary :: DomainLibrary
networkLibrary = DomainLibrary
  { ontology = networkDomain
  , parseDerivedPerformatives = performatives
  , parseDerivedQuestions = questions
  , evaluateDerivedSentence = evaluateNetwork
  , propertyTruth = networkHolds
  , mentionProperties = expandMention
  , normalizeTokens = normalizeNetworkTokens
  }

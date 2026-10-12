module Domains.Network.Library where

import DomainLibrary
import Domains.Network.Definition

-- Core and anaphoric language only; network-derived algorithms come later.
networkLibrary :: DomainLibrary
networkLibrary = DomainLibrary
  { ontology = networkDomain
  , parseDerivedPerformatives = const []
  , parseDerivedQuestions = const []
  , evaluateDerivedSentence = \_ _ _ _ -> Nothing
  }

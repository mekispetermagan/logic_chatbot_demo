module ControlledLanguage.Domain where

import Domain
import Ontology
import Domains.Objects.Definition (objectsDomain)
import Domains.Network.Definition (networkDomain)

isNetwork :: Domain -> Bool
isNetwork = (== "network") . domainId
languageVersion :: Domain -> String
languageVersion domain = domainId domain ++ "-v2"
appearanceAttributesFor :: Domain -> [String]
appearanceAttributesFor domain = [name | definition <- domainAttributes domain, let AttributeId name = attributeId definition]
lookupDomain :: String -> Maybe Domain
lookupDomain "objects" = Just objectsDomain
lookupDomain "network" = Just networkDomain
lookupDomain _ = Nothing

module Domains.Network.Language.Parser (parseEntry, parseEntryAlternatives) where
import ControlledLanguage.Syntax (Entry)
import qualified ControlledLanguage.Parser as Shared
import Domains.Network.Definition (networkDomain)
parseEntry :: String -> Either String Entry
parseEntry = Shared.parseEntryWith networkDomain
parseEntryAlternatives :: String -> Either String [Entry]
parseEntryAlternatives = Shared.parseEntryAlternativesWith networkDomain

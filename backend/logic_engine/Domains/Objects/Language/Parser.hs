module Domains.Objects.Language.Parser (parseEntry, parseEntryAlternatives) where
import ControlledLanguage.Syntax (Entry)
import qualified ControlledLanguage.Parser as Shared
import Domains.Objects.Definition (objectsDomain)
parseEntry :: String -> Either String Entry
parseEntry = Shared.parseEntryWith objectsDomain
parseEntryAlternatives :: String -> Either String [Entry]
parseEntryAlternatives = Shared.parseEntryAlternativesWith objectsDomain

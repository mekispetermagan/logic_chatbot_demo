module Domains.Objects.Language.Canonical (parseCanonical) where
import ControlledLanguage.Syntax (Entry)
import qualified ControlledLanguage.Canonical as Shared
import Domains.Objects.Definition (objectsDomain)
parseCanonical :: String -> Either String Entry
parseCanonical = Shared.parseCanonicalWith objectsDomain

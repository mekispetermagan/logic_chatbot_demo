module Domains.Objects.Language.Grammar (Backend(..), entryGrammar) where
import Control.Applicative (Alternative)
import ControlledLanguage.Grammar (Backend(..))
import qualified ControlledLanguage.Grammar as Shared
import ControlledLanguage.Syntax (Entry)
import Domains.Objects.Definition (objectsDomain)
entryGrammar :: (Alternative p, MonadFail p) => Backend p -> Bool -> p Entry
entryGrammar = Shared.entryGrammar objectsDomain

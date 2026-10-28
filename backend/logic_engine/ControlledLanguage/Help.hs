{-# LANGUAGE OverloadedStrings #-}
module ControlledLanguage.Help (examplesFor) where

import Data.Aeson (Value, object, (.=))
import qualified Domains.Objects.Language.Examples as Objects
import qualified Domains.Network.Language.Examples as Network
import qualified Domains.Cellular.Language.Examples as Cellular
import qualified Domains.Calendar.Language.Examples as Calendar

examplesFor :: String -> Either String Value
examplesFor domain = do
  (version, sections) <- case domain of
    "objects" -> Right ("objects-v2", Objects.examples)
    "network" -> Right ("network-v2", Network.examples)
    "cellular" -> Right ("cellular-v2", Cellular.examples)
    "calendar" -> Right ("calendar-v1", Calendar.examples)
    _ -> Left "Unknown language domain"
  pure $ object
    [ "domain" .= domain
    , "languageVersion" .= (version :: String)
    , "sections" .= [object ["title" .= title, "examples" .= entries] | (title, entries) <- sections]
    ]

{-# LANGUAGE OverloadedStrings #-}
module ControlledLanguage.Example (ExamplePart(..), Example, ExampleSections, sentence) where

import Data.Aeson (ToJSON(..), object, (.=))

-- Reference boundaries are authored by the domain, never inferred by the UI.
data ExamplePart = Plain String | Reference String deriving (Eq, Show)
type Example = [ExamplePart]
type ExampleSections = [(String, [Example])]

sentence :: Example -> String
sentence = concatMap partText
  where partText (Plain text) = text
        partText (Reference text) = text

instance ToJSON ExamplePart where
  toJSON (Plain text) = object ["text" .= text, "reference" .= False]
  toJSON (Reference text) = object ["text" .= text, "reference" .= True]

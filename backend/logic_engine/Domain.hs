module Domain where

import Data.Char (toLower)
import Data.List (nub)
import Ontology
import Pretty

-- Finite optional attributes; a singleton value list represents a unary attribute.
data ValueDefinition = ValueDefinition
  { valueId :: ValueId, valueAliases :: [String] } deriving (Eq, Show)
data AttributeDefinition = AttributeDefinition
  { attributeId :: AttributeId, attributeAliases :: [String]
  , attributeValues :: [ValueDefinition] } deriving (Eq, Show)
data DefinedDescriptor = DefinedDescriptor
  { definedName :: String, definedAliases :: [String], assignable :: Bool } deriving (Eq, Show)
data Domain = Domain
  { domainId :: String, boardWidth :: Int, boardHeight :: Int
  , domainAttributes :: [AttributeDefinition], domainDefined :: [DefinedDescriptor] } deriving (Eq, Show)

canonical :: String -> String
canonical = map toLower

descriptorVocabulary :: Domain -> [(String, Property)]
descriptorVocabulary domain =
  [(canonical word, AttributeValue (attributeId attribute) (valueId value))
  | attribute <- domainAttributes domain, value <- attributeValues attribute
  , word <- pretty (valueId value) : valueAliases value] ++
  [(canonical word, Defined (definedName definition)) | definition <- domainDefined domain,
    word <- definedName definition : definedAliases definition]

attributeVocabulary :: Domain -> [(String, AttributeId)]
attributeVocabulary domain =
  [(canonical word, attributeId attribute) | attribute <- domainAttributes domain
  , word <- pretty (attributeId attribute) : attributeAliases attribute]

validProperty :: Domain -> Property -> Bool
validProperty domain (AttributeValue attribute value) = any
  (\definition -> attributeId definition == attribute && value `elem` map valueId (attributeValues definition))
  (domainAttributes domain)
validProperty domain (Defined name) = any ((== name) . definedName) (domainDefined domain)
validProperty domain (P position) = inDomainBounds domain position

inDomainBounds :: Domain -> Position -> Bool
inDomainBounds domain (x,y) = x >= 0 && y >= 0 && x < boardWidth domain && y < boardHeight domain

validateDomain :: Domain -> Either String Domain
validateDomain domain
  | null (domainId domain) = Left "Empty domain identifier"
  | boardWidth domain <= 0 || boardWidth domain > 26 || boardHeight domain <= 0 = Left "Invalid board dimensions"
  | not (unique (map attributeId definitions)) = Left "Duplicate attribute identifier"
  | any (null . attributeValues) definitions = Left "Attribute has no permitted values"
  | any (not . unique . map valueId . attributeValues) definitions = Left "Duplicate value identifier"
  | any (null . pretty . attributeId) definitions || any (null . pretty . valueId) values = Left "Empty identifier"
  | not (unambiguous (attributeVocabulary domain)) || not (unambiguous (descriptorVocabulary domain)) = Left "Ambiguous vocabulary"
  | any (\word -> null word || any (`elem` " .?\t\n") word || (word `elem` reserved && not (directionalUnary word)) || looksLikeReference word) words' = Left "Reserved or invalid vocabulary"
  | any incompatibleOverlap (descriptorVocabulary domain) = Left "Attribute/descriptor vocabulary collision"
  | otherwise = Right domain
  where
    definitions = domainAttributes domain
    values = concatMap attributeValues definitions
    words' = map fst (attributeVocabulary domain) ++ map fst (descriptorVocabulary domain)
    unique xs = length xs == length (nub xs)
    unambiguous xs = all (\(word, meaning) -> all (\(other, result) -> word /= other || meaning == result) xs) xs
    looksLikeReference word = take 1 word == "#" || case word of
      c:digits -> c >= 'a' && c <= 'z' && not (null digits) && all (`elem` "0123456789") digits
      _ -> False
    unaryWord word attribute = any matches definitions
      where
        matches definition = attributeId definition == attribute &&
          case attributeValues definition of
            [value] -> lookup word (descriptorVocabulary domain) ==
              Just (AttributeValue attribute (valueId value))
            _ -> False
    incompatibleOverlap (word, AttributeValue attribute _) = case lookup word (attributeVocabulary domain) of
      Nothing -> False
      Just name -> name /= attribute || not (unaryWord word attribute)
    incompatibleOverlap (word, _) = word `elem` map fst (attributeVocabulary domain)
    directionalUnary word = word `elem` ["up", "right", "down", "left"] &&
      case lookup word (attributeVocabulary domain) of
        Just attribute -> unaryWord word attribute
        Nothing -> False
    reserved = words "is to on a the one it of what remove from board erase delete swap and move turn make same have in at edge corner next just above under up down left right how many objects object squares every some are does do undo position row column square clear world everything all"

prettyObjectIn :: Domain -> Object -> String
prettyObjectIn domain object = pretty (idOf object) ++ ": " ++ unwords
  [maybe "?" pretty (attributeOf (attributeId attribute) object) | attribute <- domainAttributes domain]
  ++ " on " ++ maybe "?" prettyPosition (positionOf object)

prettyWorldIn :: Domain -> World -> String
prettyWorldIn _ (World []) = "(empty world)"
prettyWorldIn domain (World objects) = unlines (map (prettyObjectIn domain) objects)

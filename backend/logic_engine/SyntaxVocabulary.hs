module SyntaxVocabulary where
import Control.Applicative ((<|>))
import Data.Char (ord, isDigit)
import Text.Read (readMaybe)
import Domain
import Ontology
import AtomicPerformative (RemovableAttribute(..))
import AtomicPropertyQuery
import Layer2Syntax

descriptorWith :: Domain -> String -> Maybe Property
descriptorWith domain word = lookup (canonical word) (descriptorVocabulary domain)

attributeWith :: Domain -> String -> Maybe Attribute
attributeWith domain word = (Stored <$> lookup (canonical word) (attributeVocabulary domain)) <|>
  lookup word [("position",PositionAttribute),("row",RowAttribute),("column",ColumnAttribute)]

squareWith :: Domain -> String -> Maybe Position
squareWith domain (column:digits) | column >= 'a' && column <= 'z' && not (null digits) && take 1 digits /= "0" && all isDigit digits = do
  row <- readMaybe digits :: Maybe Integer
  if row < 1 || row > toInteger (boardHeight domain) then Nothing else do
    let position = (ord column - ord 'a', fromInteger row - 1)
    if inDomainBounds domain position then Just position else Nothing
squareWith domain _ = Nothing

referenceWith :: Domain -> String -> Maybe ObjectReference
referenceWith domain ('#':digits) | not (null digits) && all isDigit digits = do
  number <- readMaybe digits :: Maybe Integer
  if number >= 0 && number <= toInteger (maxBound :: Int)
    then Just (ById (Id (fromInteger number))) else Nothing
referenceWith domain word = AtSquare <$> (squareWith domain) word

subjectWith :: Domain -> [String] -> Maybe Subject
subjectWith domain ["it"] = Just It
subjectWith domain [word] | Just ref <- (referenceWith domain) word = Just (Reference ref)
subjectWith domain ("the":words') = Definite <$> (descriptionWith domain) words'
subjectWith domain ("a":words') = Indefinite <$> (descriptionWith domain) words'
subjectWith domain words' = Indefinite <$> (descriptionWith domain) words'

descriptionWith :: Domain -> [String] -> Maybe [Property]
descriptionWith domain words' = case stripOne words' of
  [] -> Nothing
  descriptors -> traverse (descriptorWith domain) descriptors
  where
    stripOne tokens | not (null tokens) && last tokens == "one" = init tokens
    stripOne tokens = tokens

dropWord :: String -> [String] -> [String]
dropWord word (first:rest) | word == first = rest
dropWord _ words' = words'

destinationWith :: Domain -> [String] -> Maybe Property
destinationWith domain words' = case dropWord "on" (dropWord "to" words') of
  [position] -> P <$> (squareWith domain) position
  _ -> Nothing

-- A destination can occur once, only at the end of a predicate.
predicateWith :: Domain -> [String] -> Maybe [Property]
predicateWith domain words' = let tokens = dropWord "a" (dropWord "to" (dropWord "is" words')) in
  case (destinationWith domain) tokens of
    Just position -> Just [position]
    Nothing -> case span (\word -> (descriptorWith domain) word /= Nothing) tokens of
      ([], _) -> Nothing
      (descriptors, rest) -> do
        properties <- traverse (descriptorWith domain) descriptors
        case rest of
          [] -> Just properties
          _ -> (properties ++) . (:[]) <$> (destinationWith domain) rest

splits :: [a] -> [([a], [a])]
splits tokens = [splitAt index tokens | index <- [1 .. length tokens - 1]]

isIndefinite :: Subject -> Bool
isIndefinite (Indefinite _) = True
isIndefinite _ = False

hasBoundary :: [String] -> Bool
hasBoundary (word:_) = word == "is" || word == "to"
hasBoundary _ = False

isPosition :: Property -> Bool
isPosition (P _) = True
isPosition _ = False

existingSubjectWith :: Domain -> [String] -> Maybe Subject
existingSubjectWith domain tokens = do
  who <- (subjectWith domain) tokens
  if isIndefinite who then Nothing else Just who

unaryWith :: Domain -> (Subject -> Sentence) -> [String] -> [Sentence]
unaryWith domain constructor tokens = maybe [] ((:[]) . constructor) ((existingSubjectWith domain) tokens)

removableWith :: Domain -> String -> Maybe RemovableAttribute
removableWith domain name = (RemoveStored <$> lookup (canonical name) (attributeVocabulary domain))
  <|> (if name == "square" then Just RemoveSquare else Nothing)

comparisonAttributeWith :: Domain -> String -> Maybe Attribute
comparisonAttributeWith domain "square" = Just PositionAttribute
comparisonAttributeWith domain name = (attributeWith domain) name

direction :: String -> Maybe Direction
direction name = lookup name [("up", Up), ("down", Down), ("left", Leftward), ("right", Rightward)]

relative :: [String] -> Maybe (Direction, [String])
relative tokens = case dropWord "just" tokens of
  "above":rest -> Just (Up, rest)
  "under":rest -> Just (Down, rest)
  "right":"of":rest -> Just (Rightward, rest)
  "left":"of":rest -> Just (Leftward, rest)
  _ -> Nothing



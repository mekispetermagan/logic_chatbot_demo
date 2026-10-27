{-# LANGUAGE FlexibleContexts #-}
module Domains.Calendar.Language.Parser (parseEntries,parseEntry) where
import Control.Applicative ((<|>))
import Control.Monad (guard,void)
import Data.Char (isAlphaNum,toLower)
import Data.List (nub,sort)
import Data.Time (Day,defaultTimeLocale,parseTimeM)
import qualified Data.Aeson as J
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.ByteString.Lazy as B
import Text.ParserCombinators.ReadP
import Domains.Calendar.Language.Syntax

asciiDigit c=c>='0'&&c<='9'
lexeme p=p <* skipSpaces
word t=lexeme $ void (traverse (\c->satisfy ((==c).toLower)) t) <* (look >>= \r->guard (null r || not (isAlphaNum (head r))))
phrase=mapM_ word . words
symbol=lexeme . string
number=lexeme $ do ds<-munch1 (\c->c>='0'&&c<='9');guard (length ds==1 || head ds/='0');pure (read ds::Integer)
integer=do n<-number;guard (n<toInteger (maxBound::Int));pure (fromInteger n)
quoted=lexeme $ do
  raw<-gather (char '"' *> many (void (char '\\' *> get) <|> void (satisfy (\c->c/='"'&&c/='\\'&&c>=' '))) <* char '"')
  case J.eitherDecode (B.fromStrict (T.encodeUtf8 (T.pack (fst raw)))) of Right x->pure x;Left _->pfail
choiceWords xs=choice [v <$ phrase k | (k,v)<-xs]
slot p=(Missing <$ word "unspecified") <|> (Known <$> p)
date=choiceWords (zip ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"] (map Weekday [0..6]))
  <|> (Today <$ word "today") <|> (Tomorrow <$ word "tomorrow") <|> do
    t<-lexeme (count 4 (satisfy asciiDigit) >>= \y->char '-' *> count 2 (satisfy asciiDigit) >>= \m->char '-' *> count 2 (satisfy asciiDigit) >>= \d->pure (y++"-"++m++"-"++d))
    guard ((parseTimeM True defaultTimeLocale "%Y-%m-%d" t::Maybe Day)/=Nothing && take 4 t/="0000");pure (DateLiteral t)
dateSlot=(Missing <$ phrase "unspecified date") <|> (Known <$> date)
clock=do h<-count 2 (satisfy asciiDigit);char ':';m<-count 2 (satisfy asciiDigit);guard (read h<24 && read m<60);skipSpaces;pure (read h*60+read m)
clockTerm=(Clock <$> clock) <|> do phrase "one of";symbol "[";xs<-sepBy1 clock (symbol ",");symbol "]";guard (length xs>=2&&length xs==length(nub xs));pure (ClockChoices (sort xs))
offset=do sign<-lexeme (satisfy (`elem` "+-"));h<-count 2 (satisfy asciiDigit);char ':';m<-count 2 (satisfy asciiDigit);skipSpaces;guard(read h<=14&&read m<60);pure ((if sign=='-' then -1 else 1)*(read h*60+read m)*60)
moment=Moment <$> dateSlot <*> (word "at" *> slot clockTerm) <*> option Nothing (Just <$> (word "offset" *> offset))
windowValue=(SelectedWeek <$ phrase "selected week")
  <|> (Between <$> (phrase "interval from" *> slot moment) <*> (word "to" *> slot moment))
  <|> (Starting <$> (phrase "starting at" *> slot moment))
  <|> (OnDate <$> dateSlot <*> option Nothing (Just <$> choiceWords [(x,x)|x<-["night","dawn","morning","lunchtime","afternoon","evening"]])
    <*> option Nothing (Just <$> ((,) <$> choiceWords [("after",False),("at or after",True)] <*> slot clockTerm))
    <*> option Nothing (Just <$> ((,) <$> choiceWords [("before",False),("by",True)] <*> slot clockTerm)))
importance=choiceWords [("normal",0),("important",1),("critical",2)]
textField=choiceWords [(x,x)|x<-["title","location","description"]]
ref=(Handle <$> (char '#' *> integer)) <|> (It <$ word "it") <|> do
  word "the";unique<-option False (True <$ word "unique");phrase "event with"
  ds<-sepBy1 descriptor (word "and");let names=map fst ds
  guard (length names==length(nub names)&&names==sortFields names);pure(Described unique ds)
  where
    descriptor=((,) <$> textField <*> quoted) <|> ((,) "importance" . show <$> (word "importance" *> importance))
      <|> ((,) "start date" . show <$> (phrase "start date" *> date))
sortFields xs=map snd (sort [(rank x,x)|x<-xs]) where rank x=case lookup x (zip ["title","location","description","importance","start date"] [0::Int ..]) of Just n->n;_->9
refs=between (symbol "[") (symbol "]") (sepBy ref (symbol ","))
comparison=choiceWords [("is",Equal),("is at least",AtLeast),("is at most",AtMost)]
durationValue=(1 <$ phrase "1 minute") <|> do n<-number;guard(n/=1);word "minutes";pure n
condition=do
  a<-primary;xs<-many ((,) <$> choiceWords [("and",True),("or",False)] <*> primary)
  choice (map (pure.normalize) (trees a xs))
  where
    primary=(Not <$> (word "not" *> condition)) <|> between (symbol "(") (symbol ")") condition <|> atom
    trees a []=[a]
    trees a xs | all fst xs=[foldr1 And (a:map snd xs)] | all (not.fst) xs=[foldr1 Or (a:map snd xs)]
    trees a xs=[(if op then And else Or) l r |i<-[0..length xs-1],let (before,(op,b):after)=splitAt i xs,l<-trees a before,r<-trees b after]
    normalize (And a b)=foldr1 And (ands(normalize a)++ands(normalize b))
    normalize (Or a b)=foldr1 Or (ors(normalize a)++ors(normalize b))
    normalize (Not a)=Not(normalize a);normalize a=a
    ands(And a b)=ands a++ands b;ands a=[a];ors(Or a b)=ors a++ors b;ors a=[a]
    atom=(TrueCondition <$ word "true") <|> (UnknownCondition <$ word "unspecified")
      <|> (TextIs <$> textField <*> (word "is" *> slot quoted))
      <|> (ImportanceIs <$> (word "importance" *> comparison) <*> slot importance)
      <|> (StartsOn <$> (phrase "starts on" *> dateSlot))
      <|> (Within <$> (word "within" *> slot windowValue))
      <|> (OverlapsWindow <$> (word "overlaps" *> slot windowValue))
      <|> (Relation "overlaps" <$> (phrase "overlaps event" *> slot ref))
      <|> (Relation "before" <$> (phrase "before event" *> slot ref))
      <|> (Relation "after" <$> (phrase "after event" *> slot ref))
      <|> (DurationIs <$> (word "duration" *> comparison) <*> slot durationValue)
      <|> (HasClash <$> (phrase "has a clash" *> option (Known SelectedWeek) (word "within" *> slot windowValue)))
options=Options <$> option Missing (symbol "," *> phrase "moving up to" *> slot (choiceWords [("none",-1)] <|> importance))
  <*> option (Known []) (symbol "," *> word "protecting" *> slot refs)
  <*> option False (symbol "," *> word "choosing" *> choiceWords [("ask",False),("preserve original order",True)])
parameters=Task <$> option Missing (word "lasting" *> slot durationValue) <*> option Missing (word "within" *> slot windowValue) <*> pure []
task=do
  t<-parameters;fs<-option [] (word "with" *> sepBy1 field (word "and"));let names=map fst fs
  guard(length names==length(nub names)&&names==sortFields names);pure t{fields=fs}
  where field=((,) <$> textField <*> slot quoted) <|> ((,) "importance" . fmapSlot show <$> (word "importance" *> slot importance))
fmapSlot f (Known x)=Known(f x);fmapSlot _ Missing=Missing
command=choice
  [ Create <$> (phrase "create event from" *> slot moment) <*> (word "to" *> slot moment)
  , Delete <$> (word "delete" *> slot ref)
  , SetText <$> (word "set" *> textField <* word "of") <*> slot ref <*> (word "to" *> slot quoted)
  , SetImportance <$> (phrase "set importance of" *> slot ref) <*> (word "to" *> slot importance)
  , SetInterval <$> (phrase "set interval of" *> slot ref) <*> (word "from" *> slot moment) <*> (word "to" *> slot moment)
  , Schedule <$> (phrase "schedule event" *> task)
  , Insert <$> (phrase "make room for event" *> task) <*> options
  , Repair <$> (phrase "remove clashes" *> option Missing (word "on" *> dateSlot)) <*> options ]
question=choice
  [ Exists <$> (word "does" *> slot (char '#' *> integer) <* word "exist")
  , Query <$> (phrase "what is the" *> slot (choiceWords [(x,x)|x<-["title","location","description","importance","start","end","interval"]]) <* word "of") <*> slot ref
  , Check <$> (word "does" *> slot ref) <*> (word "satisfy" *> condition)
  , DurationOf <$> (phrase "what is the duration of" *> slot ref)
  , Gap <$> (phrase "what is the gap between" *> slot ref) <*> (word "and" *> slot ref)
  , Select False <$> (phrase "which events match" *> condition)
  , Select True <$> (phrase "how many events match" *> condition)
  , Quantify <$> (word "does" *> choiceWords [("every",True),("some",False)] <* phrase "event matching") <*> condition <*> (word "satisfy" *> condition)
  , Free <$> (phrase "which intervals are free" *> option Missing (word "within" *> slot windowValue))
  , Earliest <$> (phrase "what is the earliest available interval" *> parameters)
  , Conflicts False <$> (phrase "which event pairs clash" *> option Missing (word "within" *> slot windowValue)) <*> pure (Known "pairs")
  , Conflicts True <$> (phrase "how many overlaps occur" *> option Missing (word "within" *> slot windowValue)) <*> option Missing (symbol "," *> word "counting" *> slot (choiceWords [("pairs","pairs"),("events","events")]))
  , Feasible <$> (phrase "can an event" *> parameters <* word "fit") <*> options
  , MinimumCost <$> (phrase "what is the minimum movement cost to fit an event" *> parameters) <*> options
  , RepairPossible <$> (phrase "can clashes" *> option Missing (word "on" *> dateSlot) <* phrase "be removed") <*> options ]
parseEntries :: String -> Either String [Entry]
parseEntries source
  | length source>65536=Left "Entry exceeds the 64 KiB parser limit."
  | otherwise=case nub [x|(x,"")<-readP_to_S (skipSpaces *> many1 ((command <* symbol ".") <|> (question <* symbol "?")) <* eof) source] of
      []->Left "Invalid Calendar controlled language. Commands require a period; questions require ?. Undo and atomic batches are not supported."
      xs->Right xs
parseEntry :: String -> Either String Entry
parseEntry source=do xs<-parseEntries source;case xs of [x]->Right x;_->Left "Choose an explicit Boolean grouping."

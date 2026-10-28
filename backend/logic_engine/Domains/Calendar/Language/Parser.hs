{-# LANGUAGE NoMonomorphismRestriction, FlexibleContexts #-}
{-# LANGUAGE FlexibleContexts #-}
module Domains.Calendar.Language.Parser (parseEntries,parseEntry,parseJointList,parseJointWindow) where
import Control.Applicative ((<|>))
import Control.Monad (guard,void)
import Data.Char (isAlphaNum,toLower)
import Data.List (nub,sort)
import Data.Time (Day,defaultTimeLocale,parseTimeM)
import qualified Data.Aeson as J
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.ByteString.Lazy as B
import qualified Text.ParserCombinators.ReadP as R
import ControlledLanguage.Parsing
import Domains.Calendar.Language.Syntax

asciiDigit c=c>='0'&&c<='9'
lexeme p=p <* skipSpaces
word t=keywordToken t $ lexeme $ void (traverse (\c->satisfy ((==c).toLower)) t) <* (look >>= \r->guard (null r || not (isAlphaNum (head r))))
phrase=mapM_ word . words
symbol=lexeme . string
number=lexeme $ do ds<-munch1 (\c->c>='0'&&c<='9');ensure (length ds==1 || head ds/='0') "Leading zeroes are not allowed in a number.";pure (read ds::Integer)
integer=do n<-number;ensure (n<toInteger (maxBound::Int)) "Identifier exceeds the supported integer range.";pure (fromInteger n)
quoted=labelled "a double-quoted string" $ lexeme $ do
  raw<-gather (char '"' *> many (void (char '\\' *> get) <|> void (satisfy (\c->c/='"'&&c/='\\'&&c>=' '))) <* char '"')
  case J.eitherDecode (B.fromStrict (T.encodeUtf8 (T.pack (fst raw)))) of Right x->pure x;Left message->fail ("Invalid quoted string: "++message)
choiceWords xs=choice [v <$ phrase k | (k,v)<-xs]
slot p=(Missing <$ word "unspecified") <|> (Known <$> p)
date=labelled "a weekday, today, tomorrow, or YYYY-MM-DD" $ choiceWords (zip ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"] (map Weekday [0..6]))
  <|> (Today <$ word "today") <|> (Tomorrow <$ word "tomorrow") <|> do
    t<-lexeme (count 4 (satisfy asciiDigit) >>= \y->char '-' *> count 2 (satisfy asciiDigit) >>= \m->char '-' *> count 2 (satisfy asciiDigit) >>= \d->pure (y++"-"++m++"-"++d))
    ensure ((parseTimeM True defaultTimeLocale "%Y-%m-%d" t::Maybe Day)/=Nothing && take 4 t/="0000") "Invalid date; use a real date in YYYY-MM-DD format.";pure (DateLiteral t)
dateSlot=(Missing <$ phrase "unspecified date") <|> (Known <$> date)
clock=labelled "a time in HH:MM format (00:00–23:59)" $ do h<-count 2 (satisfy asciiDigit);char ':';m<-count 2 (satisfy asciiDigit);ensure (read h<24 && read m<60) "Invalid time; hours must be 00–23 and minutes 00–59.";skipSpaces;pure (read h*60+read m)
clockTerm=(Clock <$> clock) <|> do phrase "one of";symbol "[";xs<-sepBy1 clock (symbol ",");symbol "]";ensure (length xs>=2&&length xs==length(nub xs)) "Clock choices require at least two distinct times.";pure (ClockChoices (sort xs))
offset=do sign<-lexeme (satisfy (`elem` "+-"));h<-count 2 (satisfy asciiDigit);char ':';m<-count 2 (satisfy asciiDigit);skipSpaces;ensure (read h<=14&&read m<60) "Invalid UTC offset; hours must be 00–14 and minutes 00–59.";pure ((if sign=='-' then -1 else 1)*(read h*60+read m)*60)
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
  ensure (length names==length(nub names)) "Description fields must not be repeated.";ensure (names==sortFields names) "Description fields must be ordered title, location, description, importance, start date.";pure(Described unique ds)
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
  t<-parameters;fs<-creationFields;pure t{fields=fs}
creationFields=do
  fs<-option [] (word "with" *> sepBy1 field (word "and"));let names=map fst fs
  ensure (length names==length(nub names)) "Creation fields must not be repeated.";ensure (names==sortFields names) "Creation fields must be ordered title, location, description, importance.";pure fs
  where field=((,) <$> textField <*> slot quoted) <|> ((,) "importance" . fmapSlot show <$> (word "importance" *> slot importance))
fmapSlot f (Known x)=Known(f x);fmapSlot _ Missing=Missing
jointWindow=(AnyWindows <$> (phrase "any of" *> between (symbol "[") (symbol "]") (sepBy1 (slot windowValue) (symbol ";"))))
  <|> (SingleWindow . Known <$> windowValue)
jointItem=JointItem <$> (word "event" *> option Missing (word "lasting" *> slot durationValue))
  <*> option Missing (word "within" *> slot jointWindow) <*> creationFields
jointList=do
 xs<-between (symbol "[") (symbol "]") (sepBy1 jointItem (symbol ";"))
 ensure (length xs>=2 && length xs<=16) "Joint scheduling requires between two and sixteen events.";pure xs
jointOptions=(,) <$> option False (True <$ (symbol "," *> phrase "on different dates"))
  <*> option False (symbol "," *> word "choosing" *> choiceWords [("ask",False),("earliest in listed order",True)])
jointSentence constructor=do
 xs<-slot jointList;(different,earliest)<-jointOptions;pure(constructor xs different earliest)
freeWindow=do
 w<-slot windowValue
 ensure (case w of Known (Starting _)->False;_->True) "A free window needs an end; starting at is not a bounded window.";pure w
parseJointList text=case parseEntry ("schedule events jointly "++text++".") of
 Right [JointSchedule (Known xs) False False]->Just xs;_->Nothing
parseJointWindow text=case parseEntry ("schedule events jointly [event within "++text++"; event].") of
 Right [JointSchedule (Known [JointItem Missing (Known w) [], JointItem Missing Missing []]) False False]->Just w;_->Nothing
command=choice
  [ phrase "schedule events jointly" *> jointSentence JointSchedule
  , FreeWindow <$> (phrase "free window" *> freeWindow) <*> options
  , createSentence <$> (phrase "create event from" *> slot moment) <*> (word "to" *> slot moment) <*> creationFields
  , Delete <$> (word "delete" *> slot ref)
  , SetText <$> (word "set" *> textField <* word "of") <*> slot ref <*> (word "to" *> slot quoted)
  , SetImportance <$> (phrase "set importance of" *> slot ref) <*> (word "to" *> slot importance)
  , SetInterval <$> (phrase "set interval of" *> slot ref) <*> (word "from" *> slot moment) <*> (word "to" *> slot moment)
  , Schedule <$> (phrase "schedule event" *> task)
  , Insert <$> (phrase "make room for event" *> task) <*> options
  , Repair <$> (phrase "remove clashes" *> option Missing (word "on" *> dateSlot)) <*> options ]
question=choice
  [ do phrase "can events";xs<-slot jointList;phrase "be scheduled jointly";(d,e)<-jointOptions;pure(JointPossible xs d e)
  , FreePossible <$> (phrase "can window" *> freeWindow <* phrase "be freed") <*> options
  , FreeCost <$> (phrase "what is the minimum movement cost to free window" *> freeWindow) <*> options
  , Exists <$> (word "does" *> slot (char '#' *> integer) <* word "exist")
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
  | otherwise=case nub [x|(x,"")<-R.readP_to_S (skipSpaces *> many1 ((command <* symbol ".") <|> (question <* symbol "?")) <* eof) source] of
      []->Left (diagnose "Calendar" (skipSpaces *> many1 ((command <* symbol ".") <|> (question <* symbol "?")) <* eof) source)
      xs->Right xs
parseEntry :: String -> Either String Entry
parseEntry source=do xs<-parseEntries source;case xs of [x]->Right x;_->Left "Choose an explicit Boolean grouping."

-- Preserve the serialized form of existing pending creations.
createSentence a b []=Create a b
createSentence a b fs=CreateWithFields a b fs

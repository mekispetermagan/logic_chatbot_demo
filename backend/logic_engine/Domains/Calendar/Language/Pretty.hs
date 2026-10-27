{-# LANGUAGE FlexibleContexts #-}
module Domains.Calendar.Language.Pretty where
import Data.List(intercalate)
import Domains.Calendar.Language.Syntax
import qualified Data.Aeson as J
import qualified Data.ByteString.Lazy as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
quoted :: String -> String
quoted=T.unpack . T.decodeUtf8 . B.toStrict . J.encode
slotText f Missing="unspecified"
slotText f (Known x)=f x
dateText(DateLiteral x)=x
dateText(Weekday n)=["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]!!n
dateText Today="today";dateText Tomorrow="tomorrow"
dateSlot Missing="unspecified date";dateSlot(Known x)=dateText x
clockText(Clock n)=pad(n `div` 60)++":"++pad(n `mod` 60) where pad x=if x<10 then '0':show x else show x
clockText(ClockChoices xs)="one of ["++intercalate ", " (map (clockText.Clock) xs)++"]"
momentText(Moment d t z)=dateSlot d++" at "++slotText clockText t++maybe "" (\n->" offset "++(if n<0 then "-" else "+")++clockText(Clock(abs n `div` 60))) z
windowText SelectedWeek="selected week"
windowText(OnDate d p a b)=dateSlot d++maybe "" (' ':) p++maybe "" (\(inc,t)->(if inc then " at or after " else " after ")++slotText clockText t) a++maybe "" (\(inc,t)->(if inc then " by " else " before ")++slotText clockText t) b
windowText(Between a b)="interval from "++slotText momentText a++" to "++slotText momentText b
windowText(Starting a)="starting at "++slotText momentText a
refText(Handle n)='#':show n
refText It="it"
refText(Described u ds)="the "++(if u then "unique " else "")++"event with "++intercalate " and " [k++" "++v k x|(k,x)<-ds]
  where v "importance" x=importanceText(read x);v "start date" x=dateText(read x);v _ x=quoted x
importanceText n=["normal","important","critical"]!!n
comparisonText Equal="is";comparisonText AtLeast="is at least";comparisonText AtMost="is at most"
durationText n=show n++if n==1 then " minute" else " minutes"
conditionText c=case c of
 TrueCondition->"true";UnknownCondition->"unspecified"
 TextIs k v->k++" is "++slotText quoted v
 ImportanceIs op v->"importance "++comparisonText op++" "++slotText importanceText v
 StartsOn d->"starts on "++dateSlot d
 Within w->"within "++slotText windowText w
 OverlapsWindow w->"overlaps "++slotText windowText w
 Relation k r->k++" event "++slotText refText r
 DurationIs op d->"duration "++comparisonText op++" "++slotText durationText d
 HasClash w->"has a clash within "++slotText windowText w
 Not a->"(not "++conditionText a++")"
 And a b->"("++conditionText a++" and "++conditionText b++")"
 Or a b->"("++conditionText a++" or "++conditionText b++")"
optionsText(Options t p order)=", moving up to "++slotText (\i->if i<0 then "none" else importanceText i) t++", protecting "++slotText (\rs->"["++intercalate ", " (map refText rs)++"]") p++", choosing "++if order then "preserve original order" else "ask"
parameters t=" lasting "++slotText durationText(duration t)++" within "++slotText windowText(window t)
taskText t=parameters t++" with "++intercalate " and " [k++" "++slotText (if k=="importance" then importanceText.read else quoted) (maybe(Known def) id (lookup k(fields t)))|(k,def)<-[("title",""),("location",""),("description",""),("importance","0")]]
sentenceText s=body++if isQuestion s then "?" else "."
 where
 body=case s of
  Create a b->"create event from "++m a++" to "++m b
  Delete r->"delete "++rtext r
  SetText k r v->"set "++k++" of "++rtext r++" to "++slotText quoted v
  SetImportance r v->"set importance of "++rtext r++" to "++slotText importanceText v
  SetInterval r a b->"set interval of "++rtext r++" from "++m a++" to "++m b
  Schedule t->"schedule event"++taskText t
  Insert t o->"make room for event"++taskText t++optionsText o
  Repair d o->"remove clashes on "++dateSlot d++optionsText o
  Exists i->"does "++slotText (('#':).show) i++" exist"
  Query f r->"what is the "++slotText id f++" of "++rtext r
  Check r c->"does "++rtext r++" satisfy "++conditionText c
  DurationOf r->"what is the duration of "++rtext r
  Gap r t->"what is the gap between "++rtext r++" and "++rtext t
  Select n c->(if n then "how many" else "which")++" events match "++conditionText c
  Quantify all p q->"does "++(if all then "every" else "some")++" event matching "++conditionText p++" satisfy "++conditionText q
  Free w->"which intervals are free within "++slotText windowText w
  Earliest t->"what is the earliest available interval"++parameters t
  Conflicts n w u->(if n then "how many overlaps occur" else "which event pairs clash")++" within "++slotText windowText w++if n then ", counting "++slotText id u else ""
  Feasible t o->"can an event"++parameters t++" fit"++optionsText o
  MinimumCost t o->"what is the minimum movement cost to fit an event"++parameters t++optionsText o
  RepairPossible d o->"can clashes on "++dateSlot d++" be removed"++optionsText o
 m=slotText momentText;rtext=slotText refText
entryText=intercalate " " . map sentenceText

{-# LANGUAGE FlexibleContexts #-}
module Domains.Calendar.Language.Resolution where
import Control.Monad (when,unless,forM,forM_,filterM,foldM)
import Control.Monad.Except
import Control.Monad.State.Strict
import Data.Aeson
import Data.List(nub,sortOn)
import qualified Data.Map.Strict as M
import Data.Time hiding (midnight)
import Text.Read(readMaybe)
import qualified Data.Text as T
import Domains.Calendar.Types
import Domains.Calendar.Language.Syntax
import Domains.Calendar.Language.Parser(parseEntry)
import Domains.Calendar.Language.Pretty
import Domains.Calendar.Language.State

fieldValue :: Event -> String -> String
fieldValue e k=case k of "title"->title e;"location"->location e;"description"->description e;"importance"->show(importance e);_->""
textValue k s= valueAt k s ("What should "++k++" be? Empty text is allowed.") "text" []
numberValue k s message=valueAt k s message "number" []
importanceValue k s movement=do
 n<-valueAt k s (if movement then "What maximum importance may be moved? None, Normal, Important or Critical?" else "Which importance: Normal, Important or Critical?") "importance"
   [(if i<0 then "None" else importanceName i,toJSON i)|i<-[if movement then -1 else 0 ..2]]
 if n>2 || n<(if movement then -1 else 0) then need k "Choose a listed importance." "importance" [(importanceName i,toJSON i)|i<-[0..2]] else pure n
exprValue :: String -> Slot a -> (a->String) -> (String->Maybe a) -> String -> String -> Eval a
exprValue k initial render parse message typ=do
 supplied<-gets (M.lookup k.answers)
 case supplied of
  Just (String raw)->case parse (showText raw) of Just x->logValue x;Nothing->need k ("Invalid value. "++message) typ []
  Just _->need k message typ []
  Nothing->case initial of Known x->logValue x;Missing->need k message typ []
 where
  showText=T.unpack
  logValue x=modify(\w->w{parameterLog=M.insert k (toJSON(render x))(parameterLog w)})>>pure x
parseDate s=case parseEntry("Remove clashes on "++s++".") of Right [Repair(Known d) _]->Just d;_->Nothing
parseMoment s=case parseEntry("Create event from "++s++" to unspecified.") of Right [Create(Known t) _]->Just t;_->Nothing
parseWindow s = case parseEntry ("Schedule event within "++s++".") of
 Right [Schedule t] -> case window t of Known v -> Just v; _ -> Nothing
 _ -> Nothing
parseCondition s=case parseEntry("How many events match "++s++"?") of Right [Select _ c]->Just c;_->Nothing
resolveDate :: Bool -> String -> Slot DateTerm -> Eval Day
resolveDate closing k slot=do
 d<-exprValue k slot dateText parseDate "Which date in the selected week?" "date"
 c<-gets context
 let base=localDate c(weekStart c)
     day=case d of DateLiteral x->read x;Weekday n->addDays(fromIntegral n)base;Today->localDate c(frozenNow c);Tomorrow->addDays 1(localDate c(frozenNow c))
 when(day<base || day>addDays (if closing then 7 else 6) base)(invalid "Date is outside the selected week.")
 pure day
resolveClock :: String -> Slot Clock -> (Int->Bool) -> Eval Int
resolveClock k slot admissible=do
 n<-resolveClockValue k slot admissible
 modify(\w->w{parameterLog=M.insert k(toJSON(clockText(Clock n)))(parameterLog w)})
 pure n
resolveClockValue k slot admissible=do
 supplied<-gets(M.lookup k.answers)
 case supplied of
  Just v -> case fromJSON v of
   Success n | n>=0 && n<1440 && admissible n && listed n -> pure n
   _ -> case v of
    String t -> case parseMoment ("monday at " ++ T.unpack t) of
     Just (Moment _ (Known (Clock n)) _) | admissible n && listed n -> pure n
     _ -> question []
    _ -> question []
  Nothing->case slot of
   Known(Clock n)|admissible n->pure n
   Known(ClockChoices ns)->case filter admissible ns of [n]->pure n;xs->question xs
   Known _->invalid "Clock does not lie in the stated period."
   Missing->question []
 where listed n=case slot of Known(ClockChoices ns)->n `elem` ns;_->True
       question ns=need k "Which local time do you mean?" "clock" [(clockText(Clock n),toJSON n)|n<-ns]
resolveMoment :: Bool -> String -> Slot Moment -> Eval Instant
resolveMoment closing k slot=do
 Moment d t z<-exprValue k slot momentText parseMoment "Give a date and time, for example thursday at 09:00." "moment"
 day<-resolveDate closing (k++".date") d
 mins<-resolveClock(k++".clock") t (const True)
 c<-gets context
 let candidates=filter (\v->maybe True(==offsetAt c v)z)(localCandidates c day mins)
 when(null candidates)(invalid "This local time/offset does not exist in Europe/Budapest.")
 v<-case candidates of
  [v]->pure v
  xs->valueAt (k++".occurrence") Missing "This time occurs twice. Choose the UTC offset/occurrence." "choice" [(timeText c v,toJSON v)|v<-xs]
 when(v `notElem` candidates)(invalid "Choose a listed time occurrence.")
 when(v<weekStart c || v>weekEnd c || (not closing && v==weekEnd c))(invalid "Endpoint is outside the selected week.")
 pure v
resolveWindow :: Bool -> String -> Slot Window -> Eval (Instant,Instant,Maybe Instant)
resolveWindow placement k slot=do
 win<-exprValue k slot windowText parseWindow "What is the allowed interval? For example thursday morning or selected week." "window"
 c<-gets context
 case win of
  SelectedWeek->pure(weekStart c,weekEnd c,Nothing)
  Starting t->if not placement then invalid "starting at is a placement, not a containment/counting window." else do a<-resolveMoment False(k++".start")t;pure(a,weekEnd c,Just a)
  Between a b->do x<-resolveMoment False(k++".start")a;y<-resolveMoment True(k++".end")b;validate x y;pure(x,y,Nothing)
  OnDate d period lo hi->do
   day<-resolveDate False(k++".date")d
   let (a,b)=case period of Just "night"->(1320,1800);Just "dawn"->(360,540);Just "morning"->(540,720);Just "lunchtime"->(720,780);Just "afternoon"->(780,1080);Just "evening"->(1080,1320);_->(0,1440)
       boundary n=case localCandidates c (addDays(fromIntegral(n `div` 1440))day)(n `mod` 1440) of v:_->v;_->midnight c day
       expand n=if period==Just "night" && n<=360 then n+1440 else n
       valid n=let x=expand n in x>=a && x<=b
       boundaryValue key n=case localCandidates c (addDays(fromIntegral(n `div` 1440))day)(n `mod` 1440) of
        []->invalid "This window boundary does not exist in Europe/Budapest."
        [x]->pure x
        xs->do
         x<-valueAt key Missing "This window boundary occurs twice. Choose the UTC offset/occurrence." "choice" [(timeText c x,toJSON x)|x<-xs]
         if x `elem` xs then pure x else need key "Choose a listed boundary occurrence." "choice" [(timeText c x,toJSON x)|x<-xs]
   lower<-case lo of Nothing->pure(boundary a);Just(inc,t)->do n<-resolveClock(k++".after")t valid;x<-boundaryValue(k++".after.occurrence")(expand n);pure(x+if inc then 0 else 1)
   upper<-case hi of Nothing->pure(boundary b);Just(inc,t)->do n<-resolveClock(k++".before")t valid;x<-boundaryValue(k++".before.occurrence")(expand n);pure(x-if inc then 0 else 1)
   let x=max(weekStart c)(max(boundary a)lower);y=min(weekEnd c)(min(boundary b)upper)
   validate x y;pure(x,y,Nothing)
 where validate a b=when(b<=a)(invalid "The allowed interval is empty or reversed.")
getEvent :: Int -> Eval Event
getEvent n=gets current >>= \es->case filter((==n).handle)es of [e]->pure e;_->invalid("No in-scope event #"++show n)
resolveRef :: String -> Slot Ref -> Eval Event
resolveRef k initial=do
 cached<-gets(M.lookup ("resolved:"++k).answers)
 case cached of
  Just v->case fromJSON v of Success n->getEvent n >>= done [];_->invalid "Invalid saved reference."
  Nothing->do
   supplied<-gets(M.lookup k.answers)
   ref <- case supplied of
    Just v -> case fromJSON v of Success n -> pure (Handle n); _ -> invalid "Expected an event handle."
    Nothing -> case initial of
     Known r -> pure r
     Missing -> Handle <$> valueAt k Missing "Which event handle?" "reference" []
   (e,fs)<-case ref of
    Handle n->do e<-getEvent n;pure(e,[])
    It->do
     r<-gets ranking;es<-gets current
     let eligible=[(entryAge m,utteranceAge m,mentioned m)|m<-r,any((==mentioned m).handle)es]
     when(null eligible)(invalid "No event antecedent for it.")
     let age=minimum[(a,b)|(a,b,_)<-eligible]
     e<-choose [n|(a,b,n)<-eligible,(a,b)==age];pure(e,[])
    Described unique ds->do
     c<-gets context;es<-gets current;r<-gets ranking
     let ground (f,v)=if f=="start date" then case readMaybe v of Just d->(f,show(DateLiteral(show(dateGround c d))));_->(f,v) else (f,v)
         grounded=map ground ds
         matches e=all(\(f,v)->if f=="start date" then case readMaybe v of Just dt->localDate c(start e)==dateGround c dt;_->False else fieldValue e f==v)grounded
         candidates=filter matches es
         score e=sequence [case [10*entryAge m+utteranceAge m|m<-r,mentioned m==handle e,(f,v)`elem`facts m] of []->Nothing;xs->Just(minimum xs)|(f,v)<-grounded]
         scored=[(handle e,sum xs)|e<-candidates,Just xs<-[score e]]
         selected=if unique||null scored then map handle candidates else let best=minimum(map snd scored) in [n|(n,x)<-scored,x-best<length ds+1]
     e<-choose selected;pure(e,grounded)
   modify(\w->w{answers=M.insert("resolved:"++k)(toJSON(handle e))(answers w)})
   done fs e
 where
  done fs e=modify(\w->w{parameterLog=M.insert k(toJSON(handle e))(parameterLog w)})>>remember e fs>>pure e
  choose ns = case nub ns of
   [] -> invalid "No matching event."
   [n] -> getEvent n
   xs -> do
    n <- valueAt (k++".choice") Missing "Which event do you mean?" "choice" [("#"++show n,toJSON n)|n<-xs]
    if n `elem` xs then getEvent n else need (k++".choice") "Choose a listed event." "choice" [(show n,toJSON n)|n<-xs]
  dateGround c d=case d of DateLiteral x->read x;Weekday n->addDays(fromIntegral n)(localDate c(weekStart c));Today->localDate c(frozenNow c);Tomorrow->addDays 1(localDate c(frozenNow c))
resolveProtected :: String -> Slot [Ref] -> Eval [Int]
resolveProtected k initial=do
 supplied<-gets(M.lookup k.answers)
 refs <- case (supplied,initial) of
  (Nothing,Known rs) -> pure rs
  _ -> do
   raw <- valueAt k Missing "Which events must stay fixed? Enter handles as a JSON list, or []." "handles" []
   pure (map Handle (raw :: [Int]))
 ids<-mapM(\(i,r)->handle <$> resolveRef(k++"."++show i)(Known r))(zip[0::Int ..]refs)
 when(length ids/=length(nub ids))(invalid "Duplicate resolved protected events.")
 modify(\w->w{parameterLog=M.insert k(toJSON ids)(parameterLog w)})
 pure ids
validateInterval :: Instant -> Instant -> Eval ()
validateInterval a b=do c<-gets context;when(b<=a||a<weekStart c||b>weekEnd c)(invalid "End must be after start and both endpoints must stay inside the selected week.")
normalizeAssignment :: String -> Instant -> Instant -> Eval (Instant,Instant)
normalizeAssignment k a b=do
 validateInterval a b
 let x=roundTime a;y=max(x+tick)(roundTime b)
 when((a,b)/=(x,y))$ do
  yes<-valueAt(k++".rounding") Missing "Approve rounding these interval endpoints to the five-minute grid?" "choice" [("Approve",toJSON True)]
  unless yes(invalid "Rounding was not approved.")
 validateInterval x y;pure(x,y)
resolveDuration k slot=do
 n<-numberValue k slot "How many elapsed minutes? Use a positive multiple of five."
 when(n<=0||n `mod` 5/=0)(need k "Choose a positive duration in five-minute increments." "number" [])
 pure(n*minute)

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
module Domains.Calendar.Language.Evaluation where
import Control.Monad (when,unless,forM,forM_,filterM,foldM)
import Control.Monad.Except
import Control.Monad.State.Strict
import Data.Aeson hiding (Options)
import Data.List(nub,sortOn,intercalate)
import Data.Maybe(fromMaybe)
import qualified Data.Map.Strict as M
import Data.Time(addDays)
import Domains.Calendar.Types
import Domains.Calendar.Language.Syntax
import Domains.Calendar.Language.State
import Domains.Calendar.Language.Resolution
import Domains.Calendar.Language.Pretty
import Domains.Calendar.Language.Queries(query,intervalText)
import Domains.Calendar.Language.Planning

replace e=modify(\w->w{current=e:filter((/=handle e).handle)(current w)})
editable e=when(recurring e)(invalid "Recurring events are read-only.")
create a b=do
 n<-gets nextHandle
 when(n==maxBound)(invalid "Handle allocation exhausted.")
 let e=Event n Nothing "" "" "" (Just "10") a b False False False
 modify(\w->w{nextHandle=n+1,current=e:current w});remember e [];pure e
modifyText field value e=case field of "title"->e{title=value};"location"->e{location=value};_->e{description=value}
resolveFields :: String -> Task -> Event -> Eval Event
resolveFields k task e=do
 result<-foldM set e (fields task)
 remember result [(f,case f of "importance"->show(importance result);_->case f of "title"->title result;"location"->location result;_->description result)|(f,_)<-fields task]
 pure result
 where set e (field,s)=if field=="importance" then do
        let initial=case s of Known t->Known(read t);Missing->Missing
        n<-importanceValue(k++".importance")initial False;pure e{colorId=Just(importanceColor n)}
       else do v<-textValue(k++"."++field)s;when(length v>(if field=="description" then 8192 else 1024))(invalid "Text exceeds Calendar field limits.");pure(modifyText field v e)
runSentence :: String -> Sentence -> Eval String
runSentence k s=do
 result<-runSentenceBody k s
 es<-gets current;c<-gets context
 let planning=case s of Schedule _->True;Insert _ _->True;Repair _ _->True;Feasible _ _->True;MinimumCost _ _->True;RepairPossible _ _->True;_->False
     fixed=["#"++show(handle e)|e<-es,not(movablePlacement c e(normalized e))]
 pure(result++if planning && not(null fixed) then "\nFixed because normalization leaves the date/period envelope: "++intercalate ", " fixed++". Original exact intervals are retained; explicit correction is available." else "")
runSentenceBody k s=case s of
 Create a b->runSentenceBody k(CreateWithFields a b [])
 CreateWithFields a b fs->do
  x<-resolveMoment False(k++".start")a;y<-resolveMoment True(k++".end")b;(lo,hi)<-normalizeAssignment k x y
  n<-gets nextHandle
  template<-resolveFields(k++".fields")(Task Missing Missing fs)(Event n Nothing "" "" "" (Just "10") lo hi False False False)
  e<-create lo hi;replace template;remember template [];pure("Created "++show(handle e))
 Delete r->do e<-resolveRef(k++".subject")r;editable e;modify(\w->w{current=filter((/=handle e).handle)(current w)});pure("Deleted #"++show(handle e))
 SetText field r v->do
  e<-resolveRef(k++".subject")r;editable e;x<-textValue(k++".value")v
  when(length x>(if field=="description" then 8192 else 1024))(invalid "Text exceeds field limit.")
  replace(modifyText field x e);remember(modifyText field x e)[(field,x)];pure("Set "++field++" of #"++show(handle e)++" to "++quoted x)
 SetImportance r i->do e<-resolveRef(k++".subject")r;editable e;n<-importanceValue(k++".value")i False;replace e{colorId=Just(importanceColor n)};remember e[("importance",show n)];pure("Set importance to "++importanceName n)
 SetInterval r a b->do
  e<-resolveRef(k++".subject")r;editable e;x<-resolveMoment False(k++".start")a;y<-resolveMoment True(k++".end")b
  (lo,hi)<-normalizeAssignment k x y;replace e{start=lo,end=hi};pure "Interval assigned; overlaps are permitted for explicit assignments."
 Schedule t->placement k t Nothing False False
 Insert t opts->placement k t(Just opts)False False
 Repair d opts->repair k d opts False
 Feasible t opts->placement k t(Just opts)True False
 MinimumCost t opts->placement k t(Just opts)True True
 RepairPossible d opts->repair k d opts True
 _->query k s
placement :: String -> Task -> Maybe Options -> Bool -> Bool -> Eval String
placement k task opts hypothetical minimumCost=do
 dur<-resolveDuration(k++".duration")(duration task)
 bounds@(a,b,f)<-resolveWindow True(k++".window")(window task)
 n<-gets nextHandle
 template<-resolveFields(k++".fields")task(Event n Nothing "" "" "" (Just "10") 0 dur False False False)
 prot<-maybe(pure[])(resolveProtected(k++".protected").protected)opts
 es<-gets current;c<-gets context
 fixed<-case f of
  Just x | x `mod` tick/=0->do (u,_)<-normalizeAssignment(k++".fixed")x(x+dur);pure(Just u)
  _->pure f
 let effective=(maybe a (const(fromMaybe a fixed)) f,b,fixed)
 case firstFree es effective dur of
  Just t->finish template es t "No existing event moves; minimum movement cost is 0."
  Nothing->case opts of
   Nothing->invalid "No free interval in the specified five-minute model. Revise the window/duration or request Make room for event."
   Just o->do
    level<-movementLevel(k++".threshold")(threshold o) hypothetical
    let can=[handle e|e<-es,importance e<=level,handle e `notElem`prot,not(recurring e)]
    solve k es can [] (Just template)effective
    choosePlan k o hypothetical minimumCost es (Just template)
 where
  finish template es t msg=if hypothetical then pure("true; "++msg++" Witness start: "++show t) else do
   replace template{start=t,end=t+end template};modify(\w->w{nextHandle=nextHandle w+1});remember template [];c<-gets context
   pure(msg++"\nNew #"++show(handle template)++": "++intervalText c template{start=t,end=t+end template})
repair :: String -> Slot DateTerm -> Options -> Bool -> Eval String
repair k d o hypothetical=do
 day<-resolveDate False(k++".date")d
 prot<-resolveProtected(k++".protected")(protected o)
 es<-gets current;c<-gets context
 let bounds=(midnight c day,midnight c(addDays 1 day));targets=[handle e|e<-es,overlaps(interval e)bounds]
 if validPairs Nothing targets es es then pure "No clashes in either normalized or exact intervals; no changes needed."
 else do
  level<-movementLevel(k++".threshold")(threshold o) hypothetical
  let can=[handle e|e<-es,handle e `elem` targets,importance e<=level,handle e `notElem`prot,not(recurring e)]
  solve k es can targets Nothing(weekStart c,weekEnd c,Nothing)
  choosePlan k o hypothetical False es Nothing
choosePlan :: String -> Options -> Bool -> Bool -> [Event] -> Maybe Event -> Eval String
choosePlan k o hypothetical minimumCost old new=do
 ps<-gets bestPlans;limited<-gets searchIncomplete;c<-gets context
 if null ps then
  if limited then throwError(Limited "Search limit reached; feasibility unresolved.")
  else if hypothetical then pure((if minimumCost then "infeasible" else "false")++"; exhaustive search within the stated grid, date/period and movement constraints.")
  else invalid "No solution exists within the stated grid, date/period and movement constraints. Revise a constraint explicitly."
 else do
  let orderGood es=and[start a<=start b|a<-es,b<-es,Just x<-[findOld a],Just y<-[findOld b],start x<start y]
      findOld e=case filter((==handle e).handle)old of x:_->Just x;_->Nothing
      preferred=if preserveOrder o then filter orderGood ps else ps
      choices=if null preferred then ps else preferred
      describe es=intercalate "\n"["#"++show(handle e)++" "++intervalText c e++maybe " (new)" (\prior->if interval prior==interval e then " (unchanged)" else " (was "++intervalText c prior++"; weight "++show((importance prior+1)^2)++", cost "++show(fromRational(toRational(movementCost [prior] [e])/12)::Double)++")")(findOld e)|e<-sortOn handle es,maybe True(\x->interval x/=interval e)(findOld e)]
      cost=case ps of es:_->fromRational(toRational(movementCost old es)/12)::Double
      status=if limited then "Feasible candidate; optimum not established (search limit; sound movement-cost lower bound 0)." else "Proven minimum weighted movement cost: "++show cost
  if hypothetical then pure((if minimumCost then status else "true; checked example witness from solver enumeration (hypothetical only, no preference or write permission). "++status)++"\n"++describe(head choices))
  else do
   i<-if preserveOrder o && null preferred then valueAt(k++".order")Missing "No optimum preserves original order. Choose a displayed optimum explicitly." "choice" [(describe es,toJSON i)|(i,es)<-zip[0::Int ..]ps] else if length choices==1 then pure 0 else valueAt(k++".plan")Missing (if limited then "Choose a checked candidate; optimum not established (lower bound 0)." else "Choose an equally optimal schedule (up to 64 examples; enumeration is not a preference).") "choice" [(describe es,toJSON i)|(i,es)<-zip[0::Int ..]choices]
   when(i<0||i>=length choices)(invalid "Choose a listed schedule.")
   let chosen=choices!!i
   modify(\w->w{current=chosen,nextHandle=nextHandle w+if new==Nothing then 0 else 1})
   forM_ chosen(\e->when(maybe True(\x->interval x/=interval e)(findOld e))(remember e []))
   pure(status++"\n"++describe chosen++"\nPolicy: importance weights 1/4/9; dates, period envelopes and normalized durations preserved.")

movementLevel k slot hypothetical = if not hypothetical then importanceValue k slot True else do
 n<-valueAt k slot "What maximum importance should I consider movable for this calculation?" "importance" [(if i<0 then "None" else importanceName i,toJSON i)|i<-[-1..2]]
 if n>=(-1) && n<=2 then pure n else need k "Choose None, Normal, Important or Critical for this hypothetical calculation." "importance" [(if i<0 then "None" else importanceName i,toJSON i)|i<-[-1..2]]

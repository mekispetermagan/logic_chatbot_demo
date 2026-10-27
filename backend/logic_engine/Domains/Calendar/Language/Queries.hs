{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
module Domains.Calendar.Language.Queries where
import Control.Monad (when,unless,forM,forM_,filterM,foldM)
import Control.Monad.State.Strict
import Data.Aeson
import Data.List(nub,sortOn,intercalate)
import Domains.Calendar.Types
import Domains.Calendar.Language.Syntax
import Domains.Calendar.Language.State
import Domains.Calendar.Language.Resolution
import Domains.Calendar.Language.Pretty
import Domains.Calendar.Language.Planning

type Predicate = Event -> Eval Bool
compareValue Equal=(==)
compareValue AtLeast=(>=)
compareValue AtMost=(<=)
compile :: Bool -> String -> Condition -> Eval Predicate
compile norm k initial=do
 condition<-exprValue k (Known initial) conditionText parseCondition "Which event condition should be tested?" "condition"
 compileResolved norm k condition
compileResolved norm k condition=case condition of
 UnknownCondition->do c<-exprValue k Missing conditionText parseCondition "Which event condition should be tested?" "condition";compile norm(k++".value")c
 Not a->do p<-compile norm(k++".not")a;pure(\e->not <$> p e)
 And a b->do p<-compile norm(k++".left")a;q<-compile norm(k++".right")b;pure(\e->(&&) <$> p e <*> q e)
 Or a b->do p<-compile norm(k++".left")a;q<-compile norm(k++".right")b;pure(\e->(||) <$> p e <*> q e)
 TrueCondition->checked(const True)
 TextIs f v->do x<-textValue(k++".value")v;checked(\e->fieldValue e f==x)
 ImportanceIs initial v->do op<-comparisonValue initial;x<-importanceValue(k++".value")v False;checked(\e->compareValue op(importance e)x)
 StartsOn d->do day<-resolveDate False(k++".date")d;c<-gets context;checked(\e->localDate c(start(project e))==day)
 Within w->do (a,b,_)<-resolveWindow False(k++".window")w;checked(\e->start(project e)>=a && end(project e)<=b)
 OverlapsWindow w->do (a,b,_)<-resolveWindow False(k++".window")w;checked(\e->overlaps(interval(project e))(a,b))
 Relation relation r->do target<-project <$> resolveRef(k++".target")r;checked(\raw->let e=project raw in case relation of "overlaps"->clash e target;"before"->end e<=start target;_->start e>=end target)
 DurationIs initial d->do op<-comparisonValue initial;dur<-resolveDuration(k++".duration")d;checked(\e->let p=project e in compareValue op(end p-start p)dur)
 HasClash w->do (a,b,_)<-resolveWindow False(k++".window")w;es<-gets current
                checked(\raw->let e=project raw in any(\x->let t=project x in handle x/=handle raw && max a(max(start e)(start t))<min b(min(end e)(end t)))es)
 where comparisonValue initial=valueAt(k++".comparison")(Known initial) "Which comparison?" "choice" [("Equal",toJSON Equal),("At least",toJSON AtLeast),("At most",toJSON AtMost)]
       project=if norm then normalized else id
       checked p=pure(\e->charge "check">>pure(p e))
truthText True="true";truthText False="false"
refLabel e="#"++show(handle e)
intervalText c e=timeText c(start e)++" – "++timeText c(end e)
modelNotice norm exact=if norm==exact then "" else "\nExact Google originals give: "++exact++" (rounding changes this answer)."
query :: String -> Sentence -> Eval String
query k s=case s of
 Exists n->do i<-numberValue k n "Which handle should be checked?";es<-gets current
              case filter((==i).handle)es of e:_->remember e []>>pure "true — in the selected week";_->pure "false — not in the selected week (not a claim about all Google events)"
 Query f r->do
  field<-valueAt(k++".field")f "Which field: title, location, description, importance, start, end or interval?" "choice" [(x,toJSON(x::String))|x<-["title","location","description","importance","start","end","interval"]]
  e<-resolveRef(k++".subject")r;c<-gets context
  let n=normalized e;timeValue p=case field of "start"->timeText c(start p);"end"->timeText c(end p);_->intervalText c p
  case field of
   "importance"->remember e [(field,show(importance e))]>>pure(importanceName(importance e))
   x | x `elem` ["title","location","description"]->remember e [(x,fieldValue e x)]>>pure(quoted(fieldValue e x))
   x | x `elem` ["start","end","interval"]->pure(timeValue n++modelNotice(timeValue n)(timeValue e))
   _->invalid "Invalid event field."
 Check r cond->do
  e<-resolveRef(k++".subject")r;p<-compile True(k++".condition")cond;q<-compile False(k++".condition")cond;a<-p e;b<-q e
  case cond of TextIs f (Known v)|fieldValue e f==v->remember e[(f,v)];_->pure()
  pure(truthText a++modelNotice(truthText a)(truthText b))
 DurationOf r->do
  e<-resolveRef(k++".subject")r;let dur x=show(fromRational(toRational(end x-start x)/toRational minute)::Double)++" minutes"
  pure(dur(normalized e)++modelNotice(dur(normalized e))(dur e))
 Gap a b->do
  e<-resolveRef(k++".first")a;t<-resolveRef(k++".second")b;c<-gets context
  let gap x y=if clash x y then "overlap: "++mins(min(end x)(end y)-max(start x)(start y))++" ("++timeText c(max(start x)(start y))++" – "++timeText c(min(end x)(end y))++")" else "gap: "++mins(max(start x)(start y)-min(end x)(end y))
  pure(gap(normalized e)(normalized t)++modelNotice(gap(normalized e)(normalized t))(gap e t))
 Select count cond->do
  p<-compile True(k++".condition")cond;q<-compile False(k++".condition")cond;es<-gets current
  xs<-filterM p es;ys<-filterM q es
  let render zs=if count then show(length zs) else show(sortOn id(map handle zs))
  pure(render xs++if map handle xs==map handle ys then "" else "\nNormalized handles "++show(map handle xs)++"; exact-original handles "++show(map handle ys)++"; exact answer "++render ys)
 Quantify every p q->do
  restrict<-compile True(k++".restriction")p;test<-compile True(k++".test")q
  exactRestrict<-compile False(k++".restriction")p;exactTest<-compile False(k++".test")q;es<-gets current
  xs<-filterM restrict es;ys<-filterM exactRestrict es
  a<-mapM test xs;b<-mapM exactTest ys
  let render zs bs=truthText((if every then and else or)bs)++if null zs then " — no matching events" else ""
  pure(render xs a++modelNotice(render xs a)(render ys b))
 Free w->do (a,b,_)<-resolveWindow False(k++".window")w;es<-gets current;c<-gets context
            pure(case freeIntervals es(a,b) of []->"No free intervals.";xs->intercalate "\n" [timeText c x++" – "++timeText c y| (x,y)<-xs])
 Earliest task->do
  dur<-resolveDuration(k++".duration")(duration task);bounds<-resolveWindow True(k++".window")(window task);es<-gets current;c<-gets context
  pure(case firstFree es bounds dur of Nothing->"No available interval in the specified five-minute search domain.";Just x->timeText c x++" – "++timeText c(x+dur))
 Conflicts count w u->do
  (a,b,_)<-resolveWindow False(k++".window")w
  unit<-if count then valueAt(k++".unit")u "Count clashing pairs or distinct affected events?" "choice" [("Pairs",toJSON("pairs"::String)),("Events",toJSON("events"::String))] else pure "pairs"
  unless(unit `elem` ["pairs","events"])(invalid "Choose pairs or events.")
  es<-gets current;c<-gets context
  let pairs project=[(handle x,handle y,max a(max(start ex)(start ey)),min b(min(end ex)(end ey)))|(i,x)<-zip[0::Int ..]es,y<-drop(i+1)es,let ex=project x,let ey=project y,max a(max(start ex)(start ey))<min b(min(end ex)(end ey))]
      render ps=if count then show(if unit=="pairs" then length ps else length(nub([x|(x,_,_,_)<-ps]++[y|(_,y,_,_)<-ps]))) else intercalate "\n"["#"++show x++" / #"++show y++": "++timeText c t++" – "++timeText c v|(x,y,t,v)<-ps]
      ps=pairs normalized;qs=pairs id
  forM_ [(x,y)| (i,x)<-zip[0::Int ..]es,y<-drop(i+1)es](\_->charge "check")
  pure(render ps++if ps==qs then "" else "\nExact-original conflicts: "++render qs++"; rounding changes witnesses or counts.")
 _->invalid "Not a direct Calendar question."
 where mins n=show(fromRational(toRational n/toRational minute)::Double)++" minutes"

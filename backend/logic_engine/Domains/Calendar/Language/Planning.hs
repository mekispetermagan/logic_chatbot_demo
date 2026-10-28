{-# LANGUAGE FlexibleContexts #-}
module Domains.Calendar.Language.Planning where
import Control.Monad (when,unless,forM,forM_,filterM,foldM)
import Control.Monad.Except
import Control.Monad.State.Strict
import Data.List(sortOn,nub)
import Data.Maybe(fromMaybe)
import Domains.Calendar.Types
import Domains.Calendar.Language.State

ceilTick x=((x+tick-1) `div` tick)*tick
-- Conservative occupancy: both exact originals and normalized projections.
freeIntervals :: [Event] -> (Instant,Instant) -> [(Instant,Instant)]
freeIntervals es (a,b)=gaps a (sortOn fst [(max a x,min b y)|e<-es,(x,y)<-[interval e,interval(normalized e)],x<b&&y>a])
 where gaps t []=[(t,b)|t<b]
       gaps t ((x,y):xs)=[(t,x)|x>t]++gaps(max t y)xs
firstFree es (a,b,fixed) dur=case [x|(lo,hi)<-freeIntervals es(a,b),let x=fromMaybe(ceilTick lo) fixed,x>=lo,x+dur<=hi] of x:_->Just x;_->Nothing
clash :: Event -> Event -> Bool
clash a b=overlaps(interval a)(interval b)
bothClash a b=clash a b || clash(normalized a)(normalized b)
requiredPairs :: Maybe Int -> [Int] -> [Event] -> Event -> Event -> Bool
requiredPairs new targets old a b
 | Just(handle a)==new || Just(handle b)==new=True
 | new/=Nothing=changed a || changed b
 | otherwise=handle a `elem` targets || handle b `elem` targets
 where changed e=case filter((==handle e).handle)old of [o]->interval o/=interval e;_->True
validPairs new targets old es=and[not(bothClash a b)| (i,a)<-zip[0::Int ..]es,b<-drop(i+1)es,requiredPairs new targets old a b]
movementCost old es=sum [(abs(start(normalized o)-start e) `div` tick)*toInteger((importance o+1)^2)|e<-es,o<-old,handle o==handle e,interval o/=interval e]
placements :: Event -> Bool -> Eval [Event]
placements e False=pure[e]
placements e True=do
 c<-gets context
 let n=normalized e;(a,b)=movementBounds c e;d=end n-start n
 if not(movablePlacement c e n) then pure[e] else do
  xs<-forM [ceilTick a,ceilTick a+tick..b-d]$ \t->do
   charge "candidate"
   let p=n{start=t,end=t+d}
   charge "check"
   charge "check"
   pure[p|t/=start n,movablePlacement c e p]
  pure(e:concat xs)
solve :: String -> [Event] -> [Int] -> [Int] -> Maybe Event -> (Instant,Instant,Maybe Instant) -> Eval ()
solve cacheKey old canMove targets new bounds=solveAvoid [] cacheKey old canMove targets new bounds
solveAvoid forbidden cacheKey old canMove targets new bounds=do
 cached<-gets bestFor
 unless(cached==cacheKey)$ do
  modify(\w->w{bestPlans=[],bestScore=Nothing,bestFor=cacheKey,searchIncomplete=False})
  let newId=handle <$> new
      changed e=case filter((==handle e).handle)old of [o]->interval o/=interval e;_->True
      required a b=requiredPairs newId targets old a b || (not(null forbidden) && (changed a || changed b))
  ds<-mapM(\e->do ps<-placements e(handle e `elem` canMove && not(recurring e));pure(e,[p|p<-ps,all (\w->not(overlaps(interval p)w || overlaps(interval(normalized p))w)) forbidden]))old
  allDomains<-case new of
   Nothing->pure ds
   Just e->do
    let (a,b,f)=bounds;d=end e-start e;ts=maybe [ceilTick a,ceilTick a+tick..b-d] (:[]) f
    ps<-forM ts$ \t->charge "candidate">>pure e{start=t,end=t+d}
    pure(ds++[(e,[p|p<-ps,start p>=a,end p<=b])])
  ctx<-gets context
  let ordered=sortOn(length.snd)allDomains
      walk assigned []=do
       -- Recompute complete constraints independently of the pruning path.
       valid<-and <$> forM assigned (\e->do
        charge "check";charge "check"
        pure(case filter((==handle e).handle)old of
          [prior]->interval prior==interval e || (handle e `elem` canMove && start e/=start(normalized prior) && start e `mod` tick==0 && movablePlacement ctx prior e && end e-start e==end(normalized prior)-start(normalized prior))
          _->case new of Just template->let (lo,hi,fixed)=bounds in handle e==handle template && inScope ctx e && start e>=lo && end e<=hi && maybe True(==start e)fixed && start e `mod` tick==0 && end e-start e==end template-start template;_->False))
       pairsValid<-and <$> forM [(a,b)|(i,a)<-zip[0::Int ..]assigned,b<-drop(i+1)assigned] (\(a,b)->do charge "check";charge "check";pure(not(required a b)||not(bothClash a b)))
       when(valid && pairsValid && all (\e->all (\w->not(overlaps(interval e)w || overlaps(interval(normalized e))w)) forbidden) assigned)$ do
        let score=(movementCost old assigned,maybe 0 (\e->start(head[p|p<-assigned,handle p==handle e]))new)
        prior<-gets bestScore
        case prior of
         Nothing->save score assigned
         Just p | score<p->save score assigned
                | score==p->modify(\w->w{bestPlans=take 64(sortOn (not.preservesOrder old)(bestPlans w++[assigned]))})
                | otherwise->pure()
      walk assigned ((_,ps):rest)=forM_ ps$ \p->do
       charge "node"
       good<-and <$> forM assigned(\q->do charge "check";charge "check";pure(not(required p q) || not(bothClash p q)))
       let cost=movementCost old(p:assigned)
       incumbent<-gets bestScore
       when(good && maybe True(\(best,_)->cost<=best)incumbent)(walk(p:assigned)rest)
      save score es=modify(\w->w{bestScore=Just score,bestPlans=[es]})
  catchError (walk [] ordered) (\e->case e of Limited _->modify(\w->w{searchIncomplete=True});_->throwError e)

preservesOrder old es=and[start a<=start b|a<-es,b<-es,x<-old,y<-old,handle x==handle a,handle y==handle b,start x<start y]

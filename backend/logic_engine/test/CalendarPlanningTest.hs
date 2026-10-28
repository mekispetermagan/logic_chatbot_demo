module Main where

import Control.Monad (forM_, unless)
import Control.Monad.Except (runExceptT)
import Control.Monad.State.Strict (runState)
import Data.List (nub, sortOn)
import qualified Data.Map.Strict as M
import Domains.Calendar.Types
import Domains.Calendar.Language.State
import Domains.Calendar.Language.Planning (solveJoint)

assert label ok = unless ok (error label)

ctx = Context 0 (7*day) 0 [Zone 0 0]
day = 24*60*minute
make ident date clock len = Event ident Nothing "" "" "" (Just "10") t (t+len*tick) False False False
  where t = date*day+clock*tick

work fixed = Work {context=ctx, original=fixed, current=fixed, initialRanking=[], ranking=[],
  nextHandle=100, mappings=M.empty, sentences=[], completed=0, answers=M.empty,
  feedback=[], mentions=[], candidatesUsed=0, checksUsed=0, nodesUsed=0,
  parameterLog=M.empty, grouping=[], bestPlans=[], bestScore=Nothing,
  bestFor="", searchIncomplete=False, historyStates=[]}

run different cap fixed domains = runState (runExceptT (solveJoint ctx different cap fixed domains)) (work fixed)

-- Deliberately exhaustive, without pruning or the production compatibility helper.
-- Candidate domains are on-grid; raw interval arithmetic independently checks pairs.
oracle different fixed domains = [fixed++events | events <- sequence domains,
  and [clear a b | (i,a)<-zip [0::Int ..] events, b<-drop (i+1) events],
  and [clear a b | a<-events, b<-fixed],
  not different || length (nub [start e `div` day | e<-events]) == length events]
  where clear a b = not (start a < end b && start b < end a)

check label different fixed domains = forM_ [1,64] $ \cap -> do
  let (status,result) = run different cap fixed domains
      expected = take cap (oracle different fixed domains)
  assert (label++": unexpected resource limit") (status==Right ())
  assert (label++": feasible solutions/order differ from exhaustive oracle") (bestPlans result==expected)

main = do
  -- Exhaust all nonempty candidate subsets for three event-specific domains.
  -- 7^3 cases, each checked under both date policies and both display caps.
  let pools = [[make i 0 108 1,make i 0 109 1,make i 1 108 1] | i<-[0..2]]
      subsets xs = filter (not.null) (foldr (\x rest -> rest++map(x:)rest) [[]] xs)
  forM_ (sequence (map subsets pools)) $ \domains ->
    forM_ [False,True] $ \different -> check "exhaustive subsets" different [] domains

  -- A separate deterministic family with varying lengths, dates and obstacles.
  -- No seed or case is filtered on its observed result.
  forM_ [0..149::Int] $ \seed -> do
    let size=2+seed `mod` 3
        domain i=sortOn start (nub [make i (toInteger ((seed+3*i+j*j) `mod` 4))
                                     (108+toInteger ((seed*7+i*3+j) `mod` 5))
                                     (1+toInteger ((seed+i) `mod` 3))
                                  |j<-[0..2::Int]])
        domains=[domain i|i<-[0..size-1]]
        fixed=[make 99 2 110 1|seed `mod` 4==0]
        -- Candidate generation removes fixed obstacles before search, as in the app.
        available=[[e|e<-ds,all (\o->not(start e<end o && start o<end e)) fixed]|ds<-domains]
    check ("generated "++show seed) (odd seed) fixed available

  check "empty domain" False [] [[make 0 0 108 1],[]]
  check "adjacent same-day events" False [] [[make 0 0 108 1],[make 1 0 109 1]]
  check "overnight events use start dates" True []
    [[make 0 0 276 24],[make 1 1 12 12]]
  check "old unrelated clashes stay fixed" True [make 90 4 108 12,make 91 4 114 12]
    [[make 0 0 108 1],[make 1 1 108 1]]

  let hall = [[make i d 108 1|d<-[0,1]]|i<-[0..2]] ++ [[make 3 d 108 1|d<-[2,3]]]
      (hallStatus,hallResult)=run True 1 [] hall
  assert "Hall deficiency proves infeasible without expansion" (hallStatus==Right () && null(bestPlans hallResult) && nodesUsed hallResult==0)
  check "matching needs an augmenting path" True []
    [[make 0 d 108 1|d<-[0,1]],[make 1 0 108 1],
     [make 2 d 108 1|d<-[1,2]],[make 3 3 108 1]]

  -- Forward checks and matching must respect the existing check budget.
  let exhausted=(work []){checksUsed=1000000}
      (limited,limitedState)=runState (runExceptT (solveJoint ctx True 1 [] [[make 0 0 108 1],[make 1 1 108 1]])) exhausted
  assert "propagation is budgeted, not an infeasibility claim" (case limited of Left (Limited _)->null(bestPlans limitedState);_->False)
  putStrLn "Calendar joint planning: 686 exhaustive instances, 150 generated variants, edge cases and resource checks passed."

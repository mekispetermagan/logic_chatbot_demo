{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveGeneric, DeriveAnyClass #-}
module Domains.Calendar.Language.State where
import Control.Monad (when,unless,forM,forM_,filterM,foldM)
import Control.Monad.Except
import Control.Monad.State.Strict
import Data.Aeson
import Data.Aeson.Types(parseEither)
import qualified Data.Map.Strict as M
import GHC.Generics(Generic)
import Domains.Calendar.Types
import Domains.Calendar.Language.Syntax

data Question = Question {key :: String,prompt :: String,kind :: String,options :: [(String,Value)]}
 deriving(Eq,Show,Generic,ToJSON,FromJSON)
data Stop = Need Question | Invalid String | Limited String deriving(Eq,Show)
data Work = Work {context :: Context,original :: [Event],current :: [Event],initialRanking :: [Mention],ranking :: [Mention],
 nextHandle :: Int, mappings :: M.Map String Int, sentences :: Entry, completed :: Int, answers :: M.Map String Value,
 feedback :: [String], mentions :: [(Int,[(String,String)])], candidatesUsed :: Int,checksUsed :: Int,nodesUsed :: Int,
 parameterLog :: M.Map String Value, grouping :: [Entry], bestPlans :: [[Event]],
 bestScore :: Maybe (Integer,Instant), bestFor :: String, searchIncomplete :: Bool, historyStates :: [([Event],[Mention],Int)]}
 deriving(Eq,Show,Generic,ToJSON,FromJSON)
type Eval = ExceptT Stop (State Work)
invalid :: String -> Eval a
invalid=throwError.Invalid
need :: String -> String -> String -> [(String,Value)] -> Eval a
need k p t os=throwError(Need(Question k p t os))
valueAt :: (FromJSON a,ToJSON a) => String -> Slot a -> String -> String -> [(String,Value)] -> Eval a
valueAt k initial message typ os=do
 vals<-gets answers
 let parsed = case M.lookup k vals of
       Just v -> case fromJSON v of Success x -> Right x; Error _ -> Left ()
       Nothing -> case initial of Known x -> Right x; Missing -> Left ()
 case parsed of
  Right x | not(null os) && toJSON x `notElem` map snd os->need k ("Choose one of the listed values. "++message) typ os
  Right x->modify(\w->w{parameterLog=M.insert k (toJSON x)(parameterLog w)})>>pure x
  Left _->need k message typ os
charge :: String -> Eval ()
charge counter=do
 w<-get
 let (n,limit)=case counter of "candidate"->(candidatesUsed w,200000);"node"->(nodesUsed w,100000);_->(checksUsed w,1000000)
 when(n>=limit)(throwError(Limited("Calendar "++counter++" budget exhausted; no infeasibility or optimality proof.")))
 put(case counter of "candidate"->w{candidatesUsed=n+1};"node"->w{nodesUsed=n+1};_->w{checksUsed=n+1})
remember :: Event -> [(String,String)] -> Eval ()
remember e fs=modify(\w->w{mentions=mentions w++[(handle e,fs)]})

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
module Domains.Calendar.Language (processRequest) where
import Control.Monad (unless)
import Control.Applicative ((<|>))
import Control.Monad.Except
import Control.Monad.State.Strict
import Data.Aeson
import Data.Aeson.Types(parseEither,Parser)
import Data.List(sortOn,nub,isPrefixOf,isSuffixOf)
import Data.Time (addDays)
import Text.Read (readMaybe)
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Domains.Calendar.Types
import Domains.Calendar.Language.Syntax
import Domains.Calendar.Language.State
import Domains.Calendar.Language.Parser
import Domains.Calendar.Language.Pretty
import Domains.Calendar.Language.Evaluation

processRequest :: Value -> Either String Value
processRequest input=parseEither request input >>= run
 where
 request=withObject "calendar request" $ \v->do
  ver<-v .:? "languageVersion" .!= version
  unless(ver==version)(fail "Unsupported Calendar language version")
  c<-v .: "context";es<-v .:? "events" .!= [];rs<-v .:? "salience" .!= []
  maps<-v .:? "handles" .!= M.empty;n<-v .:? "nextHandle" .!= 0
  a<-v .: "action";saved<-v .:? "work"
  pure(c,es,rs,maps,n,a,saved)
 run(c,es,rs,maps,n,action,saved)=do
  (typ,source,k,value)<-parseEither(withObject "calendar action" $ \a->(,,,) <$> (a .: "type" :: Parser String) <*> a .:? "text" .!= "" <*> a .:? "key" .!= "" <*> a .:? "value" .!= Null)action
  unless(weekEnd c>weekStart c && not(null(zones c)))(Left "Invalid Calendar context")
  unless(all(\e->allDay e || cancelled e || end e>start e)es)(Left "Malformed Calendar event interval")
  unless(length (map googleId es)==length(nub(map googleId es)))(Left "Duplicate Google event identities")
  case typ of
   "checkSyntax"->do
    entries<-parseEntries source
    Right(object["languageVersion" .= version,"policyVersion" .= policy,"status" .= ("syntax"::String),"alternatives" .= map entryText entries])
   "snapshot"->do
    let (imported,updatedMaps,next)=ingest c es maps n
        visible=maybe imported current saved
        discourse=maybe (purge c imported rs) ranking saved
        eventValue e=object["handle" .= handle e,"title" .= title e,"location" .= location e,"description" .= description e,
          "importance" .= importanceName(importance e),"start" .= timeText c(start e),"end" .= timeText c(end e),
          "normalizedStart" .= timeText c(start(normalized e)),"normalizedEnd" .= timeText c(end(normalized e)),"readOnly" .= recurring e]
    Right(object["languageVersion" .= version,"policyVersion" .= policy,"status" .= ("snapshot"::String),"handles" .= updatedMaps,"nextHandle" .= next,
      "world" .= object["domain" .= ("calendar"::String),"weekStart" .= timeText c(weekStart c),"weekEnd" .= timeText c(weekEnd c),
       "frozenNow" .= timeText c(frozenNow c),"timezone" .= ("Europe/Budapest"::String),"provisional" .= (saved/=Nothing),"events" .= map eventValue visible,"salience" .= discourse,
       "evaluation" .= fmap (\w->object["entry" .= entryText(sentences w),"completedSentences" .= completed w,"parameters" .= parameterLog w]) saved]])
   "start"->do
    alternatives<-parseEntries source
    let (imported,updatedMaps,next)=ingest c es maps n
        aged=[m{entryAge=entryAge m+1}|m<-purge c imported rs,entryAge m<3,any((==mentioned m).handle)imported]
        w=Work c imported imported rs aged next updatedMaps (head alternatives) 0 M.empty [] [] 0 0 0 M.empty (if length alternatives>1 then alternatives else []) [] Nothing "" False [(imported,aged,next)]
    if length alternatives>1 then Right(reply "clarify" "Choose Boolean scope before evaluation." (Just(Question "grouping" "Which Boolean grouping?" "choice" [(entryText e,toJSON i)|(i,e)<-zip[0::Int ..]alternatives]))w)
    else Right(evaluate w)
   "answer"->case saved of
    Nothing->Left "No pending Calendar evaluation"
    Just w | k=="grouping" && not(null(grouping w))->case fromJSON value of
     Success i | i>=0&&i<length(grouping w)->Right(evaluate w{sentences=grouping w!!i,grouping=[]})
     _->Left "Choose a listed grouping"
    Just w->Right(evaluate w{answers=M.insert k value(answers w)})
   "revise"->case saved of
    Nothing->Left "No Calendar task to revise"
    Just w->case reads(takeWhile(/='.')k) of
     [(i,"")] | i>=0&&i<length(historyStates w) && i<length(sentences w)->
      let (es',rs',next)=historyStates w!!i;cache=M.filterWithKey(\key _->keepAnswer i k key)(answers w)
      in Right(evaluate w{current=es',ranking=rs',nextHandle=next,completed=i,feedback=take i(feedback w),
           historyStates=take(i+1)(historyStates w),answers=M.insert k value cache,candidatesUsed=0,checksUsed=0,nodesUsed=0,bestFor="",bestPlans=[],bestScore=Nothing,searchIncomplete=False})
     _->Left "Invalid revision parameter"
   "verify"->case saved of
    Nothing->Left "No accepted Calendar evaluation"
    Just w->
     let ids=case fromJSON value of Success v->v;Error _->M.empty
         merged=[e{googleId=M.lookup(show(handle e))ids <|> googleId e}|e<-current w]
         actual=filter(inScope c)es
         same expected=case filter((==googleId expected).googleId)actual of
          [observed]->observed{handle=handle expected}==expected
          _->False
     in if length actual==length merged && all same merged
       then Right(reply "answered" "Confirmed effects; discourse finalized." Nothing w{current=merged,ranking=purge c merged(ranking w)})
       else Left "Fresh Google events differ from the accepted Calendar result"
   _->Left "Unsupported Calendar engine action"
-- Preserve independent identities in the revised sentence. Later sentences are
-- resolved again against their rebuilt world; plans and rounding consent expire.
keepAnswer index changed saved
 | "resolved:" `isPrefixOf` saved = sentence raw<=index && not related
 | any (`isSuffixOf` saved) [".plan",".order",".rounding",".occurrence"] = sentence saved<index
 | ".choice" `isSuffixOf` saved = sentence saved<=index && not related
 | otherwise = not((changed++".") `isPrefixOf` saved)
 where raw=if "resolved:" `isPrefixOf` saved then drop 9 saved else saved
       related=changed==raw || (changed++".") `isPrefixOf` raw || (raw++".") `isPrefixOf` changed
       sentence x=case reads(takeWhile(/='.')x) of [(n,"")]->n;_->index+1

ingest c es mapping initial=foldl assign([],mapping,max initial(1+maximum(-1:M.elems mapping)))(sortOn googleId(filter(inScope c)es))
 where assign(acc,ms,n)e=case googleId e of
        Nothing->(acc,ms,n)
        Just g->case M.lookup g ms of Just h->(acc++[e{handle=h}],ms,n);Nothing->(acc++[e{handle=n}],M.insert g n ms,n+1)
purge c es rs=[m{facts=filter(\(k,v)->case filter((==mentioned m).handle)es of e:_->fieldValue' e k v==v;_->False)(facts m)}|m<-rs,any((==mentioned m).handle)es]
 where fieldValue' e k v=case k of "title"->title e;"location"->location e;"description"->description e;"importance"->show(importance e);"start date"->if trueDate e v then v else "!stale";_->""
       trueDate e v=case readMaybe v of
        Just d->localDate c(start e)==case d of DateLiteral x->read x;Weekday n->addDays(fromIntegral n)(localDate c(weekStart c));Today->localDate c(frozenNow c);Tomorrow->addDays 1(localDate c(frozenNow c))
        Nothing->False
evaluate :: Work -> Value
evaluate w
 | completed w>=length(sentences w)=reply (if any(not.isQuestion)(sentences w) then "review" else "answered") "Evaluation completed." Nothing w
 | otherwise=
  let index=completed w;key=show index
      (out,attempted)=runState(runExceptT(runSentence key(sentences w!!index)))w{mentions=[]}
      reset=attempted{current=current w,ranking=ranking w,mentions=[]}
      failed=reset{ranking=[m{utteranceAge=utteranceAge m+if entryAge m==0 then 1 else 0}|m<-ranking reset]}
  in case out of
   Left(Need q)->reply "clarify" (prompt q)(Just q)reset
   Left(Invalid message)->reply (if index>0 && any(not.isQuestion)(sentences w) then "prefix" else "error") message Nothing failed
   Left(Limited message)->reply (if index>0 && any(not.isQuestion)(sentences w) then "prefix" else "limited") message Nothing failed
   Right message->
    let old=ranking w;aged=[m{utteranceAge=utteranceAge m+if entryAge m==0 then 1 else 0}|m<-old]
        groups=M.toList(M.fromListWith(++)(mentions attempted))
        ranked=purge(context attempted)(current attempted)([Mention 0 0 h(nub fs)|(h,fs)<-groups]++aged)
        next=attempted{ranking=ranked,completed=index+1,feedback=feedback w++[sentenceText(sentences w!!index)++"\n"++message],mentions=[],
         historyStates=historyStates w++[(current attempted,ranked,nextHandle attempted)]}
    in evaluate next
reply :: String -> String -> Maybe Question -> Work -> Value
reply status message question w=object
 ["domain" .= ("calendar"::String),"languageVersion" .= version,"policyVersion" .= policy,
 "status" .= status,"commitDiscourse" .= (all isQuestion(sentences w) && status `elem` ["error","limited"]),"message" .= message,"feedback" .= feedback w,"question" .= question,"work" .= w,
 "salience" .= ranking w,"handles" .= mappings w,"nextHandle" .= nextHandle w,"parameters" .= parameterLog w,
 "plan" .= plan (original w)(current w),"usage" .= object["candidates" .= candidatesUsed w,"checks" .= checksUsed w,"nodes" .= nodesUsed w]]
plan :: [Event] -> [Event] -> [Value]
plan old new=updates++creates++deletes
 where
 updates=[object["type" .= ("update"::String),"handle" .= handle e,"eventId" .= googleId e,"fields" .= M.fromList(changes prior e)]|e<-sortOn handle new,Just prior<-[find e old],not(null(changes prior e))]
 creates=[object["type" .= ("create"::String),"handle" .= handle e,"fields" .= allFields e]|e<-sortOn handle new,googleId e==Nothing]
 deletes=[object["type" .= ("delete"::String),"handle" .= handle e,"eventId" .= googleId e,"fields" .= object[]]|e<-sortOn handle old,find e new==Nothing]
 find e xs=case filter((==handle e).handle)xs of x:_->Just x;_->Nothing
 allFields :: Event -> M.Map String Value
 allFields e=M.fromList[("summary",toJSON(title e)),("location",toJSON(location e)),("description",toJSON(description e)),("colorId",toJSON(colorId e)),("start",toJSON(start e)),("end",toJSON(end e))]
 changes a b=[(k,v)|(k,v)<-M.toList(allFields b),M.lookup k(allFields a)/=Just v || (k `elem` ["start","end"] && interval a/=interval b)]

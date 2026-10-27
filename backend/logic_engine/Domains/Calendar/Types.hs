{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveGeneric, DeriveAnyClass #-}
module Domains.Calendar.Types where

import Data.Aeson (FromJSON,ToJSON)
import Data.List (find, nub, sortOn)
import Data.Time hiding (midnight, utc)
import Data.Time.Clock.POSIX
import GHC.Generics (Generic)

type Instant = Integer -- microseconds since Unix epoch
minute :: Integer
minute = 60000000
tick :: Integer
tick = 5*minute
version, policy :: String
version = "calendar-v1"
policy = "calendar-demo-1"
data Zone = Zone {zoneFrom :: Instant, zoneOffset :: Int} deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Context = Context {weekStart :: Instant, weekEnd :: Instant, frozenNow :: Instant, zones :: [Zone]}
  deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Event = Event {handle :: Int, googleId :: Maybe String, title :: String, location :: String,
  description :: String, colorId :: Maybe String, start :: Instant, end :: Instant, recurring :: Bool, allDay :: Bool, cancelled :: Bool}
  deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Mention = Mention {entryAge :: Int, utteranceAge :: Int, mentioned :: Int, facts :: [(String,String)]}
  deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
importance :: Event -> Int
importance e = case colorId e of Just "11" -> 2; Just "5" -> 1; _ -> 0
importanceName :: Int -> String
importanceName i = ["normal","important","critical"] !! i
importanceColor :: Int -> String
importanceColor i = ["10","5","11"] !! i
roundTime :: Instant -> Instant
roundTime x = let (q,r)=x `divMod` tick in (q + if r>tick `div` 2 then 1 else 0)*tick
normalized :: Event -> Event
normalized e = e {start=a,end=max (a+tick) (roundTime (end e))} where a=roundTime (start e)
overlaps :: (Instant,Instant) -> (Instant,Instant) -> Bool
overlaps (a,b) (c,d) = a<d && c<b
interval :: Event -> (Instant,Instant)
interval e = (start e,end e)
inScope :: Context -> Event -> Bool
inScope c e = not(allDay e) && not(cancelled e) && start e>=weekStart c && end e<=weekEnd c && end e>start e
utc :: Instant -> UTCTime
utc x = posixSecondsToUTCTime (fromRational (toRational x/1000000))
instant :: UTCTime -> Instant
instant = round . (*1000000) . utcTimeToPOSIXSeconds
offsetAt :: Context -> Instant -> Int
offsetAt c t = maybe 0 zoneOffset (find ((<=t).zoneFrom) (reverse (sortOn zoneFrom (zones c))))
local :: Context -> Instant -> LocalTime
local c t = utcToLocalTime (minutesToTimeZone (offsetAt c t `div` 60)) (utc t)
localDate :: Context -> Instant -> Day
localDate c = localDay . local c
localCandidates :: Context -> Day -> Int -> [Instant]
localCandidates c day mins = nub [t | z<-nub (map zoneOffset (zones c)),
  let t=instant (localTimeToUTC (minutesToTimeZone (z `div` 60)) (LocalTime day (TimeOfDay (mins `div` 60) (mins `mod` 60) 0))), offsetAt c t==z]
midnight :: Context -> Day -> Instant
midnight c d = case localCandidates c d 0 of t:_ -> t; [] -> error "Budapest midnight missing from supplied timezone context"
timeText :: Context -> Instant -> String
timeText c t = formatTime defaultTimeLocale (if t `mod` minute==0 then "%Y-%m-%d %H:%M" else "%Y-%m-%d %H:%M:%S%Q") (local c t) ++ " Europe/Budapest (UTC" ++ sign ++ hh ++ ":" ++ mm ++ ")"
  where n=offsetAt c t `div` 60; sign=if n<0 then "-" else "+"; pad x=if x<10 then '0':show x else show x; hh=pad (abs n `div` 60); mm=pad (abs n `mod` 60)
periodBounds :: Context -> Instant -> (Instant,Instant)
periodBounds c t = (boundary lo, boundary hi)
  where
    d=localDate c t; tod=localTimeOfDay (local c t); m=todHour tod*60+todMin tod
    (lo,hi) | m<360=(-120,360) | m<540=(360,540) | m<720=(540,720)
            | m<780=(720,780) | m<1080=(780,1080) | m<1320=(1080,1320) | otherwise=(1320,1800)
    boundary x = case localCandidates c (addDays (fromIntegral (x `div` 1440)) d) (x `mod` 1440) of a:_ -> a; [] -> midnight c d
movementBounds :: Context -> Event -> (Instant,Instant)
movementBounds c e = (max (weekStart c) (max a dayA),min (weekEnd c) (min b dayB))
  where (a,_)=periodBounds c (start e); (_,b)=periodBounds c (end e-1)
        dayA=midnight c (localDate c (start e)); dayB=midnight c (addDays 1 (localDate c (end e)))
movablePlacement :: Context -> Event -> Event -> Bool
movablePlacement c old new = inScope c new && start new>=a && end new<=b
  && localDate c (start old)==localDate c (start new) && localDate c (end old)==localDate c (end new)
  where (a,b)=movementBounds c old

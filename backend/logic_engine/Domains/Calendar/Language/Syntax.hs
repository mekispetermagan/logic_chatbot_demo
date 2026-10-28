{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveGeneric, DeriveAnyClass #-}
module Domains.Calendar.Language.Syntax where
import Data.Aeson (FromJSON,ToJSON)
import GHC.Generics (Generic)

data Slot a = Known a | Missing deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data DateTerm = DateLiteral String | Weekday Int | Today | Tomorrow deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Clock = Clock Int | ClockChoices [Int] deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Moment = Moment (Slot DateTerm) (Slot Clock) (Maybe Int) deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Window = SelectedWeek | OnDate (Slot DateTerm) (Maybe String) (Maybe (Bool,Slot Clock)) (Maybe (Bool,Slot Clock))
  | Between (Slot Moment) (Slot Moment) | Starting (Slot Moment) deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Ref = Handle Int | It | Described Bool [(String,String)] deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Compare = Equal | AtLeast | AtMost deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Condition = TrueCondition | UnknownCondition | TextIs String (Slot String) | ImportanceIs Compare (Slot Int)
  | StartsOn (Slot DateTerm) | Within (Slot Window) | OverlapsWindow (Slot Window) | Relation String (Slot Ref)
  | DurationIs Compare (Slot Integer) | HasClash (Slot Window) | Not Condition | And Condition Condition | Or Condition Condition
  deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Options = Options {threshold :: Slot Int, protected :: Slot [Ref], preserveOrder :: Bool}
  deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Task = Task {duration :: Slot Integer, window :: Slot Window, fields :: [(String,Slot String)]}
  deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data JointWindow = SingleWindow (Slot Window) | AnyWindows [Slot Window]
  deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data JointItem = JointItem (Slot Integer) (Slot JointWindow) [(String,Slot String)]
  deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
data Sentence = Create (Slot Moment) (Slot Moment) | CreateWithFields (Slot Moment) (Slot Moment) [(String,Slot String)] | Delete (Slot Ref) | SetText String (Slot Ref) (Slot String)
  | SetImportance (Slot Ref) (Slot Int) | SetInterval (Slot Ref) (Slot Moment) (Slot Moment)
  | Schedule Task | Insert Task Options | Repair (Slot DateTerm) Options
  | JointSchedule (Slot [JointItem]) Bool Bool | JointPossible (Slot [JointItem]) Bool Bool
  | FreeWindow (Slot Window) Options | FreePossible (Slot Window) Options | FreeCost (Slot Window) Options
  | Exists (Slot Int) | Query (Slot String) (Slot Ref) | Check (Slot Ref) Condition
  | DurationOf (Slot Ref) | Gap (Slot Ref) (Slot Ref) | Select Bool Condition | Quantify Bool Condition Condition
  | Free (Slot Window) | Earliest Task | Conflicts Bool (Slot Window) (Slot String)
  | Feasible Task Options | MinimumCost Task Options | RepairPossible (Slot DateTerm) Options
  deriving (Eq,Show,Read,Generic,ToJSON,FromJSON)
type Entry = [Sentence]
isQuestion :: Sentence -> Bool
isQuestion s = case s of Create {}->False;CreateWithFields {}->False;Delete _->False;SetText {}->False;SetImportance {}->False;SetInterval {}->False;Schedule _->False;Insert {}->False;Repair {}->False;JointSchedule {}->False;FreeWindow {}->False;_->True

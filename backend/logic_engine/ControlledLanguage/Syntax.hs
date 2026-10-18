module ControlledLanguage.Syntax where

import Ontology (Position)

data Ref = Ident Int | It | At Square | Anaphoric [(String,String)] | Unique Condition | Described Condition deriving (Eq,Show,Read)
data Square = Cell Position | SquareIt | Neighbor Direction Ref deriving (Eq,Show,Read)
data Direction = North | East | South | West deriving (Eq,Show,Read)
data Condition = Truth | ValueIs String String | Present String Bool | PositionIs Position
               | IdentifierIs Int | Occupied | Shading Bool | Coordinate String Int
               | EqualAttribute String Ref Bool | SameObject Ref | Adjacent Ref
               | Directed Direction Ref | Edge | Corner | OnSquare Condition
               | PatternIs String | NetworkRole String (Maybe GraphExpr)
               | NetworkRelation String Ref (Maybe GraphExpr) | GraphProperty String (Maybe String)
               | Not Condition | And Condition Condition | Or Condition Condition deriving (Eq,Show,Read)
data GraphExpr = NetworkGraph | Component Ref (Maybe GraphExpr) | Induced GraphExpr Condition deriving (Eq,Show,Read)
data Endpoint = SquareEndpoint Square | ObjectEndpoint Ref | EndpointIt deriving (Eq,Show,Read)
data Collection = Objects [Ref] | AtSquares [Square] | Matching Condition | InGraph GraphExpr deriving (Eq,Show,Read)
data Targets = One Ref | Many Collection deriving (Eq,Show,Read)
data Turn = Clockwise | HalfTurn | Counterclockwise deriving (Eq,Show,Read)
data Transform = Rotate Turn | Reflect Bool deriving (Eq,Show,Read)
data CopyMode = Copy | Transfer | Exchange deriving (Eq,Show,Read)
data Command = Create [(String,String)] (Maybe Square) | Delete Targets | DeleteAll
             | SetAttribute Targets String (Maybe String) | SetAppearance Targets [(String,Maybe String)]
             | Move Ref Square | Unplace Targets | ExchangePositions Ref Ref
             | Step Ref Direction | MoveNextTo Ref Ref | CopyComponent CopyMode String Ref Ref
             | Clone Ref (Maybe Square) | Shift Collection Position
             | Rearrange [(Ref,Square)] | Permute [(Ref,Ref)]
             | Transformation Bool Collection Transform (Position,Position)
             | PortState Targets Direction Bool | SetPattern Targets String
             | TransformPorts Targets Transform | TransformDrawing Collection Transform (Position,Position)
             | Link Ref Ref Bool | Extend Ref Direction | Trim Targets
             | BuildConnection Endpoint Endpoint (Maybe String) deriving (Eq,Show,Read)
data Question = Exists Int | CheckObject Ref Condition | CheckSquare Square Condition | CheckIt Condition
              | Query String Ref | Occupant Square | Select Bool Condition | Count Bool Condition
              | Quantified Bool Bool Condition Condition
              | CheckGraph GraphExpr Condition | CheckLink Ref Ref (Maybe GraphExpr) Condition
              | GraphNumber String GraphExpr | NetworkQuery String Ref (Maybe Ref) (Maybe GraphExpr) deriving (Eq,Show,Read)
data Sentence = Command Command | Question Question deriving (Eq,Show,Read)
data Entry = Undo | Sequence [Sentence] | Batch [Command] deriving (Eq,Show,Read)
data Choice = ObjectChoice Int | SquareChoice Position deriving (Eq,Show,Read)

appearanceAttributes :: [String]
appearanceAttributes = ["color","size","shape"]

offset :: Direction -> Position
offset North = (0,1)
offset East = (1,0)
offset South = (0,-1)
offset West = (-1,0)

-- Shared predicates can constrain a pronoun to objects, squares, or either.
data ReferentKind = ObjectKind | SquareKind deriving (Eq,Ord,Show,Read)
conditionKinds :: Condition -> [ReferentKind]
conditionKinds condition = case condition of
  Truth -> both
  Edge -> both
  Corner -> both
  Coordinate _ _ -> both
  Occupied -> [SquareKind]
  Shading _ -> [SquareKind]
  GraphProperty _ _ -> []
  Not c -> conditionKinds c
  And a b -> intersection a b
  Or a b -> intersection a b
  _ -> [ObjectKind]
  where
    both = [ObjectKind,SquareKind]
    intersection a b = filter (`elem` conditionKinds b) (conditionKinds a)

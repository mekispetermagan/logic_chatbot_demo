{-# LANGUAGE OverloadedStrings #-}
module Main where

import Control.Monad (unless)
import Data.Aeson (Value, eitherDecode, encode, object, (.=))
import Data.Either (isLeft)
import EditorJson (processRequest)
import Ontology
import WorldEditor

check :: String -> Bool -> IO ()
check name result = unless result (fail name)

main :: IO ()
main = do
  let empty = World []
      unplaced = Object (Id 5) Nothing Nothing Nothing Nothing
      original = World [unplaced]
      (created@(World objects), _) = evaluateEditorAction original (ApplyProperty (0, 0) (C Red))
      (changed, _) = evaluateEditorAction created (ApplyProperty (0, 0) (S Small))
      (placed, _) = evaluateEditorAction changed (PlaceObject (Id 5) (1, 1))
  check "empty square creates next identifier with only selected property"
    (objects == [Object (Id 6) (Just Red) Nothing Nothing (Just (0, 0)), unplaced])
  check "property additions preserve identity and other attributes"
    (changed == World [Object (Id 6) (Just Red) (Just Small) Nothing (Just (0, 0)), unplaced])
  check "same property does not change world"
    (evaluateEditorAction changed (ApplyProperty (0, 0) (S Small)) == (changed, "No change"))
  check "occupied destination does not place or create"
    (fst (evaluateEditorAction changed (PlaceObject (Id 5) (0, 0))) == changed)
  check "place preserves identity and partial attributes"
    (placed == World [Object (Id 6) (Just Red) (Just Small) Nothing (Just (0, 0)),
                      unplaced {positionOf = Just (1, 1)}])
  check "already placed objects cannot be moved through placement"
    (fst (evaluateEditorAction placed (PlaceObject (Id 5) (2, 2))) == placed)
  check "unknown placement identifier does not create"
    (fst (evaluateEditorAction placed (PlaceObject (Id 999) (2, 2))) == placed)
  check "erase removes only object on selected square"
    (fst (evaluateEditorAction placed (EraseSquare (0, 0))) ==
      World [unplaced {positionOf = Just (1, 1)}])
  check "erase empty square unchanged" (evaluateEditorAction empty (EraseSquare (0, 0)) == (empty, "No change"))
  check "clear includes unplaced objects" (fst (evaluateEditorAction original ClearWorld) == empty)
  check "clear empty world unchanged" (evaluateEditorAction empty ClearWorld == (empty, "No change"))
  mapM_ (\action -> check "out of bounds unchanged" (fst (evaluateEditorAction original action) == original))
    [ApplyProperty (-1, 0) (C Blue), ApplyProperty (0, 8) (S Large),
     PlaceObject (Id 5) (8, 0), EraseSquare (0, -1)]
  let emptyJson = object ["width" .= (8 :: Int), "height" .= (8 :: Int), "objects" .= ([] :: [Value])]
      action = object ["type" .= ("property" :: String), "property" .= ("red" :: String),
                       "position" .= object ["x" .= (0 :: Int), "y" .= (0 :: Int)]]
      request = object ["world" .= emptyJson, "action" .= action]
      expected = object ["world" .= object ["width" .= (8 :: Int), "height" .= (8 :: Int),
                    "objects" .= [object ["id" .= (0 :: Int), "color" .= ("red" :: String),
                                          "size" .= (Nothing :: Maybe String),
                                          "shape" .= (Nothing :: Maybe String),
                                          "position" .= object ["x" .= (0 :: Int), "y" .= (0 :: Int)]]]],
                         "feedback" .= ("Created #0: red" :: String), "salience" .= ([] :: [Value]),
                         "pending" .= (Nothing :: Maybe Value), "isError" .= False]
  check "JSON round trip with explicit null attributes"
    ((eitherDecode (encode request) >>= processRequest) == Right expected)
  check "JSON rejects unsupported board dimensions"
    (isLeft (processRequest (object ["world" .= object ["width" .= (9 :: Int),
      "height" .= (8 :: Int), "objects" .= ([] :: [Value])], "action" .= action])))
  check "JSON rejects unknown property"
    (isLeft (processRequest (object ["world" .= emptyJson, "action" .= object
      ["type" .= ("property" :: String), "property" .= ("purple" :: String),
       "position" .= object ["x" .= (0 :: Int), "y" .= (0 :: Int)]]])))
  let undoRequest = object ["world" .= emptyJson,
                           "action" .= object ["type" .= ("chat" :: String),
                             "text" .= (" \tUnDo #999 red. invalid suffix" :: String)]]
      undoReply = object ["world" .= emptyJson, "salience" .= ([] :: [Value]),
                          "pending" .= (Nothing :: Maybe Value),
                          "feedback" .= ("" :: String), "isError" .= False,
                          "undoRequested" .= True]
  check "undo request precedes grammar parsing without evaluating suffix"
    (processRequest undoRequest == Right undoReply)
  putStrLn "All world editor checks passed."

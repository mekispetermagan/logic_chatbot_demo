module Main where

import Data.Aeson (eitherDecode, encode)
import qualified Data.ByteString.Lazy.Char8 as Bytes
import EditorJson (processRequest)
import System.Exit (exitWith, ExitCode(..))
import System.IO (hPutStrLn, stderr)

-- One JSON request on stdin, one JSON response on stdout; diagnostics on stderr.
main :: IO ()
main = do
  input <- Bytes.getContents
  case eitherDecode input >>= processRequest of
    Left message -> hPutStrLn stderr message >> exitWith (ExitFailure 2)
    Right response -> Bytes.putStrLn (encode response)

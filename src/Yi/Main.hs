{-# LANGUAGE CPP #-}
-- Copyright (c) Tuomo Valkonen 2004.
-- Copyright (c) Don Stewart 2004-5.
-- Copyright (c) Jean-Philippe Bernardy 2006,2007.

-- | This is the main module of Yi, called with configuration from the user.
-- Here we mainly process command line arguments.

module Yi.Main (main) where

import Prelude ()

import Control.Monad.Error
import Data.Char
import Data.List (intercalate)
import Distribution.Text (display)
import System.Console.GetOpt
import System.Environment (getArgs)
import System.Exit
#include "ghcconfig.h"

import Yi.Config
import Yi.Config.Default
import Yi.Core
import Yi.File
import Paths_yi

#ifdef TESTING
import qualified TestSuite
#endif

#ifdef FRONTEND_COCOA
import HOC (withAutoreleasePool)
#endif

frontendNames :: [String]
frontendNames = fmap fst' availableFrontends
  where fst' :: (a,UIBoot) -> a
        fst' (x,_) = x

data Err = Err String ExitCode

instance Error Err where
    strMsg s = Err s (ExitFailure 1)

-- ---------------------------------------------------------------------
-- | Argument parsing. Pretty standard.

data Opts = Help
          | Version
          | LineNo String
          | EditorNm String
          | File String
          | Frontend String
          | ConfigFile String
          | SelfCheck
          | Debug

-- | List of editors for which we provide an emulation.
editors :: [(String,Config -> Config)]
editors = [("emacs", toEmacsStyleConfig),
           ("vim",   toVimStyleConfig),
           ("cua",   toCuaStyleConfig)]

options :: [OptDescr Opts]
options =
  [ Option []     ["self-check"]  (NoArg  SelfCheck)             "Run self-checks"
  , Option ['f']  ["frontend"]    (ReqArg Frontend   "FRONTEND") frontendHelp
  , Option ['y']  ["config-file"] (ReqArg ConfigFile "PATH")     "Specify a configuration file"
  , Option ['V']  ["version"]     (NoArg  Version)               "Show version information"
  , Option ['h']  ["help"]        (NoArg  Help)                  "Show this help"
  , Option []     ["debug"]       (NoArg  Debug)                 "Write debug information in a log file"
  , Option ['l']  ["line"]        (ReqArg LineNo     "NUM")      "Start on line number"
  , Option []     ["as"]          (ReqArg EditorNm   "EDITOR")   editorHelp
  ] where frontendHelp = ("Select frontend, which can be one of:\n"
                             ++ intercalate ", " frontendNames)
          editorHelp   = ("Start with editor keymap, where editor is one of:\n"
                             ++ (intercalate ", " . fmap fst) editors)

-- | usage string.
usage, versinfo :: String
usage = usageInfo ("Usage: yi [option...] [file]") options

versinfo = "yi " ++ display version

-- | Transform the config with options
do_args :: Config -> [String] -> Either Err Config
do_args cfg args =
    case (getOpt (ReturnInOrder File) options args) of
        (o, [], []) -> foldM getConfig cfg o
        (_, _, errs) -> fail (concat errs)

-- | Update the default configuration based on a command-line option.
getConfig :: Config -> Opts -> Either Err Config
getConfig cfg opt =
    case opt of
      Frontend f -> case lookup f availableFrontends of
                      Just frontEnd -> return cfg { startFrontEnd = frontEnd }
                      Nothing       -> fail "Panic: frontend not found"
      Help          -> throwError $ Err usage ExitSuccess
      Version       -> throwError $ Err versinfo ExitSuccess
      Debug         -> return cfg { debugMode = True }
      LineNo l      -> case startActions cfg of
                         x : xs -> return cfg { startActions = x:makeAction (gotoLn (read l)):xs }
                         []     -> fail "The `-l' option must come after a file argument"
      File filename -> prependAction (editFile filename)
      EditorNm emul -> case lookup (fmap toLower emul) editors of
             Just modifyCfg -> return $ modifyCfg cfg
             Nothing -> fail $ "Unknown emulation: " ++ show emul
      _ -> return cfg
  where 
    prependAction a = return $ cfg { startActions = makeAction a : startActions cfg}

-- ---------------------------------------------------------------------
-- | Static main. This is the front end to the statically linked
-- application, and the real front end, in a sense. 'dynamic_main' calls
-- this after setting preferences passed from the boot loader.
--
main :: Config -> Maybe Editor -> IO ()
main cfg state = do
#ifdef FRONTEND_COCOA
       withAutoreleasePool $ do
#endif
         args <- getArgs
#ifdef TESTING
         when ("--self-check" `elem` args)
              TestSuite.main
#endif
         case do_args cfg args of
              Left (Err err code) ->
                do putStrLn err
                   exitWith code
              Right finalCfg ->
                do when (debugMode finalCfg) $ initDebug ".yi.dbg"
                   startEditor finalCfg state


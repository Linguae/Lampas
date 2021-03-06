-- The `Eval` module handles evaluation of already parsed expressions. Generally the evaluation is done by pattern matching, execution of functions, and recursion upon `eval`.
module Eval where

import Text.ParserCombinators.Parsec
import System.Environment
import Control.Monad
import Control.Monad.Error
import System.IO
import Data.IORef

import Types
import Refs
import IO

-- ## Apply Arguments to Functions
-- Functions are either primitive or user-defined. Application simply pattern matches against these and assuming no errors, fires the underlying function with passed arguments.

apply :: LispVal -> [LispVal] -> IOThrowsError LispVal
apply (PrimitiveFunc func) args = liftThrows $ func args
-- ### Apply Arguments to User-Defined Functions
-- Check parameter count and then bind the closure to the environment, pass arguments and evaluate the body.
apply (Func params varargs body closure) args = 
    if num params /= num args && varargs == Nothing
       then throwError $ NumArgs (num params) args
       else (liftIO $ bindVars closure $ zip params args) >>= bindVarArgs varargs >>= evalBody
    where remainingArgs = drop (length params) args
          num = toInteger . length
          evalBody env = liftM last $ mapM (eval env) body 
          bindVarArgs arg env = case arg of
              Just argName -> liftIO $ bindVars env [(argName, List $ remainingArgs)]
              Nothing -> return env 
apply (IOFunc func) args = func args  

-- ## Apply a List of Arguments to Functions
-- A primitive function for application of arguments to a function.
applyProc :: [LispVal] -> IOThrowsError LispVal
applyProc [func, List args] = apply func args
applyProc (func : args) = apply func args            

-- ## Macros
-- Macros rewrite expressions of a given form prior to there evaluation.

-- ### Check for Rewriters of Expressions
-- Macro rewriters are stored in the same way as traditional functions. They are merely given a special flag and fired in a different way.

-- Basic `defmacro` rewriters are checked for here.
hasRewrite :: LispVal -> Env -> IOThrowsError Bool
hasRewrite (Atom name) env = liftIO $ isBound env (name ++ "-syntax")
hasRewrite badAtom env = liftIO $ return False

-- Special `defenvmacro` rewriters are handled separately and are passed the environment of the expression they are substituting.
hasEnvRewrite :: LispVal -> Env -> IOThrowsError Bool
hasEnvRewrite (Atom name) env = liftIO $ isBound env (name ++ "-syntax-env")
hasEnvRewrite badAtom env = liftIO $ return False

-- ### Macro Rewriters
-- When rewriting an expression by macro, the function is accessed just like any other, then applied with the rest of the expression as argument, and the returned expression is then evaluated.
rewrite env (Atom name) args = do
    func <- getVar env (name ++ "-syntax")    
    applied <- apply func args
    eval env applied
    
rewriteEnv env (Atom name) args = do
    func <- getVar env (name ++ "-syntax-env")    
    renderedEnv <- renderEnv env
    renderedVals <- mapM (\(String val) -> getVar env val) renderedEnv
    applied <- apply func ((List (map (\(key, val) -> List [key, val]) (zip renderedEnv renderedVals))):args)
    eval env applied    
    
-- ## Quasiquotations
-- Quasiquotes allow for values to be escaped as literal via `,`. The parsing of this is made recursive by quasiquoting all sub-expressions.
evalCommas (List [Atom "unquote", val]) = val
evalCommas normalAtom = List [Atom "quasiquote", normalAtom]

-- ## Evaluate LispVals
eval :: Env -> LispVal -> IOThrowsError LispVal
-- Pattern match against basic primitive types and return them.
eval env val@(String _) = return val
eval env val@(Number _) = return val
eval env val@(Bool _) = return val
-- An atom not caught as `quote`, `if`, etc. is a variable reference.
eval env (Atom id) = getVar env id
-- `quote` returns the literal form of quoted values, and `quasiquote` does the same, after searching for commas to parse via `evalCommas`.
eval env (List [Atom "quote", val]) = return val
eval env (List [Atom "quasiquote", List args]) = do 
    argVals <- mapM ((eval env) . evalCommas) args
    liftIO $ return $ List argVals
eval env (List [Atom "quasiquote", arg]) = liftIO $ return arg
-- `if` statement evaluation is lazy
eval env (List [Atom "if", pred, conseq, alt]) = 
    do result <- eval env pred
       case result of
         Bool False -> eval env alt
         otherwise -> eval env conseq
-- ## Variable Setters & Macros         
eval env (List [Atom "set!", Atom var, form]) =
    eval env form >>= setVar env var
eval env (List [Atom "define", Atom var, form]) =
    eval env form >>= defineVar env var
eval env (List [Atom "load", String filename]) = 
    load filename >>= liftM last . mapM (eval env)    
eval env (List (Atom "define" : List (Atom var : params) : body)) =
    makeNormalFunc env params body >>= defineVar env var
eval env (List (Atom "define" : DottedList (Atom var : params) varargs : body)) =
    makeVarargs varargs env params body >>= defineVar env var    
-- `defmacro` defines functions of a special naming format.    
eval env (List (Atom "defmacro" : List (Atom var : params) : body)) =
    makeNormalFunc env params body >>= defineVar env (var ++ "-syntax")        
eval env (List (Atom "defmacro" : DottedList (Atom var : params) varargs : body)) =
    makeVarargs varargs env params body >>= defineVar env (var ++ "-syntax")        
-- `defenvmacro` defines functions of another format.
eval env (List (Atom "defenvmacro" : List (Atom var : params) : body)) =
    makeNormalFunc env params body >>= defineVar env (var ++ "-syntax-env")    
eval env (List (Atom "lambda" : List params : body)) =
    makeNormalFunc env params body    
eval env (List (Atom "lambda" : DottedList params varargs : body)) =
    makeVarargs varargs env params body
eval env (List (Atom "lambda" : varargs@(Atom _) : body)) =
    makeVarargs varargs env [] body
-- A default S-Expression is checked for applicable macros, env-macros, and finally executed as a function call.    
eval env val@(List (function : args)) = do
    hadRewrite <- hasRewrite function env
    hadEnvRewrite <- hasEnvRewrite function env
    if hadRewrite 
      then rewrite env function args 
      else if hadEnvRewrite
        then rewriteEnv env function args
        else evalfun env val
eval env badForm = throwError $ BadSpecialForm "Unrecognized special form" badForm

-- `evalfun` is delegated to if a matching expression is not interpreted as a macro.
evalfun env (List (function : args)) = do 
    func <- eval env function
    argVals <- mapM (eval env) args
    apply func argVals

-- ## Function Constructors
-- Functions are made to match the `Func` type by these constructors.
makeFunc varargs env params body = return $ Func (map showVal params) varargs body env
makeNormalFunc = makeFunc Nothing
makeVarargs = makeFunc . Just . showVal
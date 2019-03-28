
\subsection{Cardano.BM.Data.Tracer}
\label{code:Cardano.BM.Data.Tracer}

%if style == newcode
\begin{code}
{-# LANGUAGE InstanceSigs #-}

module Cardano.BM.Data.Tracer
    ( Tracer (..)
    , traceWith
    -- , Contravariant(..)
    -- * tracer transformers
    , natTracer
    , nullTracer
    , stdoutTracer
    , debugTracer
    , showTracing
    -- * conditional tracing
    , condTracing
    , condTracingM
    -- * examples
     , example2
     , example3
     , example4
     , example5
     , example6
    ) where

import           Control.Monad (void)
import           Data.Text (Text, unpack)

import           Cardano.BM.Data.LogItem (LoggerName,
                     LogObject (..), LOContent (..),
                     PrivacyAnnotation (..),
                     PrivacyAndSeverityAnnotated (..), mkLOMeta)
import           Cardano.BM.Data.Severity (Severity (..))
import           Control.Tracer

\end{code}
%endif

This module extends the basic |Tracer| with one that keeps a list of context names to
create the basis for |Trace| which accepts messages from a Tracer and ends in the |Switchboard|
for further processing of the messages.

\begin{scriptsize}
\begin{verbatim}
   +-----------------------+
   |                       |
   |    external code      |
   |                       |
   +----------+------------+
              |
              |
        +-----v-----+
        |           |
        |  Tracer   |
        |           |
        +-----+-----+
              |
              |
  +-----------v------------+
  |                        |
  |        Trace           |
  |                        |
  +-----------+------------+
              |
  +-----------v------------+
  |      Switchboard       |
  +------------------------+

  +----------+ +-----------+
  |Monitoring| |Aggregation|
  +----------+ +-----------+

          +-------+
          |Logging|
          +-------+

+-------------+ +------------+
|Visualisation| |Benchmarking|
+-------------+ +------------+

\end{verbatim}
\end{scriptsize}

\subsubsection{LogNamed}\label{code:LogNamed}\index{LogNamed}
A |LogNamed| contains of a context name and some log item.
\begin{code}
data LogNamed item = LogNamed
    { lnName :: LoggerName
    , lnItem :: item
    } deriving (Show)

\end{code}

\begin{code}
renderNamedItemTracing :: Show a => Tracer m String -> Tracer m (LogNamed a)
renderNamedItemTracing = contramap $ \item ->
    unpack (lnName item) ++ ": " ++ show (lnItem item)

renderNamedItemTracing' :: Show a => Tracer m String -> Tracer m (LogObject a)
renderNamedItemTracing' = contramap $ \item ->
    unpack (loName item) ++ ": " ++ show (loContent item) ++ ", (meta): " ++ show (loMeta item)

\end{code}

\begin{code}
named :: Tracer m (LogNamed a) -> Tracer m a
named = contramap (LogNamed mempty)
\end{code}

Add a new name to the logging context
\begin{code}
appendNamed :: LoggerName -> Tracer m (LogNamed a) -> Tracer m (LogNamed a)
appendNamed name = contramap $ (\(LogNamed oldName item) ->
    LogNamed (name <> "." <> oldName) item)

\end{code}

Add a new name to the logging context
\begin{code}
appendNamed' :: LoggerName -> Tracer m (LogObject a) -> Tracer m (LogObject a)
appendNamed' name = contramap $ (\(LogObject oldName meta item) ->
    if oldName == ""
    then LogObject name meta item
    else LogObject (name <> "." <> oldName) meta item)

\end{code}

The function |toLogObject| can be specialized for various environments
\begin{code}
class Monad m => ToLogObject m where
  toLogObject :: Tracer m (LogObject a) -> Tracer m a

instance ToLogObject IO where
    toLogObject :: Tracer IO (LogObject a) -> Tracer IO a
    toLogObject tr = Tracer $ \a -> do
        lo <- LogObject <$> pure ""
                        <*> (mkLOMeta Debug Public)
                        <*> pure (LogMessage a)
        traceWith tr lo

\end{code}

\begin{spec}
To be placed in ouroboros-network.

instance (MonadFork m, MonadTimer m) => ToLogObject m where
    toLogObject (Tracer (Op tr) = Tracer $ Op $ \a -> do
        lo <- LogObject <$> pure ""
                        <*> (LOMeta <$> getMonotonicTime  -- must be evaluated at the calling site
                                    <*> (pack . show <$> myThreadId)
                                    <*> pure Debug
                                    <*> pure Public)
                        <*> pure (LogMessage a)
        tr lo

\end{spec}

\begin{code}
tracingNamed :: Show a => Tracer IO (LogObject a) -> Tracer IO a
tracingNamed = toLogObject

example2 :: IO ()
example2 = do
    let logTrace = appendNamed' "example2" (renderNamedItemTracing' stdoutTracer)

    void $ callFun2 logTrace

callFun2 :: Tracer IO (LogObject Text) -> IO Int
callFun2 logTrace = do
    let logTrace' = appendNamed' "fun2" logTrace
    traceWith (tracingNamed logTrace') "in function 2"
    callFun3 logTrace'

callFun3 :: Tracer IO (LogObject Text) -> IO Int
callFun3 logTrace = do
    traceWith (tracingNamed (appendNamed' "fun3" logTrace)) "in function 3"
    return 42

\end{code}

A |Tracer| transformer creating a |LogObject| from |PrivacyAndSeverityAnnotated|.
\begin{code}
logObjectFromAnnotated :: Show a
    => Tracer IO (LogObject a)
    -> Tracer IO (PrivacyAndSeverityAnnotated a)
logObjectFromAnnotated tr = Tracer $ \(PSA sev priv a) -> do
    lometa <- mkLOMeta sev priv
    traceWith tr $ LogObject "" lometa (LogMessage a)

\end{code}

\begin{code}
example3 :: IO ()
example3 = do
    let logTrace =
            logObjectFromAnnotated $ appendNamed' "example3" $ renderNamedItemTracing' stdoutTracer

    traceWith logTrace $ PSA Info Confidential ("Hello" :: String)
    traceWith logTrace $ PSA Warning Public "World"

\end{code}

\begin{code}
filterAppendNameTracing :: Monad m
    => m (LogNamed a -> Bool)
    -> LoggerName
    -> Tracer m (LogNamed a)
    -> Tracer m (LogNamed a)
filterAppendNameTracing test name = (appendNamed name) . (condTracingM test)

example4 :: IO ()
example4 = do
    let appendF = filterAppendNameTracing oracle
        logTrace = appendF "example4" (renderNamedItemTracing stdoutTracer)

    traceWith (named logTrace) ("Hello" :: String)

    let logTrace' = appendF "inner" logTrace
    traceWith (named logTrace') "World"

    let logTrace'' = appendF "innest" logTrace'
    traceWith (named logTrace'') "!!"
  where
    oracle :: Monad m => m (LogNamed a -> Bool)
    oracle = return $ ((/=) "example4.inner.") . lnName

\end{code}

\begin{code}

-- severity anotated
example5 :: IO ()
example5 = do
    let logTrace =
            condTracingM oracle $
                logObjectFromAnnotated $
                    appendNamed' "test5" $ renderNamedItemTracing' stdoutTracer

    traceWith logTrace $ PSA Debug Confidential ("Hello"::String)
    traceWith logTrace $ PSA Warning Public "World"

  where
    oracle :: Monad m => m (PrivacyAndSeverityAnnotated a -> Bool)
    oracle = return $ \(PSA sev _priv _) -> (sev > Debug)

-- test for combined name and severity
example6 :: IO ()
example6 = do
    let logTrace0 =  -- the basis, will output using the local renderer to stdout
            appendNamed' "test6" $ renderNamedItemTracing' stdoutTracer
        logTrace1 =  -- the trace from |Privacy...Annotated| to |LogObject|
            condTracingM oracleSev $ logObjectFromAnnotated $ logTrace0
        logTrace2 =
            appendNamed' "row" $ condTracingM oracleName $ logTrace0
        logTrace3 =  -- oracle should eliminate messages from this trace
            appendNamed' "raw" $ condTracingM oracleName $ logTrace0

    traceWith logTrace1 $ PSA Debug Confidential ("Hello" :: String)
    traceWith logTrace1 $ PSA Warning Public "World"
    lometa <- mkLOMeta Info Public
    traceWith logTrace2 $ LogObject "" lometa (LogMessage ", RoW!")
    traceWith logTrace3 $ LogObject "" lometa (LogMessage ", RoW!")

  where
    oracleSev :: Monad m => m (PrivacyAndSeverityAnnotated a -> Bool)
    oracleSev = return $ \(PSA sev _priv _) -> (sev > Debug)
    oracleName :: Monad m => m (LogObject a -> Bool)
    oracleName = return $ \(LogObject name _ _) -> (name == "row")  -- we only see the names from us to the leaves

\end{code}

import Omafiles.Backend as Backend

// Runs an external process and delivers its full result at once
// (start / busy / cancel / finished{exitCode,stdout,stderr,cancelled}).
// Thin adapter that re-exports the C++ type Omafiles.Backend.ProcessRunner
// (backed by a real QProcess, see backend/ProcessRunner.cpp) under the
// name Omafiles.Services.ProcessRunner that logic/ expects.
//
// Phase 5.C (josema): a SINGLE implementation for both frontends. Previously
// there were two -- this one (Quickshell.Io.Process) and services/+standalone/ over
// the C++ backend; now Quickshell also loads the .so by import path,
// so the Quickshell version is retired and only this QML<->C++ seam
// remains. The API (start/busy/cancel/finished) is identical; logic/ keeps
// writing `ProcessRunner { onFinished: ... }` without noticing.
//
// For processes that do NOT end on their own (inotifywait -m and similar), see
// services/ProcessWatcher.qml.
Backend.ProcessRunner {}

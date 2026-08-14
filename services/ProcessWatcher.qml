import Omafiles.Backend as Backend

// Watches a process that does NOT end on its own (inotifywait -m and similar,
// monitor mode): it emits lineRead for each line instead of a final result
// (start / stop / active / lineRead). Thin adapter that re-exports the
// C++ type Omafiles.Backend.ProcessWatcher (QProcess in monitor mode, see
// backend/ProcessWatcher.cpp) under the name Omafiles.Services.ProcessWatcher.
//
// Phase 5.C (josema): a SINGLE implementation for both frontends, like
// ProcessRunner -- 
// only this QML<->C++ seam remains. Only current use: watching
// changes in the active folder (see logic/NavigationController.qml).
Backend.ProcessWatcher {}

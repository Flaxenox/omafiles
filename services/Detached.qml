pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// "Fire and forget" execution of an external process -- no result
// tracking, no busy/cancel (for that, services/ProcessRunner.qml).
// Thin adapter over the C++ singleton Omafiles.Backend.Detached
// (QProcess::startDetached, see backend/Detached.cpp).
//
// Phase 5.C (josema): a SINGLE implementation for both frontends. Previously
// this delegated to Quickshell.execDetached() and the standalone had a stub
// that only warned on the console; now both use the same C++ backend and the
// stub disappears. logic/ keeps calling Detached.run(args) the same.
QtObject {
  function run(args) { Backend.Detached.run(args) }
}

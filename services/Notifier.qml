pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Desktop notifications -- thin adapter over the C++ singleton
// Omafiles.Backend.Notifier (detached notify-send, "Omafiles" title
// centralized in C++, see backend/Notifier.cpp).
//
// Phase 5.C (josema): a SINGLE implementation for both frontends. Previously
// this built Quickshell.execDetached(["notify-send", ...]) and the
// standalone had a stub that only printed on the console; now both
// use the same C++ backend and the stub disappears. Each of the 16+
// call sites keeps doing Notifier.notify(text) without noticing
// (before centralizing this, each site repeated "Omafiles" by hand).
QtObject {
  function notify(text) { Backend.Notifier.notify(text) }
}

pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Reactive device watcher -- thin adapter over the C++ singleton
// Omafiles.Backend.UDisksWatcher (D-Bus subscription to org.freedesktop.UDisks2,
// see backend/UDisksWatcher.cpp). Phase 20 (josema): reactive replacement for the
// 7 s polling. Since the contract is a SIGNAL (not a function), this
// adapter re-emits it so logic/core do not import Omafiles.Backend
// (rule 8), just as JsonStore re-emits loaded/saved.
QtObject {
  id: root

  // Re-emitted when UDisks2 notifies any block-device
  // change. The frontend responds with refreshMounts().
  signal devicesChanged()

  function available() { return Backend.UDisksWatcher.available() }

  property Connections _c: Connections {
    target: Backend.UDisksWatcher
    function onDevicesChanged() { root.devicesChanged() }
  }
}

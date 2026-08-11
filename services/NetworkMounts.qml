pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// GVfs network mounts -- thin adapter over the C++ singleton
// Omafiles.Backend.NetworkMounts (reads $XDG_RUNTIME_DIR/gvfs, see
// backend/NetworkMounts.cpp). Phase 16 (josema): native replacement for
// list-network-mounts.sh. Forwards list() so logic/ does not import
// Omafiles.Backend (rule 8). Like the rest of services/.
QtObject {
  // Network locations mounted right now: [{ label, path, scheme }].
  function list() { return Backend.NetworkMounts.list() }
}

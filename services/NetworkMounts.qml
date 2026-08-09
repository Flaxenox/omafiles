pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Montajes de red GVfs -- adaptador fino sobre el singleton C++
// Omafiles.Backend.NetworkMounts (lee $XDG_RUNTIME_DIR/gvfs, ver
// backend/NetworkMounts.cpp). Fase 16 (josema): sustituto nativo de
// list-network-mounts.sh. Reenvía list() para que logic/ no importe
// Omafiles.Backend (regla 8). Igual que el resto de services/.
QtObject {
  // Ubicaciones de red montadas ahora mismo: [{ label, path, scheme }].
  function list() { return Backend.NetworkMounts.list() }
}

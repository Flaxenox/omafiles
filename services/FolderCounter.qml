pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Contador de items por carpeta -- adaptador fino sobre el singleton C++
// Omafiles.Backend.FolderCounter (QDirIterator async, ver
// backend/FolderCounter.cpp). Como el contrato es async (señal counted),
// reemite la señal para que logic/panels no importen Omafiles.Backend
// (regla 8), igual que JsonStore con loaded/saved.
QtObject {
  id: root

  // n = nº de entradas directas de `path` (-1 si no se pudo abrir).
  signal counted(string path, int n)

  function request(path, includeHidden) { Backend.FolderCounter.request(path, includeHidden) }

  property Connections _c: Connections {
    target: Backend.FolderCounter
    function onCounted(path, n) { root.counted(path, n) }
  }
}

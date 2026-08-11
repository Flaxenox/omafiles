pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Item counter per folder -- thin adapter over the C++ singleton
// Omafiles.Backend.FolderCounter (async QDirIterator, see
// backend/FolderCounter.cpp). Since the contract is async (counted signal),
// it re-emits the signal so logic/panels do not import Omafiles.Backend
// (rule 8), like JsonStore with loaded/saved.
QtObject {
  id: root

  // n = number of direct entries of `path` (-1 if it could not be opened).
  signal counted(string path, int n)

  function request(path, includeHidden) { Backend.FolderCounter.request(path, includeHidden) }

  property Connections _c: Connections {
    target: Backend.FolderCounter
    function onCounted(path, n) { root.counted(path, n) }
  }
}

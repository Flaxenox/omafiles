import "../Utils.js" as Utils
import QtQuick
import "../state"

// Delete (to trash, or permanent if already viewing the trash) --
// twenty-third component extracted from core.
Item {
  property Item root: null
  property Item actionEngine: null

  property Item selectionOps: null

  function requestDelete() {
    if (ArchiveState.inArchive) return
    var names = selectionOps.selectedEntries().map(function (e) { return e.name })
    if (names.length === 0) return
    root.pendingDeleteNames = names
  }

  function confirmDelete() {
    var names = root.pendingDeleteNames
    root.pendingDeleteNames = []
    if (names.length === 0) return
    if (NavState.currentPath === Paths.trashDir) {
      // NATIVE permanent delete (Phase 13.C): FileOperations.remove instead
      // of `rm -rf`/`rm -f`. No undo possible. TrashState.trashInfo (see
      // trash-info.sh) knows the real physical root of each item -- it can be the
      // home trash or that of any other mounted disk, Paths.trashDir can no longer
      // be assumed outright. For each item the file at
      // <root>/files/<n> (recursive) and its <root>/info/<n>.trashinfo are deleted, both
      // with ignoreMissing (= `rm -f`: it being missing is not an error).
      var paths = []
      names.forEach(function (n) {
        var info = TrashState.trashInfo[n]
        if (!info) return
        paths.push(info.trashRoot + "/files/" + n)
        paths.push(info.trashRoot + "/info/" + n + ".trashinfo")
      })
      if (paths.length > 0) actionEngine.runNativeRemove(paths, "", true)
    } else {
      // NATIVE send to trash (Phase 13.D): FileOperations.trash
      // (QFile::moveToTrash, XDG Trash) instead of `gio trash`. Original
      // absolute paths captured HERE (not inside the closures
      // below) -- NavState.currentPath may have changed by the time
      // the user presses undo, much later.
      var origPaths = names.map(function (n) { return Utils.joinPath(NavState.currentPath, n) })
      var label = names.length === 1 ? "delete \"" + names[0] + "\"" : "delete " + names.length + " items"
      actionEngine.runNativeTrash(origPaths, "", function () {
        // The undo is only registered if the send confirmed success. Undo =
        // restore BY ORIGINAL PATH (Phase 13.E, restoreByOrigPath): it searches
        // in ALL the active trashes for the .trashinfo whose original path
        // matches, so it works the same wherever the delete came from -- and it works
        // even if the user undoes much later without having ever opened the
        // Trash.
        actionEngine.pushUndo(label, function () {
          return actionEngine.runNativeRestore(origPaths, "")
        }, function () {
          return actionEngine.runNativeTrash(origPaths, "")
        })
      })
    }
  }
}

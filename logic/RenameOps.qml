import QtQuick
import qs.Commons
import "../state"
import Omafiles.Backend as Backend

// Rename / new folder / new file, with their undo -- seventeenth
// component extracted from core. Same pattern as FileOps: no
// (actionEngine.runAction/actionEngine.pushUndo).
//
// Phase 7 (josema): "new folder" (common case, without overwriting) is the
// FIRST operation wired to the native backend -- it creates with
// FileOperations.mkdir instead of "mkdir -p" via shell. The rest of the
// operations stays in the shell action engine until a later step. The undo is
// kept with rmdir (fails if the user already put something inside, on purpose).
Item {
  id: renameOps
  property Item root: null
  property Item actionEngine: null
  property Item navController: null


  // Native "new folder" paths in flight -> name. The undo is registered
  // only when FileOperations.mkdir finishes SUCCESSFULLY (see the Connections
  // below), not before nor on a redo. Same pattern as Persistence with
  // JsonStore (declarative Connections over the services singleton).
  property var _nativeMkdirPending: ({})

  function startRename(index) {
    if (ArchiveState.inArchive) return
    if (index < 0 || index >= NavState.visibleEntries.length) return
    EditModeState.creatingFolder = false
    EditModeState.creatingFile = false
    EditModeState.renamingIndex = index
  }

  function runPendingRename(overwrite) {
    var r = ConflictState.pendingRename
    ConflictState.pendingRename = null
    ConflictState.renameConflictOpen = false
    if (!r) return
    var oldName = r.oldPath.substring(r.oldPath.lastIndexOf("/") + 1)
    // Same as in makeLinkFor: the undo is only registered if the "mv"
    // actually happened. Before, it was always registered, even when runAction
    // discarded it because another action was in progress (the rename had
    // already been assumed done in the UI -- the input closed anyway).
    var renameCmd = "mv " + (overwrite ? "-f" : "-n") + " -- " + Util.shellQuote(r.oldPath) + " " + Util.shellQuote(r.newPath)
    actionEngine.runAction(renameCmd, undefined, function () {
      actionEngine.pushUndo("rename to \"" + oldName + "\"", function () {
        return actionEngine.runAction("mv -n -- " + Util.shellQuote(r.newPath) + " " + Util.shellQuote(r.oldPath))
      }, function () {
        return actionEngine.runAction(renameCmd)
      })
    })
  }

  function cancelPendingRename() {
    ConflictState.pendingRename = null
    ConflictState.renameConflictOpen = false
  }

  function startNewFolder() {
    if (ArchiveState.inArchive) return
    EditModeState.renamingIndex = -1
    NavState.searching = false
    EditModeState.creatingFile = false
    EditModeState.creatingFolder = true
  }

  function startNewFile() {
    if (ArchiveState.inArchive) return
    EditModeState.renamingIndex = -1
    NavState.searching = false
    EditModeState.creatingFolder = false
    EditModeState.creatingFile = true
  }

  // commitNewFile()/commitNewFolder() (check whether something with
  // that name already exists) live in logic/ConflictActions.qml, next to
  // newFileCheckProc/newFolderCheckProc -- same pattern as commitRename/
  // renameCheckProc. These two are the real execution (with overwrite=true
  // if the user confirmed overwriting in the conflict dialog).
  function runPendingNewFile(overwrite) {
    var pending = ConflictState.pendingNewFile
    ConflictState.pendingNewFile = null
    ConflictState.newFileConflictOpen = false
    if (!pending) return
    // overwrite: -rf first (it could be a whole folder, not just a
    // file) and then touch -- consistent with the "-f" already used by
    // paste/drop when overwriting (forces without going through the trash).
    var newFileCmd = (overwrite ? "rm -rf -- " + Util.shellQuote(pending.path) + " && " : "")
      + "touch -- " + Util.shellQuote(pending.path)
    actionEngine.runAction(newFileCmd, undefined, function () {
      // gio trash instead of rm: if the user already wrote something before
      // undoing, it goes to the trash instead of being lost with no recovery.
      // It does not try to restore whatever it may have overwritten -- same limit
      // that paste/drop with overwrite already has.
      actionEngine.pushUndo("new file \"" + pending.name + "\"", function () {
        return actionEngine.runAction("gio trash -- " + Util.shellQuote(pending.path))
      }, function () {
        return actionEngine.runAction(newFileCmd)
      })
    })
  }

  function cancelPendingNewFile() {
    ConflictState.pendingNewFile = null
    ConflictState.newFileConflictOpen = false
  }

  function runPendingNewFolder(overwrite) {
    var pending = ConflictState.pendingNewFolder
    ConflictState.pendingNewFolder = null
    ConflictState.newFolderConflictOpen = false
    if (!pending) return
    if (overwrite) {
      // Overwriting an already-existing name (rare case): it implies a
      // destructive rm -rf, it stays in the tested shell action engine -- Phase
      // 7 only wires the mkdir of the common case to the native backend.
      var cmd = "rm -rf -- " + Util.shellQuote(pending.path) + " && mkdir -p -- " + Util.shellQuote(pending.path)
      actionEngine.runAction(cmd, undefined, function () {
        actionEngine.pushUndo("new folder \"" + pending.name + "\"", function () {
          return actionEngine.runAction("rmdir -- " + Util.shellQuote(pending.path))
        }, function () {
          return actionEngine.runAction(cmd)
        })
      })
      return
    }
    // Common case: NATIVE mkdir. The undo is registered on
    // successful completion (see the Connections below).
    renameOps._nativeMkdirPending[pending.path] = pending.name
    Backend.FileOperations.mkdir(pending.path)
  }

  // Closes the loop of the native "new folder": refreshes and registers the
  // undo when mkdir finishes well. Declarative like Persistence with
  // JsonStore.
  Connections {
    target: Backend.FileOperations
    function onFinished(op, path) {
      if (op !== "mkdir") return
      // Immediate refresh (like actionProc.onFinished): the active panel is
      // covered by the watcher, but refreshTick also refreshes the background
      // ones showing this same folder.
      navController.refresh()
      NavState.refreshTick += 1
      var name = renameOps._nativeMkdirPending[path]
      if (name === undefined) return // redo or another mkdir: do not re-register
      delete renameOps._nativeMkdirPending[path]
      actionEngine.pushUndo("new folder \"" + name + "\"", function () {
        // rmdir (not rm -rf): if there is already something inside, it fails instead of deleting it.
        return actionEngine.runAction("rmdir -- " + Util.shellQuote(path))
      }, function () {
        Backend.FileOperations.mkdir(path) // redo: without re-registering
        return true
      })
    }
    function onError(op, path, message) {
      if (op === "mkdir" && renameOps._nativeMkdirPending[path] !== undefined)
        delete renameOps._nativeMkdirPending[path]
      if (op === "mkdir" && message && message !== "cancelled")
        Backend.Notifier.notify(message || "Rename failed")
    }
  }

  function cancelPendingNewFolder() {
    ConflictState.pendingNewFolder = null
    ConflictState.newFolderConflictOpen = false
  }
}

pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// File operations -- thin adapter over the C++ singleton
// Omafiles.Backend.FileOperations (QFile/QDir, see backend/FileOperations.
// cpp). Phase 7 (josema): native backend introduced; for now only
// "new folder" (mkdir) consumes it live (see logic/RenameOps.qml).
//
// It forwards the calls and re-emits progress/finished/error so logic/
// does not import Omafiles.Backend (rule 8). It integrates Notifier (req 4): an
// error is warned here, in a single place, with the same text that
// ActionEngine gave ("Action failed: ..."). The refresh after the operation is NOT
// triggered here -- it is done by DirectoryModel's QFileSystemWatcher (Phase
// 6.D) when the active directory changes.
QtObject {
  id: fileOps
  signal progress(string op, string path, var done, var total)
  signal finished(string op, string path)
  signal error(string op, string path, string message)

  function copy(source, destination, overwrite) { Backend.FileOperations.copy(source, destination, overwrite === true) }
  function move(source, destination, overwrite) { Backend.FileOperations.move(source, destination, overwrite === true) }
  function rename(path, newName) { Backend.FileOperations.rename(path, newName) }
  function remove(path, ignoreMissing) { Backend.FileOperations.remove(path, ignoreMissing === true) }
  function mkdir(path) { Backend.FileOperations.mkdir(path) }
  function trash(path) { Backend.FileOperations.trash(path) }
  function restore(path) { Backend.FileOperations.restore(path) }
  // Restore by original path (Phase 13.E): finds the correct .trashinfo in
  // all the trashes. Emits finished("restore", origPath) / error.
  function restoreByOrigPath(origPath) { Backend.FileOperations.restoreByOrigPath(origPath) }

  // Native Trash listing (Phase 16): active XDG roots and metadata
  // of the .trashinfo. They replace trash-roots.sh / trash-info.sh; synchronous.
  function trashRoots() { return Backend.FileOperations.trashRoots() }
  function trashInfo() { return Backend.FileOperations.trashInfo() }
  // Cancels the operation in progress (Phase 13.A). The worker aborts and emits
  // error "cancelled", which onError does NOT notify (it is a cancellation requested
  // by the user, not a failure).
  function cancel() { Backend.FileOperations.cancel() }

  // Native conflict detection (Phase 13.F): subset of `paths` that already
  // exist. Synchronous; replaces the shell `test -e` in paste/drop.
  function existingPaths(paths) { return Backend.FileOperations.existingPaths(paths) }

  // Total size (bytes) of a set of paths (Phase 13.G): for the
  // copy/move progress percentage without `du` and the size of a multiple
  // selection in Properties (BUG-03).
  function totalSize(paths) { return Backend.FileOperations.totalSize(paths) }

  // Octal mode (%a) of each path, in the same order (BUG-03): to prefill the
  // chmod dialog of a multiple selection without `stat -c%a -- ...`.
  function octalModes(paths) { return Backend.FileOperations.octalModes(paths) }

  // Qualified with the id: Backend.FileOperations (the target) has signals
  // of the same name; without the id, re-emitting could resolve to the target's
  // own signal instead of this adapter's (same kind of collision that
  // there was in DirLister.directoryChanged).
  property Connections _backend: Connections {
    target: Backend.FileOperations
    function onProgress(op, path, done, total) { fileOps.progress(op, path, done, total) }
    function onFinished(op, path) { fileOps.finished(op, path) }
    function onError(op, path, message) {
      // "cancelled" = cancellation requested by the user (FileOperations.
      // cancel), not a failure: it is not warned. The consumer (ActionEngine) already
      // cleans up the state and the partial destination. Phase 13.A.
      if (message !== "cancelled")
        Backend.Notifier.notify("Action failed: " + message)
      fileOps.error(op, path, message)
    }
  }
}

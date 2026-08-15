import QtQuick
import "../state"
import Omafiles.Backend as Backend

// The central file action engine (rename/delete/copy/move/
// compress/extract/chmod/link, everything goes through here) + undo/redo +
// the copy/move progress bar -- thirteenth component
// extracted from core, and the most impactful: dozens of functions in
// core (commitNewFolder, requestDelete, runPaste, runDrop,
// commitChmod, makeLinkFor, restoreFromTrash...) call runAction()/
// pushUndo() as if they were their own. Changing the 50+ call sites
// would have been far more risk than the benefit -- instead, root
Item {
  property Item root: null
  property Item navController: null


  // Simple stack of reversible actions: rename, new folder/file,
  // delete (to trash), move (cut+paste/drag), bulk
  // rename, chmod and link. Copy/compress are left out on purpose --
  // undoing them is more ambiguous (delete the copy? what if it was already moved/edited?)
  // than losing by mistake something renamed/moved/deleted/with permissions
  // changed. undoStack/redoStack themselves live in state/UndoState.qml
  // (singleton) -- only these three functions that manipulate them live here.
  function pushUndo(label, undoFn, redoFn) {
    UndoState.undoStack = UndoState.undoStack.concat([{ label: label, undo: undoFn, redo: redoFn }]).slice(-20)
    UndoState.redoStack = []
  }

  function undoLast() {
    if (UndoState.undoStack.length === 0) return
    var entry = UndoState.undoStack[UndoState.undoStack.length - 1]
    UndoState.undoStack = UndoState.undoStack.slice(0, -1)
    // entry.undo() returns what runAction() returns: false if it was
    // discarded because another action was in progress. Before, this said "Undone"
    // no matter what, even when the undo didn't even get
    // launched, AND the entry was lost from the stack anyway. Now, if it
    // didn't get launched, it is returned to the stack so it can be retried.
    var started = entry.undo()
    if (started === false) {
      UndoState.undoStack = UndoState.undoStack.concat([entry])
      Backend.Notifier.notify("Couldn't undo \"" + entry.label + "\": still busy with another action")
      return
    }
    // It only goes to the redo stack if it really has a way to be redone
    // -- not every undoStack entry has a redoFn (see the
    // comment next to pushUndo).
    if (entry.redo) UndoState.redoStack = UndoState.redoStack.concat([entry]).slice(-20)
    Backend.Notifier.notify("Undoing: " + entry.label)
  }

  function redoLast() {
    if (UndoState.redoStack.length === 0) return
    var entry = UndoState.redoStack[UndoState.redoStack.length - 1]
    UndoState.redoStack = UndoState.redoStack.slice(0, -1)
    var started = entry.redo()
    if (started === false) {
      UndoState.redoStack = UndoState.redoStack.concat([entry])
      Backend.Notifier.notify("Couldn't redo \"" + entry.label + "\": still busy with another action")
      return
    }
    // Back to undoStack WITHOUT going through pushUndo() -- that would empty
    // redoStack, which is exactly what we don't want in the middle of an
    // undo/redo/undo cycle.
    UndoState.undoStack = UndoState.undoStack.concat([entry]).slice(-20)
    Backend.Notifier.notify("Redoing: " + entry.label)
  }

  function runAction(cmd, busyLabel, onSuccess) {
    // actionProc is a single process shared by all file
    // actions (rename, delete, copy/move, compress...). Without this
    // guard, a second call while the first is still running
    // (double click, or an extra keypress during a long operation)
    // changed its command and restarted it, cutting off the ongoing operation
    // mid-copy without any notice.
    if (actionProc.busy || nativeBusy) {
      Backend.Notifier.notify("Still busy with the previous action — try again in a moment")
      return false
    }
    ActionState.actionLabel = busyLabel || ""
    ActionState.actionBusy = !!busyLabel
    ActionState._actionOnSuccess = onSuccess || null
    // group:true -- the command runs in its own process group instead
        // kill the "bash -c" itself -- any cp/mv/zip that bash had
    // launched as a child was left orphaned and kept running in the background
    // as if nothing, even though the UI had already given the action for cancelled.
    actionProc.start(["bash", "-c", cmd], true)
    return true
  }

  // Joins commands of a batch operation (paste/drop/delete N files,
  // bulk rename...) so that one's failure doesn't eat the others.
  // Before they were joined with "&&": as soon as item 2 of 5 failed (no longer
  // existed, permission denied...) items 3-5 weren't even attempted
  // and on top of that there was no notice. With this, all are attempted, and if any
  // fails the process exits with status != 0 so actionProc reports it
  // (see runAction/actionProc above) -- without saying which one specifically,
  // but they are no longer lost silently.
  function chainCmds(cmds) {
    if (cmds.length <= 1) return cmds[0] || "true"
    return "st=0; " + cmds.map(function (c) { return "{ " + c + "; } || st=1" }).join("; ") + "; exit $st"
  }

  function cancelAction() {
    // Native copy/move in progress (Phase 13.A/G): cooperative cancellation
    // in C++. The worker aborts between chunks, CLEANS UP ITSELF the partial
    // copy of the destination (forceRemove in backend/FileOperations) and emits error
    // "cancelled" -> bad() -> _nativeDone cleans up the state and refreshes. There is no longer
    // a shell `rm -rf`: the backend is self-sufficient to clean up.
    if (nativeBusy) {
      _cancelling = true
      Backend.FileOperations.cancel()
      return
    }
    // Actions still in shell (compress/extract/rename/create): actionProc.
    // cancel() kills the whole process group. They have no progress nor a
    // partial destination to clean up here (their overwrite is atomic or handled
    // by their own command).
    actionProc.cancel()
    _resetActionState()
  }

  function _resetActionState() {
    ActionState.actionBusy = false
    ActionState.actionLabel = ""
    ActionState.actionProgressPct = -1
    navController.refresh()
    NavState.refreshTick += 1
  }

  // ---------- Native byte progress & batch lifecycle ----------
  // Replaces du polling with totalSize + Backend.FileOperations signals.
  property real _progTotal: 0   // total bytes of the batch (all sources)
  property real _progBase: 0    // bytes already completed from previous items
  property real _lastItemTotal: 0 // total of the current item (last progress)

  function startCopyProgress(sourcePaths, destPaths) {
    _progTotal = Backend.FileOperations.totalSize(sourcePaths)
    _progBase = 0
    _lastItemTotal = 0
    // Bar from 0% if there is something to measure; dots if the total is 0 (empty items).
    ActionState.actionProgressPct = _progTotal > 0 ? 0 : -1
  }

  // Static declarative signal handler for all native file operations:
  // eliminates per-batch-item dynamic connect()/disconnect() churn.
  Connections {
    target: Backend.FileOperations

    function onProgress(op, path, done, total) {
      if (!nativeBusy || _progTotal <= 0) return
      _lastItemTotal = total
      ActionState.actionProgressPct = Math.min(100, (_progBase + done) * 100 / _progTotal)
    }

    function onFinished(op, path) {
      if (!nativeBusy) return
      if (_nativeKind === "emptyTrash") {
        _finishNative(true)
        return
      }
      _progBase += _lastItemTotal
      _lastItemTotal = 0
      _batchIdx += 1
      _batchNext()
    }

    function onError(op, path, msg) {
      if (!nativeBusy) return
      if (msg && msg !== "cancelled")
        Backend.Notifier.notify(msg || "Action failed")
      _finishNative(false)
    }
  }

  // ---------- Native copy/move/trash/restore/remove/emptyTrash ----------
  property bool nativeBusy: false
  property string _nativeKind: "copy"
  property var _batchQueue: []
  property int _batchIdx: 0
  property bool _batchOverwrite: false
  property var _batchOnDone: null
  property bool _cancelling: false

  function runNativeCopy(pairs, busyLabel, overwrite, onDone) {
    return _runNative("copy", pairs, busyLabel, overwrite, onDone)
  }

  function runNativeMove(pairs, busyLabel, overwrite, onDone) {
    return _runNative("move", pairs, busyLabel, overwrite, onDone)
  }

  function _toPairs(paths) {
    return paths.map(function (p) { return { src: p } })
  }

  function runNativeRemove(paths, busyLabel, ignoreMissing, onDone) {
    return _runNative("remove", _toPairs(paths), busyLabel, ignoreMissing, onDone)
  }

  function runNativeTrash(paths, busyLabel, onDone) {
    return _runNative("trash", _toPairs(paths), busyLabel, false, onDone)
  }

  function runNativeRestore(origPaths, busyLabel, onDone) {
    return _runNative("restore", _toPairs(origPaths), busyLabel, false, onDone)
  }

  function emptyTrash(onDone) {
    if (actionProc.busy || nativeBusy) {
      Backend.Notifier.notify("Still busy with the previous action — try again in a moment")
      return false
    }
    nativeBusy = true
    _cancelling = false
    _nativeKind = "emptyTrash"
    _batchQueue = []
    _batchIdx = 0
    _batchOverwrite = false
    _batchOnDone = onDone || null
    ActionState.actionLabel = "Emptying trash…"
    ActionState.actionBusy = true
    ActionState.actionProgressPct = -1
    Backend.FileOperations.emptyTrash()
    return true
  }

  function _runNative(kind, pairs, busyLabel, overwrite, onDone) {
    if (actionProc.busy || nativeBusy) {
      Backend.Notifier.notify("Still busy with the previous action — try again in a moment")
      return false
    }
    nativeBusy = true
    _cancelling = false
    _nativeKind = kind
    _batchQueue = pairs
    _batchIdx = 0
    _batchOverwrite = overwrite === true
    _batchOnDone = onDone || null
    ActionState.actionLabel = busyLabel || ""
    ActionState.actionBusy = !!busyLabel
    if (busyLabel && (kind === "copy" || kind === "move"))
      startCopyProgress(pairs.map(function (p) { return p.src }),
                        pairs.map(function (p) { return p.dest }))
    _batchNext()
    return true
  }

  function _batchNext() {
    if (_cancelling) { _finishNative(false); return }
    if (_batchIdx >= _batchQueue.length) { _finishNative(true); return }
    var p = _batchQueue[_batchIdx]
    if (_nativeKind === "remove")
      Backend.FileOperations.remove(p.src, _batchOverwrite)  // _batchOverwrite = ignoreMissing
    else if (_nativeKind === "trash")
      Backend.FileOperations.trash(p.src)
    else if (_nativeKind === "restore")
      Backend.FileOperations.restoreByOrigPath(p.src)
    else if (_nativeKind === "move")
      Backend.FileOperations.move(p.src, p.dest, _batchOverwrite)
    else
      Backend.FileOperations.copy(p.src, p.dest, _batchOverwrite)
  }

  function _finishNative(success) {
    nativeBusy = false
    _resetActionState()
    var cb = _batchOnDone
    _batchOnDone = null
    if (success && cb) Qt.callLater(cb)
  }

  Backend.ProcessRunner {
    id: actionProc
    onFinished: function (result) {
      _resetActionState()
      var cb = ActionState._actionOnSuccess
      ActionState._actionOnSuccess = null
      if (result.exitCode === 0) {
        if (cb) cb()
      } else if (!result.cancelled) {
        Backend.Notifier.notify(result.stderr.trim() || "Couldn't restore from trash")
      }
    }
  }

  // Removed actionProgressTotalProc / actionProgressPollProc /
  // actionProgressPollTimer: progress is no longer polled with `du`, it comes by
  // bytes from the FileOperations.progress signal (see the Connections above).
}

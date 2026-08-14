pragma Singleton
import QtQuick

// State of the action engine (runAction/cancelAction/copy/move
// progress) -- twelfth singleton of the state/ layer, completes
// the migration of logic/ActionEngine.qml (whose undoStack/redoStack already
// live in state/UndoState.qml). actionBusyDots stays in core
// on purpose -- it is a purely visual animation (a Timer in the UI
// itself), ActionEngine.qml neither reads nor writes it.
QtObject {
  property bool actionBusy: false
  property string actionLabel: ""
  // -1 = no progress to show (rename/chmod/compress...), only
  // copy/move actually fill it -- see startCopyProgress().
  property real actionProgressPct: -1
  // Pending callback of the running runAction -- see actionProc.onFinished
  // in ActionEngine.qml. (_actionCancelled disappeared in Phase 1.5:
  // ProcessRunner.finished already carries `cancelled` in the result, see
  // Omafiles.Backend.ProcessRunner.)
  property var _actionOnSuccess: null
}

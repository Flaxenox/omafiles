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

  // Names awaiting the delete/trash ConfirmDialog -- set by
  // ActionEngine.requestDelete(), read and cleared by
  // ActionEngine.confirmDelete() and by core/DialogLayer.qml's
  // deleteConfirm (opened/message/onCanceled). Previously lived as an
  // untyped `root.pendingDeleteNames` on core/OmafilesContent.qml, the one
  // outlier among ActionEngine's pending-confirmation state that wasn't
  // migrated here with the rest (architectural audit 2026-08-17,
  // P2.1 follow-up) -- every sibling "is a confirm dialog open" check in
  // KeyboardShortcuts.qml/OmafilesContent.qml already reads a state/
  // singleton directly (ConflictState.*ConflictOpen etc.), this was the
  // only one going through `root` instead.
  property var pendingDeleteNames: []
}

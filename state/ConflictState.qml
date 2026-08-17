pragma Singleton
import QtQuick

// State of the six conflict dialogs (rename/paste/extract/
// compress/bulk-rename/drop) -- fourth singleton of the
// state/ layer, same pattern validated with Selection/Clipboard/Undo. The
// logic that decides when to open them and what to do on confirm lives in
// logic/ActionEngine.qml (corrected 2026-08-17, P2.1 follow-up -- this
// used to name six separate *Ops.qml/ConflictActions.qml files, all
// folded into ActionEngine.qml on 2026-08-15).
QtObject {
  property var pendingRename: null // { oldPath, newPath }
  property bool renameConflictOpen: false

  property var pendingNewFile: null // { path, name }
  property bool newFileConflictOpen: false

  property var pendingNewFolder: null // { path, name }
  property bool newFolderConflictOpen: false

  property var pasteConflictNames: []
  property bool pasteConflictOpen: false

  property var pendingExtract: null // { entry, cmd }
  property var extractConflictNames: []
  property bool extractConflictOpen: false

  property var pendingCompress: null // { archiveName, cmd }
  property bool compressConflictOpen: false

  property var pendingBulkRename: null // [{ oldName, newName, oldPath, newPath }]
  property int bulkRenameInternalDupes: 0
  property int bulkRenameConflictCount: 0
  property bool bulkRenameConflictOpen: false

  // ---------- Drag and drop ----------
  // Deliberately separate from the Ctrl+C/X/V clipboard (see
  // state/ClipboardState.qml) -- a drag must not clobber what the user
  // has copied by hand. Internal (same app) = move; from outside (another
  // app) = copy, decided by DragEvent.source (null if the drag comes
  // from outside).
  property var dropPendingSources: []
  property string dropTargetDir: ""
  property bool dropIsMove: false
  property var dropConflictNames: []
  property bool dropConflictOpen: false
}

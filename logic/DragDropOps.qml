import "../Utils.js" as Utils
import QtQuick
import qs.Commons
import "../state"

// Drag and drop (within the app, and from/to others) --
// nineteenth component extracted from core.
Item {
  property Item root: null
  // conflictActions.startDropInto() is the one that actually checks
  // conflicts -- handleFilesDropped() only resolves the DragEvent itself
  // (accept/reject, move vs copy). runDrop() (the real execution of the
  // mv/cp) lives in logic/ConflictActions.qml next to dropCheckProc, which
  // calls it -- if it stayed here, DragDropOps and ConflictActions would
  // need each other (circular dependency, rule 5 of the architecture
  // prompt). With the executor there, the dependency stays one-way:
  // DragDropOps -> ConflictActions.
  property Item conflictActions: null
  property Item selectionOps: null

  function urlToPath(url) {
    var s = String(url)
    if (s.indexOf("file://") === 0) s = s.substring(7)
    try { return decodeURIComponent(s) } catch (e) { return s }
  }

  // MimeData of the file(s) that row `index` starts to drag --
  // if that row is already part of a multiple selection, it drags the whole
  // selection (like Nautilus); if not, only that row.
  function dragMimeDataFor(index) {
    var indices = (selectionOps.isSelected(index) && SelectionState.selectedIndices.length > 1) ? SelectionState.selectedIndices : [index]
    var paths = indices
      .filter(function (i) { return i >= 0 && i < NavState.visibleEntries.length })
      .map(function (i) { return Utils.joinPath(NavState.currentPath, NavState.visibleEntries[i].name) })
    var data = {}
    data["text/uri-list"] = paths.map(function (p) { return Util.fileUrl(p) }).join("\r\n")
    return data
  }

  // runDrop() (executes the real mv/cp after resolving a drop conflict)
  // lives in logic/ConflictActions.qml -- see the comment next to
  // `conflictActions` above.

  function cancelDropConflict() {
    ConflictState.dropConflictOpen = false
    ConflictState.dropConflictNames = []
    ConflictState.dropPendingSources = []
    ConflictState.dropTargetDir = ""
  }

  // Called from each DropArea (folder row, bookmark, drive, list
  // background) with the real DragEvent and the destination folder already resolved.
  function handleFilesDropped(drop, destDir) {
    if (ArchiveState.inArchive) { drop.accepted = false; return }
    if (!drop.hasUrls) { drop.accepted = false; return }
    var paths = drop.urls.map(function (u) { return urlToPath(u) }).filter(function (p) { return p.length > 0 })
    if (paths.length === 0) { drop.accepted = false; return }
    var isMove = drop.source !== null && drop.source !== undefined
    drop.accept(isMove ? Qt.MoveAction : Qt.CopyAction)
    conflictActions.startDropInto(destDir, paths, isMove)
  }
}

pragma Singleton
import QtQuick

// Active-panel view mode (list vs grid), global (not per-tab/per-folder --
// same convention SortState/NavState.showHidden already use). Grid
// geometry (columnsPerRow/cellWidth/cellHeight) lives here rather than
// locally in panels/ActiveFileGrid.qml because SelectionState's marquee
// hit-test and KeyboardShortcuts' up/down-by-row math both need it, and
// state/ singletons can't import panels/ (layering).
QtObject {
  property string mode: "list" // "list" | "grid"
  // Guards against Persistence's restored value being clobbered by the
  // property's own default before the async JsonStore read delivers --
  // same pattern as BookmarksState/other persisted singletons' `loaded`.
  property bool loaded: false

  property int columnsPerRow: 1
  property real cellWidth: 112
  property real cellHeight: 128

  readonly property real minCellWidth: 72
  readonly property real maxCellWidth: 200
  // Height/width ratio of the original default (128/112) -- Ctrl+scroll
  // resizing (ActiveFileList.qml) keeps this proportion instead of only
  // growing/shrinking the thumbnail slot and leaving the name label an
  // odd shape.
  readonly property real _cellAspect: 128 / 112

  function toggleMode() { mode = mode === "grid" ? "list" : "grid" }
  function setCellWidth(w) {
    cellWidth = Math.max(minCellWidth, Math.min(maxCellWidth, w))
    cellHeight = Math.round(cellWidth * _cellAspect)
  }
}

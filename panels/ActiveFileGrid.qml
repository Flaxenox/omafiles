import QtQuick
import qs.Commons
import "../shared"
import "../state"

// GridView counterpart of the ListView inside panels/ActiveFileList.qml --
// the surrounding chrome (separator, wheel scroll, marquee rectangle,
// drop-on-empty, empty state, preview) stays in ActiveFileList.qml and
// reads through `activeView`; this component owns only the grid itself and
// its footer marquee catcher, and re-exposes the same function/property
// surface a ListView/GridView already has (contentY/originY/contentHeight/
// contentItem via alias -- always a FIXED target here, so no conditional-
// alias problem at this layer) so ActiveFileList.qml's `activeView` can
// treat this component and the real ListView interchangeably.
Item {
  id: root
  property Item hostRoot: null
  property Item hostCard: null
  property var hostControllers: null
  property var hostCommandFacade: null
  // Single KeyboardShortcuts instance owned by ActiveFileList.qml, shared
  // with the ListView -- only whichever view actually has `focus` gets key
  // events, so having both forward to the same instance is harmless.
  property Item hostKeyboardShortcuts: null

  property alias contentY: gridView.contentY
  property alias originY: gridView.originY
  property alias contentHeight: gridView.contentHeight
  property alias contentItem: gridView.contentItem
  function forceActiveFocus() { gridView.forceActiveFocus() }
  function positionViewAtBeginning() { gridView.positionViewAtBeginning() }
  function positionViewAtIndex(index, mode) { gridView.positionViewAtIndex(index, mode) }
  function forceLayout() { gridView.forceLayout() }
  // Callers (ActiveFileList.qml's firstVisibleIndex/marquee) pass a point
  // in ROOT's coordinate space (e.g. "root.width / 2") -- gridView is
  // narrower than root and horizontally centered (see cols/width below),
  // so its own indexAt() needs that x translated into ITS local space
  // first, or a wide window with few columns would resolve to a cell
  // that isn't actually under that x at all.
  function indexAt(x, y) { return gridView.indexAt(x - (root.width - gridView.width) / 2, y) }
  function itemAtIndex(index) { return gridView.itemAtIndex(index) }
  // How far gridView's own content-space x=0 sits from root's own x=0,
  // because of the centering below -- ActiveFileList.qml's marquee
  // rectangle overlay needs this to draw at the right x (it positions
  // itself using content-space coordinates that came from
  // MarqueeCatcher's mapToItem(gridView.contentItem, ...), which are
  // relative to gridView, not root).
  readonly property real xOffset: (width - gridView.width) / 2

  // Columns that fit root's FULL width (not gridView's own, narrower,
  // already-centered width below -- that would be circular). A plain
  // `anchors.fill: parent` GridView packs columns from the left and
  // dumps the whole leftover remainder as dead space on the right; this
  // sizes gridView to exactly its columns' width and centers it instead,
  // splitting the remainder evenly on both sides (josema, v1.2-dev).
  readonly property int cols: Math.max(1, Math.floor(width / ViewState.cellWidth))
  onColsChanged: ViewState.columnsPerRow = cols
  Component.onCompleted: ViewState.columnsPerRow = cols

  GridView {
    id: gridView
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(parent.width, root.cols * cellWidth)
    clip: true
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    cellWidth: ViewState.cellWidth
    cellHeight: ViewState.cellHeight
    model: NavState.visibleEntries
    focus: root.hostRoot && root.hostRoot.opened && !NavState.searching && ViewState.mode === "grid"
    onModelChanged: {
      if (root.hostRoot && root.hostRoot.suppressListFade) return
      gridRepopulateFade.restart()
    }
    NumberAnimation {
      id: gridRepopulateFade
      target: gridView
      property: "opacity"
      from: 0
      to: 1
      duration: 140
      easing.type: Easing.OutCubic
    }

    footer: Item {
      width: gridView.width
      height: 200

      MarqueeCatcher {
        anchors.fill: parent
        catcherListView: gridView
        measuredRowHeight: ViewState.cellHeight
        marqueeTarget: SelectionState
      }
    }

    Keys.onPressed: function (event) { if (root.hostKeyboardShortcuts) root.hostKeyboardShortcuts.handlePress(event) }

    delegate: FileGridCell {
      hostRoot: root.hostRoot
      hostGridView: gridView
      hostCard: root.hostCard
      hostNavController: root.hostControllers ? root.hostControllers.navController : null
      hostCommandFacade: root.hostCommandFacade
      hostDragDropOps: root.hostControllers ? root.hostControllers.actionEngine : null
      hostVideoThumbs: root.hostControllers ? root.hostControllers.videoThumbs : null
      hostFileMeta: root.hostControllers ? root.hostControllers.fileMeta : null
      hostConflictActions: root.hostControllers ? root.hostControllers.actionEngine : null
    }
  }
}

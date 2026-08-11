import QtQuick
import qs.Commons
import qs.Ui
import "../shared"
import "../logic"
import "../state"
import "../Utils.js" as Utils

// The main ListView of the active panel (lasso selection, drag and
// drop, keyboard shortcuts, inline rename, per-row context menu) +
// everything around it within listContainer (separator, mouse wheel,
// lasso gutters, empty state, visual lasso rectangle, preview)
// -- twenty-first component extracted from Omafiles.qml, and the
// largest so far. listContainer stays in Omafiles.qml with its height
// calculation (pixel-tuned, see its own comments) intact; this
// component only paints its content with anchors.fill: parent.
//
// The inner ListView was renamed from "list" to "listView" (with id: list
// there would be no way to give the SAME id "list" to the instance of this
// component without colliding) -- but dozens of sites in Omafiles.qml
// (root functions, other dialogs with onFocusReturnRequested, the
// MouseArea of the side gap between sidebar and mainColumn) still
// write `list.contentY`/`list.forceActiveFocus()`/etc. by direct
// id, and changing all those call sites would have been much more
// risky than resolving it here: the instance of this component is still
// called "list" in Omafiles.qml (same id as always), and these aliases +
// shadow functions re-expose exactly the subset of the ListView API that
// is used from outside (contentY/originY/contentHeight/contentItem,
// forceActiveFocus()/positionViewAtBeginning()) -- nothing more, it's not a
// generic ListView wrapper.
Item {
  property Item root: null
  property Item card: null
  property Item actionEngine: null
  property Item navController: null
  property Timer gTimer: null
  property Item previewLoader: null
  property Item conflictActions: null
  property Item mountOps: null
  property Item fileOps: null
  property Item videoThumbs: null
  property Item renameOps: null
  property Item clipboardOps: null
  property Item dragDropOps: null
  property Item searchOps: null
  property Item fileMeta: null
  property Item deleteOps: null
  property Item tabOps: null
  property Item sortOps: null
  property Item selectionOps: null
  property Item deleteConfirm: null
  property Item renameConflictConfirm: null
  property Item extractConflictConfirm: null
  property Item compressConflictConfirm: null
  property Item bulkRenameConflictConfirm: null
  property Item newFileConflictConfirm: null
  property Item newFolderConflictConfirm: null

  property alias contentY: listView.contentY
  property alias originY: listView.originY
  property alias contentHeight: listView.contentHeight
  property alias contentItem: listView.contentItem
  function forceActiveFocus() { listView.forceActiveFocus() }
  function positionViewAtBeginning() { listView.positionViewAtBeginning() }
  function positionViewAtIndex(index, mode) { listView.positionViewAtIndex(index, mode) }
  // Index of the first visible row (to save/restore scroll by
  // index when switching tabs). Encapsulates the inner listView: uses its own
  // width/contentY, not the wrapper's (which differ with the preview open).
  function firstVisibleIndex() { return listView.indexAt(listView.width / 2, listView.contentY + 4) }
  // SUB-ROW offset: how many pixels the top row is shifted up
  // relative to the viewport edge. Without this, restoring by index
  // aligns the row to the edge (Beginning) and, if you were at half a row, it jumped
  // to snap. It's saved along with the index and added when restoring.
  function firstVisibleOffset() {
    var idx = firstVisibleIndex()
    if (idx < 0) return 0
    var it = listView.itemAtIndex(idx)
    return it ? (listView.contentY - it.y) : 0
  }
  // Positions row `idx` reproducing the EXACT sub-row offset. It anchors on
  // the row's real y (itemAtIndex(idx).y), the SAME geometry that
  // firstVisibleOffset used when saving -- if instead the contentY that
  // positionViewAtIndex leaves were used, the two geometries differ (~a handful of px) and the
  // scroll kept drifting each time. positionViewAtIndex instantiates the row first.
  function positionAtIndexWithOffset(idx, offset) {
    listView.forceLayout()
    listView.positionViewAtIndex(idx, ListView.Beginning)
    var it = listView.itemAtIndex(idx)
    if (it) listView.contentY = it.y + offset
  }

  KeyboardShortcuts {
    id: keyboardShortcuts
    hostRoot: root
    hostActionEngine: actionEngine
    hostNavController: navController
    hostListView: listView
    hostGTimer: gTimer
    hostPreviewLoader: previewLoader
    hostConflictActions: conflictActions
    hostMountOps: mountOps
    hostFileOps: fileOps
    hostRenameOps: renameOps
    hostClipboardOps: clipboardOps
    hostDragDropOps: dragDropOps
    hostSearchOps: searchOps
    hostDeleteOps: deleteOps
    hostTabOps: tabOps
    hostSortOps: sortOps
    hostSelectionOps: selectionOps
    hostDeleteConfirm: deleteConfirm
    hostRenameConflictConfirm: renameConflictConfirm
    hostExtractConflictConfirm: extractConflictConfirm
    hostCompressConflictConfirm: compressConflictConfirm
    hostBulkRenameConflictConfirm: bulkRenameConflictConfirm
    hostNewFileConflictConfirm: newFileConflictConfirm
    hostNewFolderConflictConfirm: newFolderConflictConfirm
  }

            // Same line that separates header and list in the background
            // panels (bgHeaderSep) -- it goes in here, not as a sibling in the
            // Column, so the gap between separator and list is the
            // same Style.spacing.sm as there and not the mainColumn.spacing
            // (wider) that the Column puts between ANY pair of children.
            PanelSeparator {
              id: listSep
              anchors.top: parent.top
              foreground: Color.menu.text
              strength: 0.15
            }

            MouseArea {
              // Behind the list: right click on empty space -> general context menu.
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              acceptedButtons: Qt.RightButton
              onClicked: function (mouse) {
                var pos = mapToItem(card, mouse.x, mouse.y)
                root.openContextMenu(pos.x, pos.y, root.emptyAreaActions())
              }
            }

            // Behind the list: dropping here (from another app, or an internal
            // drag onto empty space instead of over a row) puts
            // the files in the folder open right now. Being BEFORE
            // the ListView in the file, it stays below in the paint
            // order -- the DropArea of each folder row, on top,
            // wins when the cursor is over it.
            DropArea {
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              keys: ["text/uri-list"]
              onEntered: function (drag) { if (!drag.hasUrls) drag.accepted = false }
              onDropped: function (drop) {
                dragDropOps.handleFilesDropped(drop, NavState.currentPath)
              }
            }

            // Mouse wheel: with `listView.interactive` false (so that
            // dragging never scrolls, only draws the lasso), Flickable
            // stops processing the wheel too -- it's reimplemented here by
            // hand. Without onPressed/onClicked, so a MouseArea without
            // wheel handling (none of rows/footer/marqueeArea implements
            // it) lets the event pass through to this one, behind everything;
            // that's why a single one, covering the whole area, suffices for rows and
            // empty gaps alike.
            MouseArea {
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              property real wheelAccumulator: 0
              onWheel: function (wheel) {
                var step = Util.wheelSteps(wheelAccumulator, wheel.angleDelta.y)
                wheelAccumulator = step.remainder
                if (step.steps === 0) return
                // The floor is listView.originY, NOT 0 -- ListView can shift
                // its origin with delegate recycling (seen live:
                // originY reached hundreds of pixels after scrolling
                // a lot), and forcing contentY to 0 in that case leaves exactly the
                // empty gap at the very top that the user reported.
                var minY = listView.originY
                var maxY = minY + Math.max(0, listView.contentHeight - listView.height)
                listView.contentY = Math.max(minY, Math.min(maxY, listView.contentY - step.steps * 60))
              }
            }

            // Behind the ListView, only the top gap (outside its
            // bounds, because of `listView`'s topMargin -- the bottom is covered by the
            // footer, inside the ListView itself, see further down). Pressing and
            // dragging here draws a selection lasso (like Nautilus/
            // any icon manager) -- Ctrl held down adds to
            // the previous selection instead of replacing it.
            MarqueeCatcher {
              id: marqueeArea
              anchors.top: parent.top
              height: listView.y
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              catcherListView: listView
              catcherSelectionOps: selectionOps
            }

            ListView {
              id: listView
              anchors.top: listSep.bottom
              // Reserved gap above the first row -- without this there is no
              // "empty" pixel above where to start the lasso, the
              // row 0 would start right at the edge. It only shifts the
              // ListView, marqueeArea/DropArea behind still reach
              // the real edge, so that gap falls on them. Raised
              // from sm to md (josema: little air between the header and the
              // list) -- same value in bgList so the two heights
              // keep matching exactly (see the earlier -1px bug).
              anchors.topMargin: Style.spacing.md
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              clip: true
              model: NavState.visibleEntries
              // Don't reclaim focus while the magnifier is active: if the list
              // takes it, when the model changes (live filter with each letter) it takes it
              // away from the search field and only lets you type one letter. With the
              // magnifier open the keyboard belongs to SearchBar (Up/Down/Enter/Escape),
              // so the list doesn't need focus -- it recovers it on closing the
              // search. (Empirical trace diagnosis: field focus=false right
              // after the first textChanged.)
              focus: root.opened && !NavState.searching
              // Turbo Frame-style micro-transition (Phase 22, DHH/Hotwire): on
              // (re)populating the list -- navigating to another folder, or after an
              // operation that changes the listing -- the list appears with a very
              // short fade. It does NOT delay interaction: the list is
              // navigable/clickable instantly (the opacity doesn't block input).
              // No bounces or springs, just a 140 ms OutCubic.
              //
              // The opacity of the WHOLE CONTAINER is faded, not each delegate via
              // `populate: Transition`. With populate, the ListView fixes the
              // positions of the delegates with their FIRST frame's height (a
              // line, ~40px) and doesn't recalculate them when the row grows to two
              // lines when the async subtitle arrives (folder counter) --
              // it left the active panel's rows overlapping ~9px and with different
              // density than a background panel (which, without populate, does relocate).
              // Fading the container gives the same effect without capturing geometry,
              // so the two panels are identical. Verified live with two
              // panels over the same folder: identical row pitch (49px).
              // Repaint fade (Phase 22) ONLY on real navigation/operation.
              // On a tab switch, root.suppressListFade is set: the
              // listing was already in view as a background panel and fading it on
              // activating it was the redundant flicker on hover.
              onModelChanged: {
                if (root && root.suppressListFade) return
                listRepopulateFade.restart()
              }
              NumberAnimation {
                id: listRepopulateFade
                target: listView
                property: "opacity"
                from: 0
                to: 1
                duration: 140
                easing.type: Easing.OutCubic
              }
              // Without this, dragging with the click (left button held down)
              // scrolls the list -- the same gesture we want
              // entirely free for the selection lasso. Only the
              // wheel should be able to scroll, never the drag. Since
              // Flickable ties the wheel to this same property, it has to be
              // reimplemented by hand (see wheelArea further down).
              interactive: false
              // Without this (default DragAndOvershootBounds), any change
              // in contentHeight while contentY is at the edge (the
              // footer is constantly recalculated from
              // measuredRowHeight) triggers a Flickable bounce
              // animation that can go negative before settling. If
              // the next wheel event arrives mid-animation,
              // the contentY read is no longer the real one and the bounce
              // restarts on a wrong point -- that's what made
              // the top gap grow on each scroll cycle. With this, the
              // limit is hard and immediate, with no animation to interrupt.
              boundsBehavior: Flickable.StopAtBounds

              // Bottom gap for the lasso. A loose MouseArea behind
              // the ListView (like the top one) does NOT work here: being
              // Flickable, ListView keeps any press+drag in
              // ALL its rectangle -- including the gap under the last row,
              // even if there is no delegate there -- before it reaches
              // anything behind (and if `interactive` is disabled to
              // avoid it, wheel scroll is also lost, which
              // depends on the same property). The real solution is a
              // footer: being the ListView's own content (like the
              // rows), it wins the press just like them.
              footer: Item {
                id: listFooter
                width: listView.width
                // FIXED height on purpose -- nothing that depends on
                // measuredRowHeight/contentHeight/visibleEntries.length, nor
                // on any other property that changes during scroll. The
                // footer is the ListView's own content (participates in its
                // delegate relocation/recycling); tying it to something that
                // recalculates during scroll is what left
                // `listView.originY` desynchronized from 0 -- confirmed with a
                // debug reader (originY reached 210 after
                // scrolling up/down several times), and that is exactly
                // the gap that appeared at the very top. With a fixed number
                // the footer is never recalculated, so there is nothing that
                // can perturb the origin.
                height: 400

                MarqueeCatcher {
                  anchors.fill: parent
                  catcherListView: listView
                  catcherSelectionOps: selectionOps
                }
              }

              // Lasso auto-scroll: if the cursor stays stuck to an
              // edge of the list while dragging and there are more rows than
              // fit in the viewport, it scrolls on its own to be able to
              // keep selecting beyond what's visible -- like
              // Nautilus/any manager with a lasso. marqueeViewportY arrives
              // already updated (via mapToItem(listView, ...)) from any
              // lasso catcher, so this doesn't depend on where
              // the drag started.
              Timer {
                interval: 16
                repeat: true
                running: SelectionState.marqueeActive && listView.contentHeight > listView.height
                  && (SelectionState.marqueeViewportY < 32 || SelectionState.marqueeViewportY > listView.height - 32)
                onTriggered: {
                  var minY = listView.originY
                  var maxY = minY + Math.max(0, listView.contentHeight - listView.height)
                  var step = 18
                  if (SelectionState.marqueeViewportY < 32) {
                    listView.contentY = Math.max(minY, listView.contentY - step)
                    SelectionState.marqueeCurrentY = listView.contentY
                  } else {
                    listView.contentY = Math.min(maxY, listView.contentY + step)
                    SelectionState.marqueeCurrentY = listView.contentY + listView.height
                  }
                  selectionOps.updateMarqueeSelection(SelectionState.marqueeAdditive, SelectionState.marqueeBaseSelection)
                }
              }

              Keys.onPressed: function (event) { keyboardShortcuts.handlePress(event) }

              delegate: FileListRow {
                hostRoot: root
                hostListView: listView
                hostCard: card
                hostDragDropOps: dragDropOps
                hostVideoThumbs: videoThumbs
                hostFileMeta: fileMeta
                hostConflictActions: conflictActions
                hostSelectionOps: selectionOps
              }
            }

            // Notice when list-dir.sh could not list currentPath --
            // before this looked just like a truly empty folder, without
            // any hint that the problem was permissions.
            Text {
              // Same anchor and margin as the background panel's error notice
              // (bgErrorText): right under the header separator, at
              // Style.spacing.md -- where the first row would start. Before
              // this one went to parent.top + lg and the background one to separator + sm, so
              // the same error appeared in two different places depending on the panel
              // (Visual Sprint 3, C-05).
              visible: NavState.currentPathError !== ""
              anchors.top: listSep.bottom
              anchors.topMargin: Style.spacing.md
              // No leftMargin: it aligns with the ICON COLUMN (the glyph
              // starts at the content edge), not with the names one -- the
              // notice has no glyph, so it takes its place.
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.rowPaddingX
              // It occupies the icon's height (controlHeight) and centers the text
              // vertically, to stay at the HEIGHT of the glyph (which is
              // controlHeight and is centered in the row) instead of stuck to the
              // top, with the same top spacing as the rest.
              height: Style.spacing.controlHeight
              verticalAlignment: Text.AlignVCenter
              text: NavState.currentPathError
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              color: Color.urgent
            }

            EmptyState {
              // `root.loaded` (listing confirmed at least once) prepended
              // for the same reason as in BackgroundPanel: on startup, and
              // at any instant when entries is empty but STILL not
              // confirmed, the empty-folder logo must not appear as a
              // transient frame. loaded doesn't go back to false and stays true during the
              // search, so the real "No results"/"Nothing here yet" is
              // still shown as soon as visibleEntries is truly at 0.
              visible: root.loaded && NavState.currentPathError === "" && NavState.visibleEntries.length === 0
              centerOn: listView
              message: NavState.searchQuery
                ? "No results for “" + NavState.searchQuery + "”"
                : (NavState.currentPath === Paths.trashDir ? "Trash is empty" : "Nothing here yet")
            }

            // Visual lasso rectangle -- after the ListView in the
            // file to stay on top when painting (visible even
            // when the lasso grows over already-drawn rows).
            Rectangle {
              visible: SelectionState.marqueeActive
              x: Math.min(SelectionState.marqueeStartX, SelectionState.marqueeCurrentX)
              y: Math.min(SelectionState.marqueeStartY, SelectionState.marqueeCurrentY) - listView.contentY + listView.y
              width: Math.abs(SelectionState.marqueeCurrentX - SelectionState.marqueeStartX)
              height: Math.abs(SelectionState.marqueeCurrentY - SelectionState.marqueeStartY)
              color: Util.alpha(Color.accent, 0.12)
              border.color: Color.accent
              border.width: 1
              z: 5
            }

            // ---------- Preview (Space) ----------
            PreviewPanel {
              anchors.fill: parent
              open: PreviewState.previewOpen
              entryName: PreviewContentState.previewEntry ? PreviewContentState.previewEntry.name : ""
              hasEntry: !!PreviewContentState.previewEntry
              isImageEntry: PreviewContentState.previewEntry ? root.isImage(PreviewContentState.previewEntry) : false
              isVideoEntry: PreviewContentState.previewEntry ? root.isVideo(PreviewContentState.previewEntry) : false
              isTextEntry: !!PreviewContentState.previewEntry && !root.isImage(PreviewContentState.previewEntry) && PreviewContentState.previewIsText
              isPdfEntry: PreviewContentState.previewEntry ? root.isPdf(PreviewContentState.previewEntry) : false
              isAudioEntry: PreviewContentState.previewEntry ? root.isAudio(PreviewContentState.previewEntry) : false
              imageSource: PreviewContentState.previewImage ? Util.fileUrl(PreviewContentState.previewImage) : ""
              videoThumbSource: {
                if (!PreviewContentState.previewEntry || !root.isVideo(PreviewContentState.previewEntry)) return ""
                var p = VideoThumbState.videoThumbReady[Utils.thumbKeyFor(PreviewContentState.previewEntry, NavState.currentPath)] || ""
                return p ? Util.fileUrl(p) : ""
              }
              highlightedText: PreviewContentState.previewHighlighted
              plainText: PreviewContentState.previewText
              pdfImageSource: PreviewContentState.previewPdfImage ? Util.fileUrl(PreviewContentState.previewPdfImage) : ""
              audioInfo: PreviewContentState.previewAudioInfo
              fallbackSizeText: PreviewContentState.previewEntry ? Utils.formatSize(PreviewContentState.previewEntry.size) : ""
            }
}

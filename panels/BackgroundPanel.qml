import QtQuick
import qs.Commons
import qs.Ui
import "../shared"
import "../state"
import "../services"
import "../logic"
import "../Utils.js" as Utils

// Delegate of the "background" panels (all tabs except the active one),
// nineteenth component extracted from Omafiles.qml. Each one has its
// own listing (its own Process), without a selection lasso nor its own context
// menu -- only navigate with double click and drag, the active
// panel (which stays in Omafiles.qml) already has everything else.
// hostPanelsRow is passed as a property separate from hostRoot -- it's the one that computes
// x/width/height of this panel (slotX/slotWidth), and without passing it explicitly
// it isn't visible from this file.
Item {
  id: bgPanel
  property Item hostRoot: null
  property Item hostPanelsRow: null
  property Item hostVideoThumbs: null
  property Item hostDragDropOps: null
  property Item hostFileMeta: null
  property Item hostTabOps: null
  property Item hostSortOps: null
  required property var modelData
  required property int index
  // ALWAYS rendered (not `visible:false`): an invisible ListView doesn't do its
  // layout (contentHeight=0), so on moving to the background positionViewAtIndex
  // didn't hit the mark until a couple of frames later -> the scroll jump. With opacity:0
  // (in the active slot) the ListView STILL has a real layout (ch>0), covered by the
  // activePanel that goes on top in the same slot; on moving to the background it positions
  // instantly, frozen. The background slots go to the usual 0.72 dim.
  visible: true
  opacity: index === TabsState.activeTabIndex ? 0 : 0.72
  x: hostPanelsRow.slotX(index)
  y: 0
  width: hostPanelsRow.slotWidth
  height: hostPanelsRow.height

  // PER-PANEL search (Phase 26, josema): if this tab was left in GLOBAL
  // search mode (2+ chars) when moving to the background, the background panel
  // keeps it open -- bar + results -- until it's closed with the X. The
  // state (searching/searchQuery/searchEntries/searchTruncated) is saved by
  // TabOps.saveActiveTab in the tab object itself (modelData), so each
  // panel has its independent search instead of a shared global one.
  readonly property bool bgSearching: modelData.searching === true
    && (modelData.searchQuery || "").length >= 2
  // RAW results saved by TabOps (for the footer's "of N").
  readonly property var bgSearchEntries: modelData.searchEntries || []
  // Same NAME filter that the active panel applies (NavState.visibleEntries):
  // the global search also brings PATH matches (e.g. folders
  // INSIDE Steam/ like bin/ or logs/, whose name doesn't contain the term). The
  // active panel hides them; without this, the background panel showed MORE results
  // than the active one for the same search. Now the two show the same.
  readonly property var bgVisibleSearchEntries: {
    var q = (modelData.searchQuery || "").toLowerCase()
    return bgSearchEntries.filter(function (e) { return e.name.toLowerCase().indexOf(q) >= 0 })
  }

  // The listing itself lives in DirLister (Phase 1.6, josema) -- same
  // mechanism the active panel uses (NavigationController), but with
  // its own instance: several background tabs can be listing
  // different paths at the same time, so they can't share a single
  // Process. entries/pathError/loaded are no longer bgPanel's own
  // properties -- they're read directly from dirLister throughout the file.
  DirLister {
    id: dirLister
    trashDir: Paths.trashDir
    showHidden: NavState.showHidden
    sortOps: hostSortOps
    // hostRoot.tabEntriesCache is what _goToPath() consults when entering
    // a path that a background panel already had listed -- only the
    // background panels fill it (see NavigationController, which does NOT
    // write here).
    onListed: {
      bgPanel._cachePut(bgPanel.effectivePath, dirLister.entries)
      // Refreshes the painted content ONLY if it really changed (Utils
      // .entriesEqual): so, on moving to the background with the folder unchanged, the
      // model is NOT reassigned -> the ListView doesn't reset the scroll -> no jump. If
      // it changed (new files), it's reassigned and re-positioned.
      if (!Utils.entriesEqual(dirLister.entries, bgPanel._content)) {
        bgPanel._content = dirLister.entries
        bgPanel._restoreScroll()
      }
    }
  }

  // LRU of the per-path entries cache (Phase 10.A): before it grew without
  // limit (one entry per folder visited in ANY background
  // tab, retaining thousands of objects in long sessions with keepLoaded).
  // It's bounded to the 8 most recent paths using the insertion order of the
  // object's keys (delete+reinsert moves to the end = most recent;
  // the ones at the start are evicted = oldest).
  readonly property int _cacheMax: 8
  function _cachePut(path, entries) {
    var c = hostRoot.tabEntriesCache
    if (c[path] !== undefined) delete c[path]
    c[path] = entries
    var keys = Object.keys(c)
    while (keys.length > _cacheMax) { delete c[keys[0]]; keys.shift() }
  }

  // Hovering makes this panel become the active one (the
  // one with the selection lasso, context menu, and that responds to the
  // j/k/F2/Del/etc. keyboard shortcuts) -- without this you could only "activate" a
  // panel by clicking inside, and josema wanted it to be enough to place the
  // cursor over it. HoverHandler instead of MouseArea: it doesn't steal the event from
  // the MouseArea of the rows/buttons below, it only observes.
  HoverHandler {
    // Don't switch the active panel while the user has a name half-
    // written (rename/new folder/new file/editable path) --
    // switchToTab -> _goToPath resets those fields, and with hover-to-activate
    // just crossing the mouse over the divider was enough to lose the text without
    // any click involved. Nor with the context menu open --
    // real bug: the menu opens over the active panel of THAT moment, but
    // if the cursor passed over another background panel on the way to a menu
    // entry (nothing blocked the hover just for having a menu on top), the
    // active tab changed mid-action and "Open in new tab"/Copy/
    // etc. ended up acting on the wrong folder.
    // The real guard now lives in switchToTab() (hasBlockingOverlay), so
    // it covers ALL the dialogs, not just these two.
    onHoveredChanged: if (hovered) hostTabOps.switchToTab(bgPanel.index)
  }

  // Last path for which this specific panel launched a reload --
  // see onModelDataChanged below.
  property string _lastRefreshedPath: ""

  // Path that this panel must list. For the ACTIVE tab it's NavState
  // .currentPath (the tab object is NOT updated until the switch, so
  // using modelData.path left the active-slot panel with the PREVIOUS folder
  // and its EMPTY/stale list -> on moving to the background it populated async and jumped).
  // For the background tabs it's their own saved path. So the active-slot
  // panel (opacity:0, covered by the active panel) PRELOADS the current
  // folder, and on moving to the background it already has the content and the layout -> the
  // repositioning is instant, frozen, without a jump.
  readonly property string effectivePath: index === TabsState.activeTabIndex
    ? NavState.currentPath : (modelData.path || "")
  onEffectivePathChanged: bgPanel.refreshMe()

  // Content that the background ListView paints. It's adopted SYNCHRONOUSLY from the tab
  // object (modelData.entries, which TabOps saved = what the active panel
  // saw) on moving to the background, so the list is NOT empty at that
  // instant (if it were populated async, the scroll would jump from 0 to its place). The
  // dirLister refreshes it behind the scenes without resetting if the content didn't change.
  property var _content: []

  function refreshMe() {
    if (bgPanel.effectivePath === "") return
    bgPanel._lastRefreshedPath = bgPanel.effectivePath
    dirLister.list(bgPanel.effectivePath)
  }

  // On moving to the background (no longer the active tab): restore the scroll.
  // The content is already preloaded (the active slot listed effectivePath
  // live) and with layout (opacity:0 keeps the ListView in the scene graph), so
  // positionViewAtIndex hits the mark instantly. It does NOT re-list here: the path hasn't
  // changed, and re-listing reset the list -> the jump.
  readonly property bool isBackground: index !== TabsState.activeTabIndex
  onIsBackgroundChanged: if (isBackground) {
    // Adopts the content saved in the tab (synchronous, not empty) BEFORE
    // positioning, and refreshes behind the scenes.
    bgPanel._content = bgPanel.modelData.entries || []
    bgPanel._restoreScroll()
    bgPanel.refreshMe()
  }
  // refreshTick is the signal for the NON-active panels to refresh
  // after an action (delete/move/paste/rename), which may affect
  // any panel and not only the active one. It lives in NavState since Phase 14.C
  // -- before it was in OmafilesContent (hostRoot) and this Connections was left
  // listening to a target without that signal (silent regression detected in the
  // 14.E audit: qmllint doesn't see it because hostRoot is an untyped Item).
  Connections {
    target: NavState
    function onRefreshTickChanged() { bgPanel.refreshMe() }
  }
  Component.onCompleted: bgPanel.refreshMe()

  // Scroll shared with the active panel (tab.scrollY = list.contentY). On
  // moving THIS panel to the background we have to reflect in its bgList the scroll it
  // had as the active panel; otherwise, it jumped to the beginning. It's called from
  // dirLister.onListed (when the async re-listing is already set, otherwise that
  // re-listing would reset the contentY right after).
  function _restoreScroll() {
    // By INDEX (positionViewAtIndex), not by pixel: immune to the
    // contentHeight being estimated lazily. Fallback to contentY if there is no
    // saved index (old tabs / root with no scroll).
    var idx = modelData.scrollIndex
    if (idx !== undefined && idx >= 0) {
      // A ListView just made visible hasn't done its layout yet (contentHeight
      // = 0), so positionViewAtIndex would give 0 and the scroll would jump when measured
      // async. forceLayout() completes the SYNCHRONOUS layout -> real geometry ->
      // positionViewAtIndex hits the mark on the first try, without a jump.
      // Anchored on the row's REAL y (same geometry as firstVisibleOffset
      // when saving), not on the contentY that positionViewAtIndex leaves -> no drift.
      bgList.forceLayout()
      bgList.positionViewAtIndex(idx, ListView.Beginning)
      var it = bgList.itemAtIndex(idx)
      if (it) bgList.contentY = it.y + (modelData.scrollOffset || 0)
    } else {
      bgList.contentY = modelData.scrollY || bgList.originY
    }
  }
  // And the other way around: if you scroll this background panel, it's saved in its tab
  // object so that on activating it (list.contentY = tab.scrollY) it stays the same.
  // Only on release (onMovementEnded), not by pixel, so as not to reassign
  // TabsState.tabs constantly.
  function _saveScroll() {
    if (index < 0 || index >= TabsState.tabs.length) return
    var t = TabsState.tabs[index]
    if (!t || t.scrollY === bgList.contentY) return
    var idx = bgList.indexAt(bgList.width / 2, bgList.contentY + 4)
    var it = idx >= 0 ? bgList.itemAtIndex(idx) : null
    var off = it ? (bgList.contentY - it.y) : 0
    var next = TabsState.tabs.slice()
    next[index] = Object.assign({}, t, { "scrollY": bgList.contentY, "scrollIndex": idx, "scrollOffset": off })
    TabsState.tabs = next
  }

  DropArea {
    anchors.fill: parent
    keys: ["text/uri-list"]
    onEntered: function (drag) { if (!drag.hasUrls) drag.accepted = false }
    onDropped: function (drop) { hostDragDropOps.handleFilesDropped(drop, bgPanel.modelData.path) }
  }

  Row {
    id: bgHeaderRow
    anchors.top: parent.top
    width: parent.width
    height: Style.spacing.controlHeight
    spacing: Style.spacing.controlGap

    // Same header as the active panel (back/forward/home/up) --
    // josema asked that the two look the same, not just the active panel
    // with full navigation.
    PanelNavButtons {
      id: bgNavButtons
      canGoBack: (bgPanel.modelData.historyIndex || 0) > 0
      canGoForward: (bgPanel.modelData.historyIndex || 0) < (bgPanel.modelData.history || [bgPanel.modelData.path]).length - 1
      canGoUp: bgPanel.modelData.path !== "/"
      onBackRequested: hostTabOps.navTabBack(bgPanel.index)
      onForwardRequested: hostTabOps.navTabForward(bgPanel.index)
      onUpRequested: {
        var p = bgPanel.modelData.path
        var idx = p.lastIndexOf("/")
        hostTabOps.navigateTabTo(bgPanel.index, idx > 0 ? p.substring(0, idx) : "/")
      }
    }

    // Full breadcrumbs, same as in the active panel -- before only
    // the current folder's name was shown, without the rest of the path.
    BreadcrumbSegments {
      id: bgBreadcrumbRow
      // Same width as the active panel's breadcrumb (pathArea in
      // MainLayout): reserves the gap of the collapsed magnifier (collapsedW =
      // controlHeight) + its separation, even though there is NO magnifier here (the search
      // belongs only to the active panel). So the breadcrumb doesn't change width when
      // the panel becomes active -- no horizontal shift when switching
      // panels (Visual Sprint 3, B-06).
      width: parent.width - bgNavButtons.width - bgSearchPlaceholder.width - 2 * Style.spacing.controlGap
      height: parent.height
      segments: hostRoot.pathSegmentsFor(bgPanel.modelData.path)
      activePath: bgPanel.modelData.path
    }

    // Magnifier slot. At rest it's empty (it only reserves the width of the collapsed
    // magnifier of the active panel, so the header has the same geometry
    // in both states). If THIS background panel has a search open,
    // it grows into a read-only bar: query + X to close it. It's read-
    // only because to EDIT you activate the panel (by hovering), which already
    // brings the full interactive magnifier.
    Item {
      id: bgSearchPlaceholder
      // Same expanded width as the active SearchBar (core/MainLayout): 300 px
      // literal (NOT Style.space, which would scale it and made it wider than the
      // original), clamped by what's left after reserving 120 px of breadcrumb
      // (pathArea.minPathW). At rest, only the width of the collapsed magnifier.
      width: bgPanel.bgSearching
        ? Math.max(Style.spacing.controlHeight, Math.min(300, bgHeaderRow.width - bgNavButtons.width - 120 - 2 * Style.spacing.controlGap))
        : Style.spacing.controlHeight
      height: parent.height

      // READ-ONLY indicator of the search open in this background
      // panel (magnifier + query). It carries no controls of its own: with "activate on
      // hover", any button here would become unreachable (the
      // hover would activate the panel and replace this bar with the interactive
      // magnifier before you could press it). To edit or CLOSE the search
      // you activate the panel (by hovering) and use the usual interactive
      // magnifier (Escape, or click on the magnifier itself).
      // Same geometry and tokens as the active SearchBar expanded (background
      // selectedBackground + border menu.border, magnifier CENTERED in a slot of
      // controlHeight, text starting at iconSlot.right + xs) so the two
      // bars look identical -- before the magnifier was stuck to the text and
      // misaligned relative to the original.
      Rectangle {
        anchors.fill: parent
        visible: bgPanel.bgSearching
        radius: Style.cornerRadius
        color: Color.menu.selectedBackground
        border.width: Style.spacing.hairline
        border.color: Color.menu.border

        Item {
          id: bgSearchIconSlot
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.spacing.controlHeight
          height: Style.spacing.controlHeight

          OpticalGlyph {
            anchors.centerIn: parent
            text: "\u{F0349}" // nf-md-magnify
            fontFamily: Style.font.family
            fontSize: Style.font.icon
            color: Color.menu.selectedText
          }
        }

        Text {
          anchors.left: bgSearchIconSlot.right
          // The active TextField starts the text at xs + its internal leftPadding
          // (Style.spacing.controlPaddingX). A plain Text has no such padding,
          // so it's replicated here so "steam" starts at the SAME x as in
          // the active bar (otherwise, it's more to the left).
          anchors.leftMargin: Style.spacing.xs + Style.spacing.controlPaddingX
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          text: bgPanel.modelData.searchQuery || ""
          elide: Text.ElideRight
          color: Color.menu.selectedText
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }
      }
    }
  }

  PanelSeparator {
    id: bgHeaderSep
    anchors.top: bgHeaderRow.bottom
    // Same gap that separates navRow from listContainer in the active panel
    // (Style.spacing.rowGap, the same mainColumn spacing -- not
    // Style.spacing.sm) -- with sm it was visibly taller than the
    // active panel's line.
    anchors.topMargin: Style.spacing.rowGap
    width: parent.width
    foreground: Color.menu.text
    strength: 0.15
  }

  Text {
    id: bgErrorText
    // Same anchor and margin as the active panel's error notice
    // (ActiveFileList): right under the header separator, at
    // Style.spacing.md -- so the same error appears in the SAME position in the
    // two panels (Visual Sprint 3, C-05). Before it was sm and didn't match
    // the active panel's.
    visible: dirLister.pathError !== "" && !bgPanel.bgSearching
    anchors.top: bgHeaderSep.bottom
    anchors.topMargin: Style.spacing.md
    // Same alignment as the active panel's notice (ActiveFileList): icon
    // column (no leftMargin) and centered in a row's height, to
    // stay at the height of the glyph with the same top spacing as the rest.
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    height: Style.spacing.controlHeight
    verticalAlignment: Text.AlignVCenter
    text: dirLister.pathError
    font.pixelSize: Style.font.subtitle
    font.family: Style.font.family
    color: Color.urgent
  }

  ListView {
    id: bgList
    anchors.top: bgErrorText.visible ? bgErrorText.bottom : bgHeaderSep.bottom
    anchors.topMargin: Style.spacing.md
    anchors.bottom: bgStatusText.top
    anchors.bottomMargin: Style.spacing.rowGap
    anchors.left: parent.left
    anchors.right: parent.right
    clip: true
    // Results of THIS panel's search if it has one open; otherwise, its
    // normal folder listing.
    model: bgPanel.bgSearching ? bgPanel.bgVisibleSearchEntries : bgPanel._content
    boundsBehavior: Flickable.StopAtBounds
    onMovementEnded: bgPanel._saveScroll()

    delegate: CursorSurface {
      id: bgRowSurface
      required property var modelData
      required property int index
      width: bgList.width
      implicitHeight: bgRowContent.implicitHeight + Style.spacing.md * 2
      foreground: Color.menu.text
      accent: Color.accent
      hasCursor: bgRowMouse.containsMouse
      // The hover fill/border is already semi-transparent on its own
      // (Style.hoverFillFor) -- the whole bgPanel goes to opacity:0.72 to
      // mark itself as "not the active panel", and without this that opacity is
      // multiplied ALSO over the hover, ending up doubly weak/
      // faded instead of the same look it has in the active panel.
      // 1/0.72 cancels exactly the parent's opacity only while this
      // specific row has the cursor over it.
      opacity: hasCursor ? 1 / 0.72 : 1

      DropArea {
        visible: modelData.type === "dir"
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: function (drag) { if (!drag.hasUrls) drag.accepted = false }
        onDropped: function (drop) {
          hostDragDropOps.handleFilesDropped(drop, Utils.entryPath(bgPanel.modelData.path, modelData))
        }
      }

      Item {
        id: bgRowContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 0
        anchors.rightMargin: Style.spacing.rowPaddingX
        implicitHeight: bgFileRow.implicitHeight

        readonly property bool isVid: hostRoot.isVideo(modelData)
        readonly property string vidKey: isVid ? Utils.thumbKeyFor(modelData, bgPanel.modelData.path) : ""
        readonly property string vidThumb: vidKey ? (VideoThumbState.videoThumbReady[vidKey] || "") : ""

        // Native thumbnail (images/SVG/PDF) via ThumbnailProvider -- Phase
        // 10.A: before, the WHOLE image file was loaded to paint it
        // at 32 px. Same pattern as FileListRow, with THIS panel's path.
        readonly property string myPath: Utils.entryPath(bgPanel.modelData.path, modelData)
        readonly property bool wantsThumb: hostRoot.isImage(modelData) || hostRoot.isPdf(modelData)
          || modelData.name.toLowerCase().slice(-4) === ".svg"
        property string imgThumb: ""
        onMyPathChanged: {
          imgThumb = wantsThumb ? ThumbnailProvider.request(myPath, 256) : ""
          _requestCount(false)
        }

        Component.onCompleted: {
          if (isVid) hostVideoThumbs.requestVideoThumb(modelData, bgPanel.modelData.path)
          if (wantsThumb) imgThumb = ThumbnailProvider.request(myPath, 256)
          _requestCount(false)
        }

        // Item counter (Phase 23): same as FileListRow, with THIS background
        // panel's path. The FolderCountState cache is global (per path).
        readonly property bool _isDir: modelData.type === "dir"
        function _requestCount(force) {
          if (!_isDir) return
          if (!force && !FolderCountState.needsRequest(myPath)) return
          FolderCountState.markPending(myPath)
          FolderCounter.request(myPath, NavState.showHidden)
        }

        Connections {
          target: ThumbnailProvider
          function onReady(path, thumbPath) {
            if (path === bgRowContent.myPath) bgRowContent.imgThumb = thumbPath
          }
        }

        Connections {
          target: NavState
          function onRefreshTickChanged() { bgRowContent._requestCount(true) }
        }

        FileRowVisual {
          id: bgFileRow
          anchors.fill: parent
          name: modelData.name
          isDir: modelData.type === "dir"
          isBroken: modelData.link === "broken"
          fileIconGlyph: hostRoot.iconFor(modelData)
          // The path is THIS panel's (bgPanel.modelData.path), not
          // hostRoot.currentPath -- that one belongs to the active panel, and it was exactly
          // what made the thumbnail fail here when this panel wasn't
          // the active one.
          thumbSource: bgRowContent.imgThumb ? Util.fileUrl(bgRowContent.imgThumb)
            : (bgRowContent.vidThumb ? Util.fileUrl(bgRowContent.vidThumb) : "")
          metaText: hostFileMeta.metaFor(modelData, bgPanel.modelData.path)
          metaTooltip: hostFileMeta.metaTooltipFor(modelData, bgPanel.modelData.path)
        }
      }

      MouseArea {
        id: bgRowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        drag.target: bgDragProxy
        drag.axis: Drag.XAndYAxis
        onDoubleClicked: {
          if (bgPanel.bgSearching) {
            // Global search result: REVEAL in this panel -- folder ->
            // enter it; file -> go to its folder. navigateTabTo already leaves
            // the tab object without search fields, so the search
            // closes itself on navigating.
            hostTabOps.navigateTabTo(bgPanel.index, modelData.type === "dir" ? modelData.path : modelData.parent)
          } else if (modelData.type === "dir") {
            hostTabOps.navigateTabTo(bgPanel.index, Utils.joinPath(bgPanel.modelData.path, modelData.name))
          } else {
            hostRoot.openWithDefault(Utils.entryPath(bgPanel.modelData.path, modelData))
          }
        }
      }

      Item {
        id: bgDragProxy
        width: 1
        height: 1
        Drag.active: bgRowMouse.drag.active
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
        Drag.proposedAction: Qt.MoveAction
        Drag.mimeData: {
          var data = {}
          data["text/uri-list"] = Util.fileUrl(Utils.joinPath(bgPanel.modelData.path, modelData.name))
          return data
        }
      }
    }
  }

  EmptyState {
    // `dirLister.loaded` (not just entries.length === 0): the empty-folder
    // logo ONLY when the listing is confirmed. A background panel that
    // just became visible (on switching tabs or on hovering)
    // starts with entries=[] and loaded=false until refreshMe() finishes
    // listing asynchronously -- without this guard, EmptyState met
    // entries.length===0 && pathError==="" and flickered a frame even though the
    // folder wasn't empty. loaded is set to true on the first _apply
    // (including that of a truly empty folder) and doesn't go back to false, and
    // list() never empties entries on a refresh, so this never hides
    // a real empty nor flickers on refreshing.
    visible: dirLister.loaded && dirLister.pathError === "" && dirLister.entries.length === 0
    centerOn: bgList
    message: bgPanel.modelData.path === Paths.trashDir ? "Trash is empty" : "Nothing here yet"
  }

  Text {
    id: bgStatusText
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    // Same format as the active panel's footer (statusText in
    // MainLayout): "N items · sort: <criterion>". The sort criterion is
    // global (SortState, via hostSortOps.sortLabel()), so the background
    // panel lists with the SAME order -- omitting it made the two views
    // look different when moving the cursor. The active panel's extras
    // (selection/clipboard/search) are states that only exist there, not
    // in a background panel, so they're not replicated.
    // With a search open, the footer reflects THIS panel's RESULTS
    // (count + trimmed-list notice), same as the active panel's footer
    // when searching; otherwise, the normal folder listing.
    text: bgPanel.bgSearching
      ? (bgPanel.bgVisibleSearchEntries.length + (bgPanel.bgVisibleSearchEntries.length === 1 ? " item" : " items")
         + " of " + bgPanel.bgSearchEntries.length
         + (bgPanel.modelData.searchTruncated ? " · showing first 200" : ""))
      : (dirLister.entries.length + (dirLister.entries.length === 1 ? " item" : " items")
         + " · sort: " + hostSortOps.sortLabel())
    font.pixelSize: Style.font.subtitle
    font.family: Style.font.family
    color: Color.menu.text
    opacity: Style.emphasis.secondary
  }
}

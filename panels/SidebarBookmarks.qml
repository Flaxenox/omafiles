import QtQuick
import qs.Commons
import qs.Ui
import "../shared/Utils.js" as Utils
import "../state"

// Sidebar bookmarks section.
Item {
  id: root

  property var bookmarks: []
  property string currentPath: ""
  property string dropHoverPath: ""
  property Item positionRelativeTo: null

  property var iconForBookmark: null
  property var openContextMenu: null
  property var bookmarkActionsFor: null

  // True while a folder/file drag hovers an empty part of this section:
  // signals "drop here to add it as a bookmark".
  property bool showAddDrop: false

  // Live state of a bookmark reorder drag (plain mouse tracking -- NO Qt
  // Drag/DropArea machinery). The model is NOT touched while dragging
  // (swapping delegates mid-drag would break the tracking); only the insert
  // slot is tracked and highlighted, and the move is committed once on
  // mouse release. bookmarkDragTarget is the row index at whose boundary the
  // bookmark will be inserted, bookmarkDragAfter says "after that row"
  // (bottom line) instead of "before it" (top line).
  property int bookmarkDragFrom: -1
  property int bookmarkDragTarget: -1
  property bool bookmarkDragAfter: false
  property int _pressIndex: -1
  property int _pressY: -1
  property bool _dragging: false
  property bool _suppressClick: false

  signal bookmarkOpened(var bookmark)
  signal dropHoverChanged(string path)
  signal filesDropped(var drop, string destPath)
  signal reorderActiveChanged(bool active)

  width: parent ? parent.width : 0
  implicitHeight: bookmarksColumn.implicitHeight

  // Drops onto empty section space/folder gaps add the dropped folders or
  // files as new bookmarks (drops ON a bookmark row keep the existing
  // "drop files into that folder" behavior -- the row DropAreas sit on top).
  DropArea {
    id: addBookmarkDrop
    anchors.fill: parent
    keys: ["text/uri-list"]
    onEntered: function (drag) {
      if (!drag.hasUrls) { drag.accepted = false; return }
      root.showAddDrop = true
    }
    onExited: root.showAddDrop = false
    onDropped: function (drop) {
      root.showAddDrop = false
      root.addBookmarksFromDrop(drop)
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: root.showAddDrop
    radius: Style.cornerRadius
    color: Util.alpha(Color.accent, 0.10)
    border.color: Util.alpha(Color.accent, 0.45)
    border.width: 1
  }

  // Adds every file:// URL of the drop as a bookmark (no-op for non-local
  // URLs; duplicates are ignored by BookmarksState.addBookmark).
  function addBookmarksFromDrop(drop) {
    var urls = drop.urls || []
    for (var i = 0; i < urls.length; ++i) {
      var path = Utils.urlToPath(urls[i])
      if (!path) continue
      var name = path.substring(path.lastIndexOf("/") + 1)
      BookmarksState.addBookmark(path, name, "dir")
    }
  }

  // Commits the current reorder (no-op when the slot didn't actually move).
  function commitReorder() {
    if (root.bookmarkDragFrom === -1 || root.bookmarkDragTarget === -1) return
    var insertAt = root.bookmarkDragTarget + (root.bookmarkDragAfter ? 1 : 0)
    var from = root.bookmarkDragFrom
    var to = insertAt > from ? insertAt - 1 : insertAt
    if (from !== to) BookmarksState.reorderBookmark(from, to)
    root.bookmarkDragFrom = -1
    root.bookmarkDragTarget = -1
    root.bookmarkDragAfter = false
  }

  // Maps a pointer position (in root coordinates) to the insertion boundary
  // of the nearest bookmark row: { target: rowIndex, after: bool }.
  function slotAt(gy) {
    var count = bookmarksRepeater.count
    if (count === 0) return { target: -1, after: false }
    for (var i = 0; i < count; ++i) {
      var it = bookmarksRepeater.itemAt(i)
      if (!it) continue
      var top = it.mapToItem(root, 0, 0).y
      var mid = top + it.height / 2
      if (gy < mid) return { target: i, after: false }
      if (gy < top + it.height) return { target: i, after: true }
    }
    return { target: count - 1, after: true }
  }

  Column {
    id: bookmarksColumn
    width: root.width
    spacing: Style.spacing.md

    PanelSectionHeader {
      text: "BOOKMARKS"
      foreground: Color.menu.text
      fontFamily: Style.font.family
      fontSize: Style.font.subtitle + 1
    }

    Item {
      width: 1
      height: Style.spacing.xxs
    }

    Repeater {
      id: bookmarksRepeater
      model: root.bookmarks

    CursorSurface {
      // Phase 22: appears with a short fade (120 ms) when the delegate is created
      OpacityAnimator on opacity { from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
      required property int index
      required property var modelData
      readonly property bool isCurrent: root.currentPath === modelData.path
      width: root.width
      implicitHeight: Style.spacing.controlHeight
      foreground: Color.menu.text
      accent: Color.accent
      hasCursor: bookmarkMouse.containsMouse
      current: isCurrent || root.dropHoverPath === modelData.path
      Accessible.role: Accessible.ListItem
      Accessible.name: "Bookmark, " + modelData.label
      Accessible.selected: isCurrent

      DropArea {
        anchors.fill: parent
        enabled: modelData.type !== "file"
        keys: ["text/uri-list"]
        onEntered: function (drag) {
          if (!drag.hasUrls) { drag.accepted = false; return }
          root.dropHoverChanged(modelData.path)
        }
        onExited: if (root.dropHoverPath === modelData.path) root.dropHoverChanged("")
        onDropped: function (drop) {
          root.dropHoverChanged("")
          root.filesDropped(drop, modelData.path)
        }
      }

      // Insertion indicator for a bookmark reorder drag: a 2px accent line
      // at the top of this row when inserting before it, at its bottom when
      // inserting after it.
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        height: 2
        radius: 1
        color: Color.accent
        y: root.bookmarkDragTarget === index && !root.bookmarkDragAfter ? 0 : parent.height - 2
        visible: root.bookmarkDragFrom >= 0
          && ((root.bookmarkDragTarget === index && !root.bookmarkDragAfter)
           || (root.bookmarkDragTarget === index && root.bookmarkDragAfter))
      }

      OpticalGlyph {
        id: bookmarkIcon
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.sm
        width: Style.font.title + 1
        height: Style.font.title + 1
        text: root.iconForBookmark ? root.iconForBookmark(parent.modelData) : ""
        fontFamily: Style.font.family
        fontSize: Style.font.icon + 1
        color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: bookmarkIcon.right
        anchors.leftMargin: Style.spacing.xs
        text: parent.modelData.label
        font.pixelSize: Style.font.title + 1
        font.family: Style.font.family
        font.weight: Font.Medium
        color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
        elide: Text.ElideRight
        width: root.width - Style.spacing.sm * 2 - bookmarkIcon.width - Style.spacing.xs
      }

      MouseArea {
        id: bookmarkMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        // Keep the press on the row (reorder/click) instead of letting the
        // sidebar's Flickable steal it as scroll. Sidebar scrolling still
        // works via wheel or by dragging on the empty areas/scrollbar.
        preventStealing: true
        onPressed: function (mouse) {
          if (mouse.button !== Qt.LeftButton) return
          root._pressIndex = index
          root._pressY = mouse.y
          root._dragging = false
          root._suppressClick = false
        }
        onPositionChanged: function (mouse) {
          if (root._pressIndex < 0) return
          if (!(mouse.buttons & Qt.LeftButton)) return
          if (!root._dragging) {
            // Small vertical drag threshold (12 px) -- below it a press is a
            // click (open), above it the row starts reordering instead.
            if (Math.abs(mouse.y - root._pressY) < 12) return
            root._dragging = true
            root._suppressClick = true
            root.bookmarkDragFrom = root._pressIndex
            root.bookmarkDragTarget = -1
            root.bookmarkDragAfter = false
            // Freeze the hosting Flickable so the reorder drag can't be
            // stolen as (or fight with) a scroll gesture. Released in
            // onReleased / onCanceled below.
            root.reorderActiveChanged(true)
          }
          var slot = root.slotAt(root.mapFromItem(bookmarkMouse, mouse.x, mouse.y).y)
          if (slot.target !== root.bookmarkDragTarget || slot.after !== root.bookmarkDragAfter) {
            root.bookmarkDragTarget = slot.target
            root.bookmarkDragAfter = slot.after
          }
        }
        onReleased: function (mouse) {
          if (root._dragging) {
            // Clear drag state BEFORE commitReorder: it swaps the model and
            // destroys this very delegate, so touching it afterwards (or the
            // references in the rest of this handler) may not resolve.
            root._dragging = false
            root.reorderActiveChanged(false)
            root._pressIndex = -1
            root._pressY = -1
            root.commitReorder()
            return
          }
          root._pressIndex = -1
          root._pressY = -1
        }
        onCanceled: {
          // Grab lost (e.g. release outside the window): unwind a reorder.
          if (root._dragging) {
            root._dragging = false
            root._suppressClick = false
            root.bookmarkDragFrom = -1
            root.bookmarkDragTarget = -1
            root.bookmarkDragAfter = false
            root.reorderActiveChanged(false)
          }
          root._pressIndex = -1
          root._pressY = -1
        }
        onClicked: function (mouse) {
          if (root._suppressClick) { root._suppressClick = false; return }
          if (mouse.button === Qt.RightButton) {
            var pos = mapToItem(root.positionRelativeTo, mouse.x, mouse.y)
            if (root.openContextMenu && root.bookmarkActionsFor) {
              root.openContextMenu(pos.x, pos.y, root.bookmarkActionsFor(modelData))
            }
            return
          }
          root.bookmarkOpened(modelData)
        }
      }
    }
  }
  }
}
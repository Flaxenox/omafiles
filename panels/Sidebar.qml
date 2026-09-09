import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../shared/Utils.js" as Utils

// Sidebar (bookmarks/drives/network).
Item {
  id: root

  property var bookmarks: []
  property var mounts: []
  property var networkMounts: []
  property string currentPath: ""
  property string dropHoverPath: ""
  // Device path whose ejection is in progress -> eject button spinner
  property string ejectingDevice: ""

  property Item positionRelativeTo: null

  property var iconForBookmark: null
  property var iconForMount: null
  property var iconForNetworkMount: null
  property var openContextMenu: null
  property var bookmarkActionsFor: null
  property var mountActionsFor: null
  property var networkMountActionsFor: null

  signal bookmarkOpened(var bookmark)
  signal mountActivated(var mount)
  signal mountEjectRequested(var mount)
  signal networkMountOpened(var mount)
  signal connectRequested()
  signal filesDropped(var drop, string destPath)
  signal dropHoverChanged(string path)

  Flickable {
    id: sidebarFlickable
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: sidebarColumn.implicitHeight
    interactive: sidebarColumn.implicitHeight > height

    ScrollBar.vertical: ScrollBar {
      id: sideScroll
      policy: sidebarColumn.implicitHeight > sidebarFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
      width: Style.space(8)
      anchors.left: parent.left

      // Hidden at rest (invisible + non-interactive); fades in while the
      // sidebar is scrolled (wheel/drag) and fades out shortly after the
      // movement stops (or while being dragged, stays until release).
      opacity: sideScroll.showBar ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
      property bool showBar: false
      Timer {
        id: sideScrollHide
        interval: 700
        onTriggered: sideScroll.showBar = false
      }
      Connections {
        target: sidebarFlickable
        function onMovingChanged() {
          if (sidebarFlickable.moving) { sideScroll.showBar = true; sideScrollHide.restart() }
        }
      }
      onPressedChanged: {
        if (sideScroll.pressed) { sideScroll.showBar = true; sideScrollHide.restart() }
        else sideScrollHide.restart()
      }

      contentItem: Rectangle {
        implicitWidth: parent.width
        implicitHeight: 26
        radius: parent.width / 2
        color: Util.alpha(Color.foreground, 0.28)
      }
    }

    Column {
      id: sidebarColumn
      width: parent.width
      spacing: 0 // Components already manage their own spacing

      SidebarBookmarks {
        bookmarks: root.bookmarks
        currentPath: root.currentPath
        dropHoverPath: root.dropHoverPath
        positionRelativeTo: root.positionRelativeTo
        iconForBookmark: root.iconForBookmark
        openContextMenu: root.openContextMenu
        bookmarkActionsFor: root.bookmarkActionsFor

        onBookmarkOpened: function(b) { root.bookmarkOpened(b) }
        onDropHoverChanged: function(p) { root.dropHoverChanged(p) }
        onFilesDropped: function(d, p) { root.filesDropped(d, p) }
        onReorderActiveChanged: function (active) {
          // Reorder drag must not double as a sidebar scroll gesture.
          sidebarFlickable.interactive = !active
        }
      }

      SidebarMounts {
        mounts: root.mounts
        currentPath: root.currentPath
        dropHoverPath: root.dropHoverPath
        ejectingDevice: root.ejectingDevice
        positionRelativeTo: root.positionRelativeTo
        iconForMount: root.iconForMount
        openContextMenu: root.openContextMenu
        mountActionsFor: root.mountActionsFor

        onMountActivated: function(m) { root.mountActivated(m) }
        onMountEjectRequested: function(m) { root.mountEjectRequested(m) }
        onDropHoverChanged: function(p) { root.dropHoverChanged(p) }
        onFilesDropped: function(d, p) { root.filesDropped(d, p) }
      }

      SidebarNetwork {
        networkMounts: root.networkMounts
        currentPath: root.currentPath
        positionRelativeTo: root.positionRelativeTo
        iconForNetworkMount: root.iconForNetworkMount
        openContextMenu: root.openContextMenu
        networkMountActionsFor: root.networkMountActionsFor

        onNetworkMountOpened: function(m) { root.networkMountOpened(m) }
        onConnectRequested: function() { root.connectRequested() }
      }
    }
  }
}

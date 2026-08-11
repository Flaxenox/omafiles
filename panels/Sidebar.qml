import QtQuick
import qs.Commons
import qs.Ui

// Sidebar (bookmarks/recents/drives/network). Tenth component
// extracted from Omafiles.qml, and the first that is not a modal dialog --
// it's always visible, so no property needs to be forced by
// hand to test it live, just restart the shell and look.
//
// More interface surface than the previous ones: the icon/context-menu-action
// builders (iconForBookmark, bookmarkActions,
// etc.) are passed as function references -- QML allows treating a
// root-level function as a normal value -- instead of trying to
// replicate their logic here (unlike ChmodPanel.qml, where it WAS
// worth reproducing a small calculation locally; here there are
// too many functions and some read Paths.homeDir/trashDir).
Item {
  id: root

  property var bookmarks: []
  property var recentFiles: []
  property var mounts: []
  property var networkMounts: []
  property string currentPath: ""
  property string dropHoverPath: ""
  // Device path whose ejection is in progress -> eject button spinner
  // (Phase 21). Fed by MainLayout from MountsState.ejectingDevice.
  property string ejectingDevice: ""

  // Item against which mapToItem() computes the context menu's
  // position -- in Omafiles.qml it's "card" (the panel's root BorderSurface),
  // which a separate component cannot see on its own.
  property Item positionRelativeTo: null

  property var iconForBookmark: null
  property var iconFor: null
  property var iconForMount: null
  property var iconForNetworkMount: null
  property var openContextMenu: null
  property var bookmarkActionsFor: null
  property var mountActionsFor: null
  property var networkMountActionsFor: null

  signal bookmarkOpened(var bookmark)
  signal recentOpened(var item)
  signal recentLaunched(var item)
  signal recentRemoveRequested(string path)
  signal recentClearRequested()
  signal mountActivated(var mount)
  signal mountEjectRequested(var mount)
  signal networkMountOpened(var mount)
  signal connectRequested()
  signal filesDropped(var drop, string destPath)
  signal dropHoverChanged(string path)

  Column {
    id: sidebar
    // Follows the component's real width (set by MainLayout), not a fixed 160:
    // so the separators/headers/rows (all width: sidebar.width) occupy
    // the full width. Before, on widening the Sidebar, they fell short.
    width: parent.width
    height: parent.height
    spacing: Style.spacing.md

    PanelSectionHeader {
      text: "BOOKMARKS"
      foreground: Color.menu.text
      fontFamily: Style.font.family
      fontSize: Style.font.subtitle
    }

    Item {
      width: 1
      height: Style.spacing.xxs
    }

    Repeater {
      model: root.bookmarks

      CursorSurface {
        // Phase 22: appears with a short fade (120 ms) when the delegate is created
        // (plugging in a USB, mounting an ISO, adding a bookmark...). No
        // bounces; the opacity doesn't block the click.
        OpacityAnimator on opacity { from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
        required property var modelData
        readonly property bool isCurrent: root.currentPath === modelData.path
        width: sidebar.width
        implicitHeight: Style.spacing.controlHeight
        foreground: Color.menu.text
        accent: Color.accent
        hasCursor: bookmarkMouse.containsMouse
        current: isCurrent || root.dropHoverPath === modelData.path
        Accessible.role: Accessible.ListItem
        Accessible.name: "Bookmark, " + modelData.label
        Accessible.selected: isCurrent

        DropArea {
          // Disabled for file bookmarks -- dropping
          // something "onto a file" has no real destination (unlike
          // a folder), destDir would have to be a
          // directory.
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

        OpticalGlyph {
          id: bookmarkIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          width: Style.font.title
          height: Style.font.title
          text: root.iconForBookmark(parent.modelData)
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: bookmarkIcon.right
          anchors.leftMargin: Style.spacing.xs
          text: parent.modelData.label
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          font.weight: Font.Medium
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
          elide: Text.ElideRight
          width: sidebar.width - Style.spacing.sm * 2 - bookmarkIcon.width - Style.spacing.xs
        }

        MouseArea {
          id: bookmarkMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              var pos = mapToItem(root.positionRelativeTo, mouse.x, mouse.y)
              root.openContextMenu(pos.x, pos.y, root.bookmarkActionsFor(modelData))
              return
            }
            root.bookmarkOpened(modelData)
          }
        }
      }
    }

    Item {
      visible: root.recentFiles.length > 0
      width: 1
      height: Style.spacing.sm
    }

    PanelSeparator {
      visible: root.recentFiles.length > 0
      foreground: Color.menu.text
      strength: 0.15
    }

    Item {
      visible: root.recentFiles.length > 0
      width: 1
      height: Style.spacing.xs
    }

    PanelSectionHeader {
      visible: root.recentFiles.length > 0
      text: "RECENT"
      foreground: Color.menu.text
      fontFamily: Style.font.family
      fontSize: Style.font.subtitle
    }

    Item {
      visible: root.recentFiles.length > 0
      width: 1
      height: Style.spacing.xxs
    }

    Repeater {
      model: root.recentFiles

      CursorSurface {
        // Phase 22: appears with a short fade (120 ms) when the delegate is created
        // (plugging in a USB, mounting an ISO, adding a bookmark...). No
        // bounces; the opacity doesn't block the click.
        OpacityAnimator on opacity { from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
        required property var modelData
        width: sidebar.width
        implicitHeight: Style.spacing.controlHeight
        foreground: Color.menu.text
        accent: Color.accent
        hasCursor: recentMouse.containsMouse
        Accessible.role: Accessible.ListItem
        Accessible.name: "Recent file, " + modelData.name

        OpticalGlyph {
          id: recentIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          width: Style.font.title
          height: Style.font.title
          text: root.iconFor({ type: "file", name: parent.modelData.name })
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: Color.menu.text
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: recentIcon.right
          anchors.leftMargin: Style.spacing.xs
          text: parent.modelData.name
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          font.weight: Font.Medium
          color: Color.menu.text
          elide: Text.ElideRight
          width: sidebar.width - Style.spacing.sm * 2 - recentIcon.width - Style.spacing.xs
        }

        MouseArea {
          id: recentMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              var pos = mapToItem(root.positionRelativeTo, mouse.x, mouse.y)
              root.openContextMenu(pos.x, pos.y, [
                { label: "Open", action: function () { root.recentOpened(modelData) } },
                { label: "Remove from recent", destructive: true, action: function () { root.recentRemoveRequested(modelData.path) } },
                { label: "Clear recent", destructive: true, action: function () { root.recentClearRequested() } }
              ])
              return
            }
            root.recentOpened(modelData)
          }
          onDoubleClicked: root.recentLaunched(modelData)
        }
      }
    }

    Item {
      visible: root.mounts.length > 0
      width: 1
      height: Style.spacing.sm
    }

    PanelSeparator {
      visible: root.mounts.length > 0
      foreground: Color.menu.text
      strength: 0.15
    }

    Item {
      visible: root.mounts.length > 0
      width: 1
      height: Style.spacing.xs
    }

    PanelSectionHeader {
      visible: root.mounts.length > 0
      text: "DEVICES"
      foreground: Color.menu.text
      fontFamily: Style.font.family
      fontSize: Style.font.subtitle
    }

    Item {
      visible: root.mounts.length > 0
      width: 1
      height: Style.spacing.xxs
    }

    Repeater {
      model: root.mounts

      CursorSurface {
        // Phase 22: appears with a short fade (120 ms) when the delegate is created
        // (plugging in a USB, mounting an ISO, adding a bookmark...). No
        // bounces; the opacity doesn't block the click.
        OpacityAnimator on opacity { from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
        required property var modelData
        readonly property bool isCurrent: root.currentPath === modelData.path
        width: sidebar.width
        implicitHeight: Style.spacing.controlHeight
        foreground: Color.menu.text
        accent: Color.accent
        hasCursor: mountMouse.containsMouse
        current: isCurrent || root.dropHoverPath === modelData.path
        Accessible.role: Accessible.ListItem
        Accessible.name: modelData.label + (modelData.mounted ? "" : ", not mounted")
        Accessible.selected: isCurrent

        DropArea {
          // Only already-mounted drives -- dropping on an unmounted one has
          // no real destination yet.
          anchors.fill: parent
          enabled: modelData.mounted
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

        OpticalGlyph {
          id: mountIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          width: Style.font.title
          height: Style.font.title
          opacity: parent.modelData.mounted ? 1.0 : 0.5
          text: root.iconForMount(parent.modelData)
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: mountIcon.right
          anchors.leftMargin: Style.spacing.xs
          opacity: parent.modelData.mounted ? 1.0 : 0.5
          text: parent.modelData.label
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          font.weight: Font.Medium
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
          elide: Text.ElideRight
          // Reserves room for the eject button when the device is
          // ejectable, so the name doesn't jump when it appears on hover.
          width: sidebar.width - Style.spacing.sm * 2 - mountIcon.width - Style.spacing.xs
            - (parent.modelData.removable ? Style.font.title + Style.spacing.sm : 0)
        }

        PanelToolTip {
          visible: mountMouse.containsMouse && !parent.modelData.mounted
          text: "Not mounted -- click to mount"
        }

        MouseArea {
          id: mountMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              var pos = mapToItem(root.positionRelativeTo, mouse.x, mouse.y)
              root.openContextMenu(pos.x, pos.y, root.mountActionsFor(modelData))
              return
            }
            root.mountActivated(modelData)
          }
        }

        // Eject button (Phase 21): only on ejectable devices.
        // Hidden at rest; appears with a smooth fade (120 ms) + slight
        // 3 px slide on hovering the row (Omarchy Quattro aesthetic,
        // no bounces). While the ejection is in progress it shows a
        // spinner and accepts no more clicks; the row disappears on its own when
        // UDisksWatcher refreshes the listing (no timers). Reuses
        // mountOps.ejectMount via the mountEjectRequested signal.
        Item {
          id: ejectSlot
          readonly property var mount: parent.modelData
          readonly property bool isCurrent: parent.isCurrent
          readonly property bool ejecting: mount.device === root.ejectingDevice
          readonly property bool hovered: mountMouse.containsMouse || ejectMouse.containsMouse
          visible: mount.removable
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.title
          height: Style.font.title

          OpticalGlyph {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: ejectSlot.hovered ? 0 : 3
            width: Style.font.title
            height: Style.font.title
            visible: !ejectSlot.ejecting
            text: "\u{F01EA}" // nf-md-eject (verified in the font's cmap)
            fontFamily: Style.font.family
            fontSize: Style.font.icon
            color: ejectSlot.isCurrent ? Color.menu.selectedText : Color.menu.text
            // Always visible but discreet at rest (Omarchy Quattro), more
            // bright on hovering the row -- fully hidden (0.0)
            // was impossible to discover.
            opacity: ejectSlot.hovered ? 0.95 : Style.emphasis.muted
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on anchors.rightMargin { NumberAnimation { duration: 120 } }
          }

          // Spinner: dot in orbit (no glyph or timers), only while ejecting.
          Item {
            id: ejectSpinner
            anchors.centerIn: parent
            width: Style.font.icon
            height: Style.font.icon
            visible: ejectSlot.ejecting
            Rectangle {
              width: 3; height: 3; radius: 1.5
              color: Color.accent
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
            }
            RotationAnimator on rotation {
              running: ejectSpinner.visible
              loops: Animation.Infinite
              from: 0; to: 360; duration: 800
            }
          }

          MouseArea {
            id: ejectMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !ejectSlot.ejecting
            onClicked: root.mountEjectRequested(ejectSlot.mount)
          }
        }
      }
    }

    Item {
      width: 1
      height: Style.spacing.sm
    }

    PanelSeparator {
      foreground: Color.menu.text
      strength: 0.15
    }

    Item {
      width: 1
      height: Style.spacing.xs
    }

    // Unlike DEVICES/bookmarks, this header and the
    // "Connect to server..." row are always shown, with active mounts or
    // without them -- if they depended on root.networkMounts.length > 0
    // no one could discover the feature the first time, when by
    // definition there is not yet any active network connection.
    PanelSectionHeader {
      text: "NETWORK"
      foreground: Color.menu.text
      fontFamily: Style.font.family
      fontSize: Style.font.subtitle
    }

    Item {
      width: 1
      height: Style.spacing.xxs
    }

    Repeater {
      model: root.networkMounts

      CursorSurface {
        // Phase 22: appears with a short fade (120 ms) when the delegate is created
        // (plugging in a USB, mounting an ISO, adding a bookmark...). No
        // bounces; the opacity doesn't block the click.
        OpacityAnimator on opacity { from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
        required property var modelData
        readonly property bool isCurrent: root.currentPath === modelData.path
        width: sidebar.width
        implicitHeight: Style.spacing.controlHeight
        foreground: Color.menu.text
        accent: Color.accent
        hasCursor: networkMountMouse.containsMouse
        current: isCurrent
        Accessible.role: Accessible.ListItem
        Accessible.name: "Network location, " + modelData.label
        Accessible.selected: isCurrent

        OpticalGlyph {
          id: networkMountIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          width: Style.font.title
          height: Style.font.title
          text: root.iconForNetworkMount(parent.modelData)
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: networkMountIcon.right
          anchors.leftMargin: Style.spacing.xs
          text: parent.modelData.label
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          font.weight: Font.Medium
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
          elide: Text.ElideRight
          width: sidebar.width - Style.spacing.sm * 2 - networkMountIcon.width - Style.spacing.xs
        }

        MouseArea {
          id: networkMountMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              var pos = mapToItem(root.positionRelativeTo, mouse.x, mouse.y)
              root.openContextMenu(pos.x, pos.y, root.networkMountActionsFor(modelData))
              return
            }
            root.networkMountOpened(modelData)
          }
        }
      }
    }

    CursorSurface {
      width: sidebar.width
      implicitHeight: Style.spacing.controlHeight
      foreground: Color.menu.text
      accent: Color.accent
      hasCursor: connectServerMouse.containsMouse
      Accessible.role: Accessible.Button
      Accessible.name: "Connect to server"

      OpticalGlyph {
        id: connectServerIcon
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.sm
        width: Style.font.title
        height: Style.font.title
        text: "\u{F0490}"
        fontFamily: Style.font.family
        fontSize: Style.font.icon
        color: Color.menu.text
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: connectServerIcon.right
        anchors.leftMargin: Style.spacing.xs
        text: "Connect…"
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.weight: Font.Medium
        color: Color.menu.text
        elide: Text.ElideRight
        width: sidebar.width - Style.spacing.sm * 2 - connectServerIcon.width - Style.spacing.xs
      }

      MouseArea {
        id: connectServerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.connectRequested()
      }
    }
  }
}

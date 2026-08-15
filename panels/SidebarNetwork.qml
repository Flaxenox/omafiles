import QtQuick
import qs.Commons
import qs.Ui
import "../shared/Utils.js" as Utils

// Sidebar network mounts section.
Column {
  id: root

  property var networkMounts: []
  property string currentPath: ""
  property Item positionRelativeTo: null

  property var iconForNetworkMount: null
  property var openContextMenu: null
  property var networkMountActionsFor: null

  signal networkMountOpened(var mount)
  signal connectRequested()

  width: parent ? parent.width : 0
  spacing: Style.spacing.md

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
      OpacityAnimator on opacity { from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
      required property var modelData
      readonly property bool isCurrent: root.currentPath === modelData.path
      width: root.width
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
        text: root.iconForNetworkMount ? root.iconForNetworkMount(parent.modelData) : ""
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
        width: root.width - Style.spacing.sm * 2 - networkMountIcon.width - Style.spacing.xs
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
            if (root.openContextMenu && root.networkMountActionsFor) {
              root.openContextMenu(pos.x, pos.y, root.networkMountActionsFor(modelData))
            }
            return
          }
          root.networkMountOpened(modelData)
        }
      }
    }
  }

  CursorSurface {
    width: root.width
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
      width: root.width - Style.spacing.sm * 2 - connectServerIcon.width - Style.spacing.xs
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

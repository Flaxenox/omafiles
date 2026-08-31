import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Context menu (right-click). Eighth component extracted from
// core. The actions already arrive as a list of objects
// { label, action, enabled, destructive } built by
// root.itemActions()/emptyAreaActions()/etc. -- each `action` is already a
// function ready to call, so this component does not need
// per-action signals, only to execute it and request closing.
Item {
  id: root

  property bool open: false
  property real menuX: 0
  property real menuY: 0
  property var actions: []

  signal closeRequested()

  // Measures the labels WITHOUT instantiating any visible Text -- avoids the
  // problem of depending on real children to compute the width
  // (circular: the width of each row would depend on the menu width, which
  // in turn should depend on the width of each row). Same font that
  // each row's real Text uses (see below).
  FontMetrics {
    id: menuFontMetrics
    font.pixelSize: Style.font.title
    font.family: Style.font.family
    font.weight: Font.Medium
  }

  readonly property real maxLabelWidth: {
    var m = 0
    for (var i = 0; i < root.actions.length; i++) {
      m = Math.max(m, menuFontMetrics.advanceWidth(root.actions[i].label))
    }
    return m
  }

  MouseArea {
    anchors.fill: parent
    visible: root.open
    z: 15
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: root.closeRequested()
    onWheel: function(wheel) { wheel.accepted = true }
  }

  BorderSurface {
    id: contextMenu
    visible: root.open
    x: root.menuX
    y: root.menuY
    width: Math.max(200, root.maxLabelWidth + Style.spacing.sm * 2 + contentLeftInset + contentRightInset)
    height: Math.min(contextMenuColumn.implicitHeight + contentTopInset + contentBottomInset, root.height - root.menuY - Style.spacing.lg)
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.popupPadding
    z: 20

      Flickable {
        id: menuFlickable
        anchors.fill: parent
        anchors.topMargin: contextMenu.contentTopInset
        anchors.rightMargin: contextMenu.contentRightInset
        anchors.bottomMargin: contextMenu.contentBottomInset
        anchors.leftMargin: contextMenu.contentLeftInset
        clip: true
        contentHeight: contextMenuColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: contextMenuColumn
          width: parent.width
          spacing: Style.spacing.sm

          Repeater {
            model: root.actions

            CursorSurface {
              required property var modelData
              readonly property bool actionEnabled: modelData.enabled !== false
              width: contextMenuColumn.width
              implicitHeight: Style.spacing.controlHeight
              foreground: Color.menu.text
              accent: Color.accent
              hasCursor: itemMouse.containsMouse && actionEnabled

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                text: parent.modelData.label
                font.pixelSize: Style.font.title
                font.family: Style.font.family
                font.weight: Font.Medium
                color: parent.modelData.destructive ? Color.urgent : (parent.actionEnabled ? Color.menu.text : Qt.darker(Color.menu.text, 1.8))
              }

              MouseArea {
                id: itemMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: parent.actionEnabled
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.closeRequested()
                  parent.modelData.action()
                }
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.open && contextMenuColumn.implicitHeight > menuFlickable.height
        anchors.top: menuFlickable.top
        anchors.bottom: menuFlickable.bottom
        anchors.right: menuFlickable.right
        width: Style.space(8)
        color: "transparent"

        Rectangle {
          readonly property real trackLen: parent.height
          readonly property real handleLen: Math.max(26, trackLen * (menuFlickable.height / contextMenuColumn.implicitHeight))
          y: Math.max(0, Math.min(trackLen - handleLen, (trackLen - handleLen) * (menuFlickable.contentY / Math.max(1, contextMenuColumn.implicitHeight - menuFlickable.height))))
          width: parent.width
          height: handleLen
          radius: width / 2
          color: Util.alpha(Color.foreground, 0.28)
        }
      }
    }
  }

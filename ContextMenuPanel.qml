import QtQuick
import qs.Commons
import qs.Ui

// Menú contextual (clic derecho). Octavo componente extraído de
// Omafiles.qml. Las acciones ya llegan como una lista de objetos
// { label, action, enabled, destructive } construida por
// root.itemActions()/emptyAreaActions()/etc. -- cada `action` es ya una
// función lista para llamar, así que este componente no necesita
// señales por acción, solo ejecutarla y pedir cerrarse.
Item {
  id: root

  property bool open: false
  property real menuX: 0
  property real menuY: 0
  property var actions: []

  signal closeRequested()

  MouseArea {
    anchors.fill: parent
    visible: root.open
    z: 15
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: root.closeRequested()
  }

  BorderSurface {
    id: contextMenu
    visible: root.open
    x: root.menuX
    y: root.menuY
    width: 200
    height: contextMenuColumn.implicitHeight + contentTopInset + contentBottomInset
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.sm
    z: 20

    Column {
      id: contextMenuColumn
      anchors.fill: parent
      anchors.topMargin: contextMenu.contentTopInset
      anchors.rightMargin: contextMenu.contentRightInset
      anchors.bottomMargin: contextMenu.contentBottomInset
      anchors.leftMargin: contextMenu.contentLeftInset
      spacing: Style.spacing.xs

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
}

import QtQuick

// Adaptador MÍNIMO de qs.Ui/ConfirmDialog.qml (Fase 4, josema).
Item {
  id: root
  property bool opened: false
  property string message: ""
  property string confirmText: "OK"
  property string cancelText: "Cancel"
  property color background: "#1a1b26"
  property color foreground: "#c0caf5"
  signal canceled()
  signal confirmed()

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: "black"
    opacity: 0.4
    MouseArea { anchors.fill: parent; onClicked: root.canceled() }
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 80, 420)
    height: col.implicitHeight + 32
    radius: 8
    color: root.background
    border.color: "#414868"
    border.width: 1

    Column {
      id: col
      anchors.fill: parent
      anchors.margins: 16
      spacing: 16

      Text {
        width: parent.width
        text: root.message
        color: root.foreground
        wrapMode: Text.WordWrap
      }

      Row {
        anchors.right: parent.right
        spacing: 8

        Button { text: root.cancelText; onClicked: root.canceled() }
        Button { text: root.confirmText; bordered: true; onClicked: root.confirmed() }
      }
    }
  }
}

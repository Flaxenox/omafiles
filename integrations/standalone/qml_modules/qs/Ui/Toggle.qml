import QtQuick

// Adaptador MÍNIMO de qs.Ui/Toggle.qml (Fase 4, josema).
Item {
  id: root
  property string label: ""
  property string description: ""
  property bool checked: false
  property color foreground: "#c0caf5"
  property color accent: "#7aa2f7"
  signal clicked()

  implicitHeight: col.implicitHeight

  Row {
    width: parent.width
    spacing: 8

    Rectangle {
      width: 32
      height: 18
      radius: 9
      anchors.verticalCenter: parent.verticalCenter
      color: root.checked ? root.accent : "#414868"

      Rectangle {
        width: 14
        height: 14
        radius: 7
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 2 : 2
        color: "white"
      }
    }

    Column {
      id: col
      width: parent.width - 40

      Text { text: root.label; color: root.foreground }
      Text {
        visible: root.description.length > 0
        text: root.description
        color: root.foreground
        opacity: 0.6
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.clicked()
  }
}

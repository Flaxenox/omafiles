import QtQuick

// Adaptador MÍNIMO de qs.Ui/PanelToolTip.qml (Fase 4, josema).
Rectangle {
  id: root
  property string text: ""
  visible: false
  color: "#1a1b26"
  border.color: "#414868"
  border.width: 1
  radius: 4
  implicitWidth: label.implicitWidth + 12
  implicitHeight: label.implicitHeight + 8
  y: -implicitHeight - 4
  z: 50

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: "#c0caf5"
  }
}

import QtQuick

// Adaptador MÍNIMO de qs.Ui/Button.qml (Fase 4, josema). No redeclara
// "enabled" -- Item ya lo trae con el mismo significado, redeclararlo
// generaba un warning real de QML ("overrides a member of the base
// object").
Rectangle {
  id: root
  property string text: ""
  property bool bordered: false
  property bool leftAlign: false
  property color foreground: "#c0caf5"
  signal clicked()

  implicitWidth: label.implicitWidth + 24
  implicitHeight: 28
  radius: 4
  color: mouseArea.pressed ? Qt.darker("#2a2b3d", 1.2) : (mouseArea.containsMouse ? "#2a2b3d" : "#20212f")
  border.color: bordered ? "#414868" : "transparent"
  border.width: bordered ? 1 : 0
  opacity: root.enabled ? 1 : 0.5

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.leftAlign ? 10 : 0
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    text: root.text
    color: root.foreground
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}

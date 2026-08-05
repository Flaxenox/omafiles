import QtQuick

// Adaptador MÍNIMO de qs.Ui/TextField.qml (Fase 4, josema). FocusScope
// para que forceActiveFocus()/selectAll() llamados sobre la instancia
// (patrón usado en todo omafiles) lleguen al TextInput real de dentro.
FocusScope {
  id: root
  property alias text: input.text
  property string placeholderText: ""
  property real verticalPadding: 0
  implicitHeight: input.implicitHeight + verticalPadding * 2

  function selectAll() { input.selectAll() }

  Rectangle {
    anchors.fill: parent
    color: "#20212f"
    border.color: input.activeFocus ? "#7aa2f7" : "#414868"
    border.width: 1
    radius: 4
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    visible: input.text.length === 0
    text: root.placeholderText
    color: "#6b7089"
  }

  TextInput {
    id: input
    anchors.fill: parent
    anchors.leftMargin: 8
    anchors.rightMargin: 8
    verticalAlignment: TextInput.AlignVCenter
    color: "#c0caf5"
    focus: true
    selectByMouse: true
  }
}

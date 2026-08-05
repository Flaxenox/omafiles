import QtQuick

// Adaptador MÍNIMO de qs.Ui/PanelSeparator.qml (Fase 4, josema).
Rectangle {
  property color foreground: "#c0caf5"
  property real strength: 0.15
  width: parent ? parent.width : implicitWidth
  implicitHeight: 1
  color: foreground
  opacity: strength
}

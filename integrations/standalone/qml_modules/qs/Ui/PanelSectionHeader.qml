import QtQuick

// Adaptador MÍNIMO de qs.Ui/PanelSectionHeader.qml (Fase 4, josema).
Text {
  property color foreground: "#8a91b0"
  property string fontFamily: "sans-serif"
  property real fontSize: 11
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true
  color: foreground
  opacity: 0.7
}

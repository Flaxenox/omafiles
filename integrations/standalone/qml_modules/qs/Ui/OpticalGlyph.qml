import QtQuick

// Adaptador MÍNIMO de qs.Ui/OpticalGlyph.qml (Fase 4, josema) -- glifo
// de icono (Nerd Font) centrado. El real ajusta el "peso óptico" fino
// del glifo; este solo centra el texto.
Text {
  property string fontFamily: "sans-serif"
  property real fontSize: 16
  font.family: fontFamily
  font.pixelSize: fontSize
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
}

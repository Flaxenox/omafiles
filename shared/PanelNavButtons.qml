import QtQuick
import qs.Commons
import qs.Ui

// Botones de navegación (atrás/adelante/subir) -- decimocuarto componente
// extraído de Omafiles.qml, compartido entre panel activo y de fondo.
// Antes cada botón existía dos veces (uno en navRow, otro en bgHeaderRow)
// con el mismo glyph/tamaño, y solo cambiaba a qué función de root
// llamaban y de qué propiedad sacaban el "deshabilitado" (gris). Aquí eso
// son tres señales y tres booleanos que ya resuelve quien llama.
Row {
  id: root

  property bool canGoBack: false
  property bool canGoForward: false
  property bool canGoUp: false
  signal backRequested()
  signal forwardRequested()
  signal upRequested()

  spacing: Style.spacing.controlGap

  Button {
    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight
    anchors.verticalCenter: parent.verticalCenter
    foreground: root.canGoBack ? Color.menu.text : Qt.darker(Color.menu.text, 1.6)
    onClicked: root.backRequested()
    Accessible.role: Accessible.Button
    Accessible.name: "Back"

    OpticalGlyph {
      anchors.centerIn: parent
      // md-arrow_left, verificado contra el cmap real de la fuente.
      text: "\u{F004D}"
      fontFamily: Style.font.family
      fontSize: Style.font.icon
      color: parent.foreground
    }
  }

  Button {
    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight
    anchors.verticalCenter: parent.verticalCenter
    foreground: root.canGoForward ? Color.menu.text : Qt.darker(Color.menu.text, 1.6)
    onClicked: root.forwardRequested()
    Accessible.role: Accessible.Button
    Accessible.name: "Forward"

    OpticalGlyph {
      anchors.centerIn: parent
      // md-arrow_right, verificado contra el cmap real de la fuente.
      text: "\u{F0054}"
      fontFamily: Style.font.family
      fontSize: Style.font.icon
      color: parent.foreground
    }
  }

  Button {
    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight
    anchors.verticalCenter: parent.verticalCenter
    foreground: root.canGoUp ? Color.menu.text : Qt.darker(Color.menu.text, 1.6)
    onClicked: root.upRequested()
    Accessible.role: Accessible.Button
    Accessible.name: "Up"

    OpticalGlyph {
      anchors.centerIn: parent
      text: "󰅃"
      fontFamily: Style.font.family
      fontSize: Style.font.icon
      color: parent.foreground
    }
  }
}

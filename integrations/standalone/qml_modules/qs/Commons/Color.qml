pragma Singleton
import QtQuick

// Adaptador MÍNIMO de qs.Commons/Color.qml (Fase 4, josema) -- el real
// lee el tema activo de Omarchy vía Quickshell.Io; este solo fija una
// paleta oscura fija, suficiente para que la UI sea legible en el
// primer arranque standalone. Sin theming de verdad todavía.
QtObject {
  readonly property color accent: "#7aa2f7"
  readonly property color urgent: "#f7768e"

  readonly property QtObject menu: QtObject {
    readonly property color background: "#1a1b26"
    readonly property color border: "#414868"
    readonly property color text: "#c0caf5"
    readonly property color selectedBackground: "#283457"
    readonly property color selectedText: "#c0caf5"
  }
}

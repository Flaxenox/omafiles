pragma Singleton
import QtQuick

// Adaptador MÍNIMO de qs.Commons/Style.qml (Fase 4, josema) -- valores
// fijos razonables, no leídos de ningún tema. Cubre exactamente las
// properties que usa omafiles (ver `grep -rohE "Style\.[A-Za-z.]+"`),
// nada más.
QtObject {
  readonly property real cornerRadius: 8
  readonly property real normalBorderWidth: 1

  readonly property QtObject font: QtObject {
    readonly property string family: "sans-serif"
    readonly property real caption: 11
    readonly property real bodySmall: 12
    readonly property real subtitle: 12
    readonly property real title: 15
    readonly property real displayLarge: 22
    readonly property real icon: 16
    readonly property real iconLarge: 24
  }

  readonly property QtObject spacing: QtObject {
    readonly property real xxs: 2
    readonly property real xs: 4
    readonly property real sm: 8
    readonly property real md: 12
    readonly property real lg: 16
    readonly property real huge: 32
    readonly property real hairline: 1
    readonly property real rowGap: 8
    readonly property real rowPaddingX: 10
    readonly property real controlGap: 8
    readonly property real controlHeight: 32
    readonly property real panelGap: 8
    readonly property real panelPadding: 12
  }

  function hoverFillFor(color) {
    return Qt.rgba(color.r, color.g, color.b, 0.12)
  }
}

import QtQuick

// Adaptador MÍNIMO de qs.Ui/BorderSurface.qml (Fase 4, josema) --
// consume el "spec" simple de qs.Commons/Border.qml ({color, width}),
// nada de gradientes/anchos por lado como el real.
Rectangle {
  id: root
  property var borderSpec: ({ color: "transparent", width: 0 })
  property real padding: 0

  readonly property real contentTopInset: padding + border.width
  readonly property real contentRightInset: padding + border.width
  readonly property real contentBottomInset: padding + border.width
  readonly property real contentLeftInset: padding + border.width

  border.color: borderSpec.color
  border.width: borderSpec.width
}

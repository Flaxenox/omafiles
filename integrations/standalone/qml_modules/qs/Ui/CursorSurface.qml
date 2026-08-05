import QtQuick

// Adaptador MÍNIMO de qs.Ui/CursorSurface.qml (Fase 4, josema) -- base
// de las filas de fichero/marcador (FileListRow.qml, Sidebar.qml). El
// real dibuja el hover/selección con más matices de tema; este solo
// pinta un fondo plano cuando hasCursor/current.
Item {
  id: root
  property color foreground: "#c0caf5"
  property color accent: "#7aa2f7"
  property bool hasCursor: false
  property bool current: false
  property bool bordered: false

  Rectangle {
    anchors.fill: parent
    color: root.current ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
      : (root.hasCursor ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent")
    radius: 4
    border.color: root.bordered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3) : "transparent"
    border.width: root.bordered ? 1 : 0
  }
}

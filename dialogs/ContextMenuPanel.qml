import QtQuick
import qs.Commons
import qs.Ui

// Menú contextual (clic derecho). Octavo componente extraído de
// Omafiles.qml. Las acciones ya llegan como una lista de objetos
// { label, action, enabled, destructive } construida por
// root.itemActions()/emptyAreaActions()/etc. -- cada `action` es ya una
// función lista para llamar, así que este componente no necesita
// señales por acción, solo ejecutarla y pedir cerrarse.
Item {
  id: root

  property bool open: false
  property real menuX: 0
  property real menuY: 0
  property var actions: []

  signal closeRequested()

  // Mide las etiquetas SIN instanciar ningún Text visible -- evita el
  // problema de depender de children reales para calcular el ancho
  // (circular: el ancho de cada fila dependería del ancho del menú, que
  // a su vez debería depender del ancho de cada fila). Misma fuente que
  // usa el Text real de cada fila (ver más abajo).
  FontMetrics {
    id: menuFontMetrics
    font.pixelSize: Style.font.title
    font.family: Style.font.family
    font.weight: Font.Medium
  }

  readonly property real maxLabelWidth: {
    var m = 0
    for (var i = 0; i < root.actions.length; i++) {
      m = Math.max(m, menuFontMetrics.advanceWidth(root.actions[i].label))
    }
    return m
  }

  MouseArea {
    anchors.fill: parent
    visible: root.open
    z: 15
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: root.closeRequested()
  }

  BorderSurface {
    id: contextMenu
    visible: root.open
    x: root.menuX
    y: root.menuY
    // Ancho mínimo 200 (igual que antes) para que un menú con pocas
    // acciones cortas ("Open"/"Delete"...) no se vea escuálido, pero
    // crece con el contenido real -- antes era un 200 fijo, y una
    // etiqueta larga ("Open (extracts a temp copy)", el "Open" de un
    // fichero dentro de un archivo) se salía del recuadro.
    width: Math.max(200, root.maxLabelWidth + Style.spacing.sm * 2 + contentLeftInset + contentRightInset)
    height: contextMenuColumn.implicitHeight + contentTopInset + contentBottomInset
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.sm
    z: 20

    Column {
      id: contextMenuColumn
      anchors.fill: parent
      anchors.topMargin: contextMenu.contentTopInset
      anchors.rightMargin: contextMenu.contentRightInset
      anchors.bottomMargin: contextMenu.contentBottomInset
      anchors.leftMargin: contextMenu.contentLeftInset
      spacing: Style.spacing.xs

      Repeater {
        model: root.actions

        CursorSurface {
          required property var modelData
          readonly property bool actionEnabled: modelData.enabled !== false
          width: contextMenuColumn.width
          implicitHeight: Style.spacing.controlHeight
          foreground: Color.menu.text
          accent: Color.accent
          hasCursor: itemMouse.containsMouse && actionEnabled

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            text: parent.modelData.label
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.weight: Font.Medium
            color: parent.modelData.destructive ? Color.urgent : (parent.actionEnabled ? Color.menu.text : Qt.darker(Color.menu.text, 1.8))
          }

          MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.actionEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.closeRequested()
              parent.modelData.action()
            }
          }
        }
      }
    }
  }
}

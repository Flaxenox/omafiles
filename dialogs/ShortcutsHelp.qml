import QtQuick
import qs.Commons
import qs.Ui

// Overlay de ayuda de atajos de teclado (tecla "?"). Extraído de
// Omafiles.qml como primer paso de un componentizado incremental --
// se eligió este por ser el trozo más aislado del fichero: sin
// Process/async, sin tocar disco, una sola propiedad externa (si está
// abierto) y una sola acción hacia fuera (pedir cerrarse). El resto del
// fichero sigue siendo el dueño real de root.shortcutsHelpOpen; este
// componente solo lo refleja.
Item {
  id: root

  property bool open: false
  signal requestClose()

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    visible: root.open
    z: 15
    onClicked: root.requestClose()
  }

  BorderSurface {
    id: shortcutsHelpCard
    visible: root.open
    width: Math.min(parent.width - 80, 420)
    height: Math.min(parent.height - 80, 460)
    anchors.centerIn: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.sm
    z: 20

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: shortcutsHelpColumn
      anchors.fill: parent
      anchors.topMargin: shortcutsHelpCard.contentTopInset
      anchors.rightMargin: shortcutsHelpCard.contentRightInset
      anchors.bottomMargin: shortcutsHelpCard.contentBottomInset
      anchors.leftMargin: shortcutsHelpCard.contentLeftInset
      spacing: Style.spacing.xs

      Text {
        width: parent.width
        text: "Keyboard shortcuts"
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: true
        color: Color.menu.text
      }

      PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

      Flickable {
        width: parent.width
        // Altura fija en vez de calculada a partir de los hermanos del
        // Column (título/separador/botón) -- más simple y evita atarse
        // a un Item auxiliar solo para medir. 460 de alto de tarjeta
        // menos cabecera/separador/botón deja hueco de sobra para las
        // ~24 filas sin que sea necesario hacer scroll casi nunca.
        height: 320
        clip: true
        contentWidth: width
        contentHeight: shortcutsHelpRepeaterColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: shortcutsHelpRepeaterColumn
          width: parent.width
          spacing: Style.spacing.xs

          // Mismo orden que la tabla de la sección "Keyboard
          // shortcuts" del README -- si se añade/edita un atajo ahí,
          // hacerlo aquí también.
          Repeater {
            model: [
              { key: "j / k / ↓ / ↑", action: "Move down / up" },
              { key: "h / Backspace", action: "Go up a directory" },
              { key: "Alt+← / Alt+→", action: "Back / forward" },
              { key: "l / Enter", action: "Open (enter directory / launch file)" },
              { key: "gg / Shift+G", action: "Jump to top / bottom" },
              { key: "Space", action: "Toggle preview" },
              { key: "/", action: "Search here (Ctrl+Enter searches recursively)" },
              { key: ": / Ctrl+P", action: "Command palette" },
              { key: "Ctrl+A", action: "Select all" },
              { key: "Ctrl+Shift+A", action: "Select none" },
              { key: "Ctrl+I", action: "Invert selection" },
              { key: "F2", action: "Rename" },
              { key: "Delete", action: "Delete (to trash)" },
              { key: "Ctrl+C / Ctrl+X / Ctrl+V", action: "Copy / cut / paste" },
              { key: "Ctrl+Z", action: "Undo" },
              { key: "Ctrl+Shift+Z / Ctrl+Y", action: "Redo" },
              { key: "s / Shift+S", action: "Cycle sort field / reverse order" },
              { key: "Ctrl+L", action: "Edit path directly" },
              { key: "Ctrl+Shift+N", action: "New folder" },
              { key: "Ctrl+N", action: "New file" },
              { key: "Ctrl+T / Ctrl+\\", action: "New tab (new panel)" },
              { key: "Ctrl+W / Ctrl+Tab", action: "Close tab / next tab" },
              { key: "Ctrl+H", action: "Toggle hidden files" },
              { key: "Shift+Enter", action: "Open a terminal here" },
              { key: "F5", action: "Refresh" },
              { key: "?", action: "Toggle this help" },
              { key: "Escape", action: "Close preview, or close the window" }
            ]

            Row {
              required property var modelData
              width: shortcutsHelpRepeaterColumn.width
              spacing: Style.spacing.sm

              Text {
                width: 170
                text: parent.modelData.key
                font.pixelSize: Style.font.bodySmall
                font.family: "monospace"
                color: Color.menu.text
                opacity: 0.7
                wrapMode: Text.Wrap
              }

              Text {
                width: parent.width - 170 - Style.spacing.sm
                text: parent.modelData.action
                font.pixelSize: Style.font.bodySmall
                font.family: Style.font.family
                color: Color.menu.text
                wrapMode: Text.Wrap
              }
            }
          }
        }
      }

      Button {
        id: closeShortcutsButton
        text: "Close"
        bordered: true
        Accessible.role: Accessible.Button
        Accessible.name: text
        onClicked: root.requestClose()
      }
    }
  }
}

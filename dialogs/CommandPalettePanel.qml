import QtQuick
import qs.Commons
import qs.Ui

// Paleta de comandos (":" o Ctrl+P). Noveno componente extraído de
// Omafiles.qml -- el más interactivo de todos (campo de texto en vivo +
// navegación con flechas + selección con el ratón), así que expone más
// señales que los anteriores, pero el patrón es el mismo: Omafiles.qml
// sigue siendo el dueño real de paletteQuery/paletteIndex, y
// `commands` ya llega filtrado desde fuera (root.filteredPaletteCommands()
// se sigue evaluando en el padre, donde "root" es de verdad el root real
// -- aquí solo se muestra el resultado).
Item {
  id: root

  property bool open: false
  property string query: ""
  property int index: 0
  property var commands: []

  signal queryEdited(string text)
  signal closeRequested()
  signal indexRequested(int index)
  signal commandActivated(int index)
  signal focusReturnRequested()

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    visible: root.open
    z: 25
    onClicked: root.closeRequested()
  }

  BorderSurface {
    id: palette
    visible: root.open
    width: Math.min(parent.width - 80, 420)
    height: Math.min(parent.height - 2 * Style.spacing.huge, 360)
    anchors.horizontalCenter: parent.horizontalCenter
    y: Style.spacing.huge
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    // Mismo padding de popup que el menú contextual (popupPadding, 14): los
    // dos menús comparten el espaciado del sistema en vez del sm (4) apretado.
    padding: Style.spacing.popupPadding
    z: 30

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: paletteColumn
      anchors.fill: parent
      anchors.topMargin: palette.contentTopInset
      anchors.rightMargin: palette.contentRightInset
      anchors.bottomMargin: palette.contentBottomInset
      anchors.leftMargin: palette.contentLeftInset
      spacing: Style.spacing.sm

      TextField {
        id: paletteField
        width: parent.width
        Accessible.role: Accessible.EditableText
        Accessible.name: "Command palette"
        placeholderText: "Type a command…"
        text: root.query
        onTextChanged: root.queryEdited(text)
        onVisibleChanged: if (visible) forceActiveFocus(); else root.focusReturnRequested()
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.commandActivated(root.index)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            var nextIdx = Math.min(root.commands.length - 1, root.index + 1)
            root.indexRequested(nextIdx)
            paletteList.positionViewAtIndex(nextIdx, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            var prevIdx = Math.max(0, root.index - 1)
            root.indexRequested(prevIdx)
            paletteList.positionViewAtIndex(prevIdx, ListView.Contain)
            event.accepted = true
          }
        }
      }

      PanelSeparator { id: paletteSep; foreground: Color.menu.text; strength: 0.15 }

      ListView {
        id: paletteList
        width: parent.width
        height: parent.height - paletteField.height - paletteSep.height - 2 * paletteColumn.spacing
        spacing: Style.spacing.sm
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.commands

        delegate: CursorSurface {
          required property var modelData
          required property int index
          readonly property bool cmdEnabled: modelData.enabled !== false
          width: paletteList.width
          implicitHeight: Style.spacing.controlHeight
          foreground: Color.menu.text
          accent: Color.accent
          hasCursor: index === root.index && cmdEnabled

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            text: parent.modelData.label
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.weight: Font.Medium
            color: parent.cmdEnabled ? (index === root.index ? Color.menu.selectedText : Color.menu.text) : Qt.darker(Color.menu.text, 1.8)
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.cmdEnabled
            cursorShape: Qt.PointingHandCursor
            onEntered: root.indexRequested(index)
            onClicked: root.commandActivated(index)
          }
        }
      }
    }
  }
}

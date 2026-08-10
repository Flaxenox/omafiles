import QtQuick
import qs.Commons
import qs.Ui

// Diálogo "Bulk rename...". Sexto componente extraído de Omafiles.qml.
// El patrón elegido se pide hacia fuera con una señal parametrizada
// (igual que ConnectServer.qml/ChmodPanel.qml) -- Omafiles.qml sigue
// siendo el dueño real de root.bulkRenamePattern.
Item {
  id: root

  property bool open: false
  property int selectedCount: 0
  property string pattern: ""
  property var history: []

  signal closeRequested()
  signal renameRequested(string pattern)
  signal focusReturnRequested()

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    visible: root.open
    z: 15
    onClicked: root.closeRequested()
  }

  BorderSurface {
    id: bulkRenameCard
    visible: root.open || opacity > 0
    width: Math.min(parent.width - 80, 380)
    height: bulkRenameColumn.implicitHeight + contentTopInset + contentBottomInset
    anchors.centerIn: parent
    // Fase 22: entrada discreta del diálogo (opacity 0->1, scale
    // 0.98->1.0, 120 ms, sin overshoot). No bloquea el clic.
    opacity: root.open ? 1 : 0
    scale: root.open ? 1 : 0.98
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.sm
    z: 20

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: bulkRenameColumn
      anchors.fill: parent
      anchors.topMargin: bulkRenameCard.contentTopInset
      anchors.rightMargin: bulkRenameCard.contentRightInset
      anchors.bottomMargin: bulkRenameCard.contentBottomInset
      anchors.leftMargin: bulkRenameCard.contentLeftInset
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        text: "Rename " + root.selectedCount + " items"
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: true
        color: Color.menu.text
      }

      Text {
        width: parent.width
        text: "Use {name}, {ext}, {n} (sequence number)"
        font.pixelSize: Style.font.subtitle
        font.family: Style.font.family
        color: Color.menu.text
        opacity: 0.6
        wrapMode: Text.Wrap
      }

      TextField {
        id: bulkRenameField
        width: parent.width
        Accessible.role: Accessible.EditableText
        Accessible.name: "Bulk rename pattern"
        text: root.pattern
        onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() } else root.focusReturnRequested()
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.renameRequested(text)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
          }
        }
      }

      // Patrones usados antes, más reciente primero -- clic rellena
      // el campo (no renombra directo), para que se pueda revisar/
      // ajustar antes de aplicar. Solo si hay historial: la primera
      // vez que se usa Bulk rename no hay nada que ofrecer aquí.
      Flow {
        width: parent.width
        visible: root.history.length > 0
        spacing: Style.spacing.xs

        Repeater {
          model: root.history

          CursorSurface {
            id: patternChip
            required property string modelData
            width: chipText.implicitWidth + Style.spacing.sm * 2
            height: Style.spacing.controlHeight * 0.8
            foreground: Color.menu.text
            accent: Color.accent
            // Sin esto se confundía con texto suelto en reposo -- el
            // mismo componente ya lleva borde permanente en la rejilla
            // de permisos de chmod (chmodCell) por este motivo
            // exacto, aquí se le había olvidado.
            bordered: true
            hasCursor: chipMouse.containsMouse
            Accessible.role: Accessible.Button
            Accessible.name: "Use pattern " + modelData

            Text {
              id: chipText
              anchors.centerIn: parent
              text: patternChip.modelData
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
              color: Color.menu.text
            }

            MouseArea {
              id: chipMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                bulkRenameField.text = patternChip.modelData
                bulkRenameField.forceActiveFocus()
                bulkRenameField.selectAll()
              }
            }
          }
        }
      }

      Button {
        text: "Rename"
        bordered: true
        Accessible.role: Accessible.Button
        Accessible.name: text
        onClicked: root.renameRequested(bulkRenameField.text)
      }
    }
  }
}

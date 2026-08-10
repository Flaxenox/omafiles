import QtQuick
import qs.Commons
import qs.Ui

// Diálogo de "Propiedades" de la selección. Tercer componente extraído
// de Omafiles.qml -- de solo lectura (nada de TextField ni Process
// propio, el padre ya resuelve tamaño/permisos/dueño/fecha por su
// cuenta con la guardia de carrera propertiesRequestId), así que solo
// necesita una señal de cierre, igual de simple que ShortcutsHelp.qml.
Item {
  id: root

  property bool open: false
  property bool multi: false
  property int count: 0
  property var entry: null
  property bool sizeLoading: false
  property string size: ""
  property string perms: ""
  property string owner: ""
  property string mtime: ""

  signal closeRequested()

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    visible: root.open
    z: 15
    onClicked: root.closeRequested()
  }

  BorderSurface {
    id: propertiesCard
    visible: root.open || opacity > 0
    width: Math.min(parent.width - 80, 360)
    height: propertiesColumn.implicitHeight + contentTopInset + contentBottomInset
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
      id: propertiesColumn
      anchors.fill: parent
      anchors.topMargin: propertiesCard.contentTopInset
      anchors.rightMargin: propertiesCard.contentRightInset
      anchors.bottomMargin: propertiesCard.contentBottomInset
      anchors.leftMargin: propertiesCard.contentLeftInset
      spacing: Style.spacing.xs

      Text {
        width: parent.width
        text: root.multi
          ? root.count + " items selected"
          : (root.entry ? root.entry.name : "")
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: true
        color: Color.menu.text
        elide: Text.ElideMiddle
      }

      PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

      Repeater {
        model: root.multi
          ? [
              { label: "Items", value: String(root.count) },
              { label: "Total size", value: root.sizeLoading ? "Calculating…" : root.size }
            ]
          : [
              { label: "Type", value: root.entry ? (root.entry.type === "dir" ? "Folder" : "File") : "" },
              { label: "Size", value: root.sizeLoading ? "Calculating…" : root.size },
              { label: "Permissions", value: root.perms },
              { label: "Owner", value: root.owner },
              { label: "Modified", value: root.mtime }
            ]

        Row {
          required property var modelData
          width: propertiesColumn.width
          spacing: Style.spacing.sm

          Text {
            // Mismo ajuste que la tabla de metadatos de audio: 84 no
            // le llegaba a "Permissions" (mide igual de ancho que
            // "Sample rate", medido con la fuente real).
            width: 120
            text: parent.modelData.label
            font.pixelSize: Style.font.subtitle
            font.family: Style.font.family
            color: Color.menu.text
            opacity: Style.emphasis.secondary
          }

          Text {
            width: parent.width - 120 - Style.spacing.sm
            text: parent.modelData.value
            font.pixelSize: Style.font.subtitle
            font.family: Style.font.family
            color: Color.menu.text
            elide: Text.ElideRight
          }
        }
      }

      Button {
        text: "Close"
        bordered: true
        Accessible.role: Accessible.Button
        Accessible.name: text
        onClicked: root.closeRequested()
      }
    }
  }
}

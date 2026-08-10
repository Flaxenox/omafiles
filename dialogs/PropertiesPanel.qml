import QtQuick
import qs.Commons
import qs.Ui
import "../shared"

// Diálogo de "Propiedades" de la selección. Tercer componente extraído
// de Omafiles.qml -- de solo lectura (nada de TextField ni Process
// propio, el padre ya resuelve tamaño/permisos/dueño/fecha por su
// cuenta con la guardia de carrera propertiesRequestId), así que solo
// necesita una señal de cierre, igual de simple que ShortcutsHelp.qml.
//
// El envoltorio modal (scrim + tarjeta + animación + padding) es
// shared/ModalSurface.qml, común a todos los diálogos.
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

  ModalSurface {
    open: root.open
    maxWidth: Style.space(360)
    onDismissed: root.closeRequested()

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
        width: parent.width
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

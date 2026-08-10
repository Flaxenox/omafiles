import QtQuick
import qs.Commons

// Fila de migas de pan (segmentos de la ruta) -- decimoquinto componente
// extraído de Omafiles.qml, compartido entre panel activo y de fondo.
// Antes eran dos Repeater casi idénticos (breadcrumbRow y bgBreadcrumbRow)
// que comparaban cada segmento contra una ruta "actual" distinta según el
// panel -- aquí ese "actual" es un solo parámetro (activePath) que quien
// llama ya resuelve (root.currentPath o bgPanel.modelData.path). El panel
// activo sigue teniendo, fuera de este componente, el MouseArea y el
// TextField para editar la ruta a mano -- el de fondo no los necesita.
Row {
  id: root

  property var segments: []
  property string activePath: ""

  spacing: Style.spacing.xs
  clip: true

  Repeater {
    model: root.segments

    Row {
      required property var modelData
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      // Sin MouseArea propio a propósito -- josema no quería navegación
      // por segmento (ya están los botones de atrás/subir para eso),
      // solo texto que deje pasar el clic al MouseArea de detrás (editar
      // ruta a mano, solo en el panel activo).
      Text {
        text: modelData.label
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: modelData.path === root.activePath
        color: Color.menu.text
        opacity: modelData.path === root.activePath ? 1.0 : Style.emphasis.secondary
      }

      Text {
        visible: modelData.path !== root.activePath
        text: "›"
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        color: Color.menu.text
        opacity: Style.emphasis.muted
      }
    }
  }
}

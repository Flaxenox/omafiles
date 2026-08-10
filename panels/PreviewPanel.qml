import QtQuick
import qs.Commons
import qs.Ui

// Panel de vista previa (Espacio). Undécimo componente extraído de
// Omafiles.qml -- puramente de lectura (nada de clics propios más allá
// de "no dejar pasar el toque a lo de detrás"), así que a diferencia de
// Sidebar.qml no hace falta ni una señal: todo lo que antes eran
// llamadas a root.isImage(root.previewEntry)/etc. repetidas varias
// veces por el fichero ahora son booleanos ya resueltos que pasa el
// padre (que sigue siendo el único que ve esas funciones).
Item {
  id: root

  property bool open: false
  property string entryName: ""
  property bool hasEntry: false
  property bool isImageEntry: false
  property bool isVideoEntry: false
  property bool isTextEntry: false
  property bool isPdfEntry: false
  property bool isAudioEntry: false
  property url imageSource: ""
  property url videoThumbSource: ""
  property string highlightedText: ""
  property string plainText: ""
  property url pdfImageSource: ""
  property var audioInfo: []
  property string fallbackSizeText: ""

  BorderSurface {
    id: previewPanel
    visible: root.open
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    width: parent.width * 0.45 - Style.spacing.rowGap
    radius: Style.cornerRadius
    color: Color.menu.selectedBackground
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.sm

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      anchors.fill: parent
      anchors.topMargin: previewPanel.contentTopInset
      anchors.rightMargin: previewPanel.contentRightInset
      anchors.bottomMargin: previewPanel.contentBottomInset
      anchors.leftMargin: previewPanel.contentLeftInset
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        text: root.entryName
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: true
        color: Color.menu.text
        elide: Text.ElideMiddle
      }

      PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

      Image {
        visible: root.isImageEntry
        width: parent.width
        height: parent.height - 60
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        source: root.isImageEntry ? root.imageSource : ""
        // Fase 22: fade-in al terminar de cargar (0 -> 1, 120 ms), nada de
        // aparecer de golpe. Sin bloquear nada.
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }

      Image {
        visible: root.isVideoEntry && root.videoThumbSource !== ""
        width: parent.width
        height: parent.height - 60
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        source: root.videoThumbSource
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }

      Flickable {
        visible: root.isTextEntry
        width: parent.width
        height: parent.height - 60
        clip: true
        contentWidth: width
        contentHeight: (root.highlightedText.length > 0 ? previewHighlightedItem : previewTextItem).implicitHeight

        // Resaltado de sintaxis cuando highlight-preview.sh
        // (Pygments) reconoció el lenguaje -- ver loadPreview().
        // Mismo Flickable/posición que el Text plano de abajo,
        // uno de los dos siempre queda oculto.
        Text {
          id: previewHighlightedItem
          visible: root.highlightedText.length > 0
          width: parent.width
          textFormat: Text.RichText
          text: root.highlightedText
          font.pixelSize: Style.font.subtitle
          font.family: "monospace"
          color: Color.menu.text
          wrapMode: Text.Wrap
        }

        Text {
          id: previewTextItem
          visible: root.highlightedText.length === 0
          width: parent.width
          text: root.plainText || "(empty)"
          font.pixelSize: Style.font.subtitle
          font.family: "monospace"
          color: Color.menu.text
          wrapMode: Text.Wrap
        }
      }

      Image {
        visible: root.isPdfEntry && root.pdfImageSource !== ""
        width: parent.width
        height: parent.height - 60
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        source: root.pdfImageSource
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }

      Column {
        visible: root.isAudioEntry && root.audioInfo.length > 0
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: root.audioInfo

          Row {
            required property var modelData
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              // 84 no le llegaba a "Sample rate" (se pegaba con
              // el valor sin espacio, confirmado midiendo el
              // glyph real de la fuente) -- 120 deja margen de
              // sobra para cualquier etiqueta actual de esta
              // tabla al tamaño de fuente real de la app.
              width: 120
              text: parent.modelData.label
              font.pixelSize: Style.font.subtitle
              font.family: Style.font.family
              color: Color.menu.text
              opacity: 0.6
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
      }

      Column {
        visible: root.hasEntry && !root.isImageEntry && !root.isTextEntry
          && !(root.isVideoEntry && root.videoThumbSource !== "")
          && !(root.isPdfEntry && root.pdfImageSource !== "")
          && !(root.isAudioEntry && root.audioInfo.length > 0)
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "No preview"
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          color: Color.menu.text
          opacity: 0.5
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.fallbackSizeText
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          color: Color.menu.text
          opacity: 0.6
        }
      }
    }
  }
}

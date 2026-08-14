import QtQuick
import qs.Commons
import qs.Ui

// Preview panel (Space). Eleventh component extracted from
// core -- purely read-only (no clicks of its own beyond
// "don't let the tap pass through to what's behind"), so unlike
// Sidebar.qml it doesn't even need a signal: everything that used to be
// calls to root.isImage(root.previewEntry)/etc. repeated several
// times across the file are now already-resolved booleans passed by the
// parent (which is still the only one that sees those functions).
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
        // Phase 22: fade-in when loading finishes (0 -> 1, 120 ms), no
        // appearing all at once. Without blocking anything.
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

        // Syntax highlighting when highlight-preview.sh
        // (Pygments) recognized the language -- see loadPreview().
        // Same Flickable/position as the plain Text below,
        // one of the two is always hidden.
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
              // 84 didn't reach "Sample rate" (it stuck to
              // the value without a space, confirmed by measuring the
              // font's real glyph) -- 120 leaves plenty of margin
              // for any current label of this
              // table at the app's real font size.
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
          opacity: Style.emphasis.muted
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.fallbackSizeText
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          color: Color.menu.text
          opacity: Style.emphasis.secondary
        }
      }
    }
  }
}

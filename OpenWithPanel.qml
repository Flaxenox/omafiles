import QtQuick
import qs.Commons
import qs.Ui

// Diálogo "Abrir con...". Cuarto componente extraído de Omafiles.qml --
// como con ConnectServer.qml, la acción real (lanzar la app elegida) se
// expone como señal parametrizada en vez de llamar a root.launchWith()
// directamente desde dentro del componente.
Item {
  id: root

  property bool open: false
  property var entry: null
  property var apps: []

  signal closeRequested()
  signal appSelected(string appId)

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    visible: root.open
    z: 15
    onClicked: root.closeRequested()
  }

  BorderSurface {
    id: openWithCard
    visible: root.open
    width: Math.min(parent.width - 80, 320)
    height: openWithColumn.implicitHeight + contentTopInset + contentBottomInset
    anchors.centerIn: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.sm
    z: 20

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: openWithColumn
      anchors.fill: parent
      anchors.topMargin: openWithCard.contentTopInset
      anchors.rightMargin: openWithCard.contentRightInset
      anchors.bottomMargin: openWithCard.contentBottomInset
      anchors.leftMargin: openWithCard.contentLeftInset
      spacing: Style.spacing.xs

      Text {
        width: parent.width
        text: "Open \"" + (root.entry ? root.entry.name : "") + "\" with:"
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: true
        color: Color.menu.text
        elide: Text.ElideMiddle
      }

      PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

      Text {
        visible: root.apps.length === 0
        width: parent.width
        text: "No registered applications for this file type."
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        color: Color.menu.text
        opacity: 0.6
        wrapMode: Text.Wrap
      }

      Repeater {
        model: root.apps

        CursorSurface {
          required property var modelData
          width: openWithColumn.width
          implicitHeight: Style.spacing.controlHeight
          foreground: Color.menu.text
          accent: Color.accent
          hasCursor: appMouse.containsMouse

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            text: parent.modelData.name
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.weight: Font.Medium
            color: Color.menu.text
          }

          MouseArea {
            id: appMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.appSelected(modelData.id)
          }
        }
      }
    }
  }
}

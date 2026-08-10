import QtQuick
import qs.Commons
import qs.Ui
import "../shared"

// Diálogo "Abrir con...". Cuarto componente extraído de Omafiles.qml --
// como con ConnectServer.qml, la acción real (lanzar la app elegida) se
// expone como señal parametrizada en vez de llamar a root.launchWith()
// directamente desde dentro del componente.
//
// El envoltorio modal (scrim + tarjeta + animación + padding) es
// shared/ModalSurface.qml, común a todos los diálogos.
Item {
  id: root

  property bool open: false
  property var entry: null
  property var apps: []

  signal closeRequested()
  signal appSelected(string appId)

  ModalSurface {
    open: root.open
    maxWidth: Style.space(320)
    onDismissed: root.closeRequested()

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
      opacity: Style.emphasis.secondary
      wrapMode: Text.Wrap
    }

    Repeater {
      model: root.apps

      CursorSurface {
        required property var modelData
        width: parent.width
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

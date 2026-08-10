import QtQuick
import qs.Commons
import qs.Ui

// Diálogo "Conectar a servidor" (SFTP/SMB/WebDAV/FTP). Segundo
// componente extraído de Omafiles.qml -- algo más acoplado que
// ShortcutsHelp.qml (tiene texto editable + un estado "conectando"
// intermedio con dos cancelaciones distintas: cerrar el diálogo vs.
// abortar solo el intento en curso), así que expone señales en vez de
// llamar directamente a funciones de root. Omafiles.qml sigue siendo el
// dueño real de connectServerUri/networkConnecting/connectServerError.
Item {
  id: root

  property bool open: false
  property bool connecting: false
  property string uri: ""
  property string errorText: ""

  // "Conectar" pulsado (Enter o botón) -- el padre decide qué hacer con
  // la URI (guardarla + commitConnectToServer()).
  signal connectRequested(string uri)
  // Escape mientras hay un intento en curso: abortar SOLO el intento,
  // el diálogo se queda abierto (igual que el botón "Cancel").
  signal cancelConnectingRequested()
  // Escape o clic fuera cuando NO hay un intento en curso: cerrar el
  // diálogo entero.
  signal closeRequested()
  // El campo de texto deja de estar visible (diálogo cerrado) -- el
  // padre es quien sabe a qué Item devolver el foco (la lista).
  signal focusReturnRequested()

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    visible: root.open
    z: 15
    onClicked: if (!root.connecting) root.closeRequested()
  }

  BorderSurface {
    id: connectServerCard
    visible: root.open || opacity > 0
    width: Math.min(parent.width - 80, 420)
    height: connectServerColumn.implicitHeight + contentTopInset + contentBottomInset
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
      id: connectServerColumn
      anchors.fill: parent
      anchors.topMargin: connectServerCard.contentTopInset
      anchors.rightMargin: connectServerCard.contentRightInset
      anchors.bottomMargin: connectServerCard.contentBottomInset
      anchors.leftMargin: connectServerCard.contentLeftInset
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        text: "Connect to server"
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: true
        color: Color.menu.text
      }

      Text {
        width: parent.width
        text: "sftp://user@host/path · smb://server/share · dav(s)://host/path · ftp://host/path"
        font.pixelSize: Style.font.bodySmall
        font.family: Style.font.family
        color: Color.menu.text
        opacity: Style.emphasis.secondary
        wrapMode: Text.Wrap
      }

      TextField {
        id: connectServerField
        width: parent.width
        Accessible.role: Accessible.EditableText
        Accessible.name: "Server address"
        text: root.uri
        enabled: !root.connecting
        onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() } else root.focusReturnRequested()
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.connectRequested(text)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.connecting) root.cancelConnectingRequested()
            else root.closeRequested()
            event.accepted = true
          }
        }
      }

      Text {
        width: parent.width
        visible: root.errorText.length > 0
        text: root.errorText
        font.pixelSize: Style.font.bodySmall
        font.family: Style.font.family
        color: Color.urgent
        wrapMode: Text.Wrap
      }

      Row {
        spacing: Style.spacing.sm

        Button {
          text: root.connecting ? "Connecting…" : "Connect"
          bordered: true
          enabled: !root.connecting
          Accessible.role: Accessible.Button
          Accessible.name: text
          onClicked: root.connectRequested(connectServerField.text)
        }

        Button {
          text: "Cancel"
          visible: root.connecting
          Accessible.role: Accessible.Button
          Accessible.name: text
          onClicked: root.cancelConnectingRequested()
        }
      }
    }
  }
}

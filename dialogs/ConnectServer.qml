import QtQuick
import qs.Commons
import qs.Ui
import "../shared"

// "Connect to server" dialog (SFTP/SMB/WebDAV/FTP). Second
// component extracted from core -- a bit more coupled than
// ShortcutsHelp.qml (it has editable text + an intermediate "connecting"
// state with two different cancellations: close the dialog vs.
// abort only the current attempt), so it exposes signals instead of
// calling root functions directly. core is still the
// real owner of connectServerUri/networkConnecting/connectServerError.
//
// The modal wrapper (scrim + card + animation + padding) is
// shared/ModalSurface.qml, common to all dialogs.
Item {
  id: root

  property bool open: false
  property bool connecting: false
  property string uri: ""
  property string errorText: ""

  // "Connect" pressed (Enter or button) -- the parent decides what to do with
  // the URI (save it + commitConnectToServer()).
  signal connectRequested(string uri)
  // Escape while there is an attempt in progress: abort ONLY the attempt,
  // the dialog stays open (like the "Cancel" button).
  signal cancelConnectingRequested()
  // Escape or click outside when there is NO attempt in progress: close the
  // whole dialog.
  signal closeRequested()
  // The text field stops being visible (dialog closed) -- the
  // parent is the one that knows which Item to return focus to (the list).
  signal focusReturnRequested()

  ModalSurface {
    open: root.open
    maxWidth: Style.space(420)
    // Click outside closes the dialog, but NOT while there is a connection
    // attempt in progress (like before: the backdrop only closed if
    // !connecting) -- the attempt's "Cancel" button is for that.
    dismissable: !root.connecting
    onDismissed: root.closeRequested()

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

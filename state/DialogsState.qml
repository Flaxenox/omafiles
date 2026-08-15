pragma Singleton
import QtQuick

// Flags for standalone dialogs that are independent of each other (bulk
// rename, shortcuts help, connect to server) -- eleventh and last
// "dialog" singleton of the state/ layer. Each of
// dialogs/BulkRenamePanel.qml, dialogs/ShortcutsHelp.qml and
// dialogs/ConnectServer.qml is purely presentational (its own
// local `id: root`, fed by binding from core), so
// none of them needs to import this directly.
QtObject {
  property bool bulkRenameOpen: false
  property string bulkRenamePattern: "{name}{ext}"

  property bool shortcutsHelpOpen: false

  property bool connectServerOpen: false
  property string connectServerUri: ""
  property string connectServerError: ""
  property bool networkConnecting: false
  property bool networkAuthRequested: false
  property string networkAuthMessage: ""
  property string networkAuthUser: ""
}

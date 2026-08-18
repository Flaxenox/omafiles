pragma Singleton
import QtQuick

// Flags for standalone dialogs that are independent of each other (bulk
// rename, shortcuts help, connect to server, notification history) --
// twelfth "dialog" singleton of the state/ layer. Each of
// dialogs/BulkRenamePanel.qml, dialogs/ShortcutsHelp.qml,
// dialogs/ConnectServer.qml and dialogs/NotificationHistory.qml is purely
// presentational (its own local `id: root`, fed by binding from core), so
// none of them needs to import this directly.
QtObject {
  property bool bulkRenameOpen: false
  property string bulkRenamePattern: "{name}{ext}"
  // Regex find/replace (V1.1), applied to the base name before {name}/{ext}/
  // {n} substitution -- ephemeral like bulkRenamePattern above, not
  // persisted (only the pattern itself joins BookmarksState.bulkRenameHistory).
  property string bulkRenameFind: ""
  property string bulkRenameReplace: ""

  property bool shortcutsHelpOpen: false

  property bool notificationHistoryOpen: false

  property bool connectServerOpen: false
  property string connectServerUri: ""
  property string connectServerError: ""
  property bool networkConnecting: false
  property bool networkAuthRequested: false
  property string networkAuthMessage: ""
  property string networkAuthUser: ""
}

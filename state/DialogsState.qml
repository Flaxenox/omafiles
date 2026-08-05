pragma Singleton
import QtQuick

// Banderas de diálogos sueltos e independientes entre sí (renombrado en
// lote, ayuda de atajos, conectar a servidor) -- undécimo y último
// singleton "de diálogo" de la capa state/. Cada uno de
// dialogs/BulkRenamePanel.qml, dialogs/ShortcutsHelp.qml y
// dialogs/ConnectServer.qml es puramente presentacional (su propio
// `id: root` local, alimentado por binding desde Omafiles.qml), así que
// ninguno necesita importar esto directamente.
QtObject {
  property bool bulkRenameOpen: false
  property string bulkRenamePattern: "{name}{ext}"

  property bool shortcutsHelpOpen: false

  property bool connectServerOpen: false
  property string connectServerUri: ""
  property string connectServerError: ""
  property bool networkConnecting: false
}

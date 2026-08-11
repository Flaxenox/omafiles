pragma Singleton
import QtQuick

// State of the command palette (":" or Ctrl+P) -- sixth singleton of the
// state/ layer. dialogs/CommandPalettePanel.qml is purely presentational
// (its own local `open`/`query`/`index`, fed by binding
// from Omafiles.qml), so it does not need to import this directly.
QtObject {
  property bool paletteOpen: false
  property string paletteQuery: ""
  property int paletteIndex: 0
}

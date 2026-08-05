pragma Singleton
import QtQuick

// Estado de la paleta de comandos (":" o Ctrl+P) -- sexto singleton de la
// capa state/. dialogs/CommandPalettePanel.qml es puramente presentacional
// (sus propias `open`/`query`/`index` locales, alimentadas por binding
// desde Omafiles.qml), así que no necesita importar esto directamente.
QtObject {
  property bool paletteOpen: false
  property string paletteQuery: ""
  property int paletteIndex: 0
}

pragma Singleton
import QtQuick

// State of the context menu (right-click on an item or empty area) --
// fifth singleton of the state/ layer, same pattern as Selection/
// Clipboard/Undo/Conflict. contextMenuActions is computed in Omafiles.qml
// (itemActions()/emptyAreaActions(), which need to see almost all the rest
// of the state) just before opening the menu.
QtObject {
  property bool contextMenuOpen: false
  property real contextMenuX: 0
  property real contextMenuY: 0
  property var contextMenuActions: []
}

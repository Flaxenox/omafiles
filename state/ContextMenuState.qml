pragma Singleton
import QtQuick

// Estado del menú contextual (clic derecho sobre un ítem o área vacía) --
// quinto singleton de la capa state/, mismo patrón que Selection/
// Clipboard/Undo/Conflict. contextMenuActions se calcula en Omafiles.qml
// (itemActions()/emptyAreaActions(), que necesitan ver casi todo el resto
// del estado) justo antes de abrir el menú.
QtObject {
  property bool contextMenuOpen: false
  property real contextMenuX: 0
  property real contextMenuY: 0
  property var contextMenuActions: []
}

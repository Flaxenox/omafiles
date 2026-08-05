pragma Singleton
import QtQuick

// Modo de edición inline del panel activo -- renombrar una fila, nueva
// carpeta, nuevo fichero, editar la ruta a mano -- decimoctavo singleton
// de la capa state/. Mutuamente excluyentes (cada startX() en
// logic/RenameOps.qml/SearchOps.qml apaga los demás), ya usado por
// hasPendingEdit para bloquear cambios de pestaña/panel mientras hay
// algo a medio escribir.
QtObject {
  property int renamingIndex: -1
  property bool creatingFolder: false
  property bool creatingFile: false
  property bool editingPath: false
}

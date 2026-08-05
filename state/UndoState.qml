pragma Singleton
import QtQuick

// Pilas de deshacer/rehacer (Ctrl+Z / Ctrl+Shift+Z) -- tercer singleton
// de la capa state/, mismo patrón validado con SelectionState/
// ClipboardState. Acciones reversibles: renombrar, nueva carpeta/fichero,
// borrar (a la papelera), mover (cortar+pegar/arrastrar), renombrado en
// lote, chmod y enlace. Copiar/comprimir se quedan fuera a propósito --
// deshacerlos es más ambiguo (¿borrar la copia? ¿y si ya se movió/editó?)
// que perder por error algo renombrado/movido/borrado/con permisos
// cambiados. La lógica que las manipula sigue en logic/ActionEngine.qml.
QtObject {
  property var undoStack: []
  // redoFn es opcional -- solo las entradas que lo llevan aparecen en
  // Ctrl+Shift+Z. Cualquier acción NUEVA (pushUndo de verdad, no un
  // redo/undo de una ya existente) invalida el redo pendiente, mismo
  // comportamiento que cualquier editor de texto.
  property var redoStack: []
}

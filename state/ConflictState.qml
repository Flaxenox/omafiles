pragma Singleton
import QtQuick

// Estado de los seis diálogos de conflicto (renombrar/pegar/extraer/
// comprimir/renombrado en lote/soltar) -- cuarto singleton de la capa
// state/, mismo patrón validado con Selection/Clipboard/Undo. La lógica
// que decide cuándo abrirlos y qué hacer al confirmar sigue en
// logic/ConflictActions.qml (y en RenameOps/ClipboardOps/ArchiveActions/
// FileOps/DragDropOps para el caso sin conflicto).
QtObject {
  property var pendingRename: null // { oldPath, newPath }
  property bool renameConflictOpen: false

  property var pasteConflictNames: []
  property bool pasteConflictOpen: false

  property var pendingExtract: null // { entry, cmd }
  property var extractConflictNames: []
  property bool extractConflictOpen: false

  property var pendingCompress: null // { archiveName, cmd }
  property bool compressConflictOpen: false

  property var pendingBulkRename: null // [{ oldName, newName, oldPath, newPath }]
  property int bulkRenameInternalDupes: 0
  property int bulkRenameConflictCount: 0
  property bool bulkRenameConflictOpen: false

  // ---------- Arrastrar y soltar ----------
  // Deliberadamente separado del portapapeles de Ctrl+C/X/V (ver
  // state/ClipboardState.qml) -- un drag no debe pisar lo que el usuario
  // tenga copiado a mano. Interno (misma app) = mover; desde fuera (otra
  // app) = copiar, decidido por DragEvent.source (null si el drag viene
  // de fuera).
  property var dropPendingSources: []
  property string dropTargetDir: ""
  property bool dropIsMove: false
  property var dropConflictNames: []
  property bool dropConflictOpen: false
}

import "../Utils.js" as Utils
import QtQuick
import qs.Commons
import "../state"

// Arrastrar y soltar (dentro de la app, y desde/hacia otras) --
// decimonoveno componente extraído de Omafiles.qml.
Item {
  property Item root: null
  // conflictActions.startDropInto() es quien de verdad comprueba
  // conflictos -- handleFilesDropped() solo resuelve el DragEvent en sí
  // (aceptar/rechazar, mover vs copiar). runDrop() (la ejecución real del
  // mv/cp) vive en logic/ConflictActions.qml junto a dropCheckProc, quien
  // lo llama -- si se quedara aquí, DragDropOps y ConflictActions se
  // necesitarían mutuamente (dependencia circular, regla 5 del prompt de
  // arquitectura). Con el executor allí, la dependencia queda en un solo
  // sentido: DragDropOps -> ConflictActions.
  property Item conflictActions: null
  property Item selectionOps: null

  function urlToPath(url) {
    var s = String(url)
    if (s.indexOf("file://") === 0) s = s.substring(7)
    try { return decodeURIComponent(s) } catch (e) { return s }
  }

  // MimeData del/los ficheros que arranca a arrastrar la fila `index` --
  // si esa fila ya forma parte de una selección múltiple, arrastra toda la
  // selección (igual que Nautilus); si no, solo esa fila.
  function dragMimeDataFor(index) {
    var indices = (selectionOps.isSelected(index) && SelectionState.selectedIndices.length > 1) ? SelectionState.selectedIndices : [index]
    var paths = indices
      .filter(function (i) { return i >= 0 && i < NavState.visibleEntries.length })
      .map(function (i) { return Utils.joinPath(NavState.currentPath, NavState.visibleEntries[i].name) })
    var data = {}
    data["text/uri-list"] = paths.map(function (p) { return Util.fileUrl(p) }).join("\r\n")
    return data
  }

  // runDrop() (ejecuta el mv/cp real tras resolver un conflicto de soltar)
  // vive en logic/ConflictActions.qml -- ver el comentario junto a
  // `conflictActions` más arriba.

  function cancelDropConflict() {
    ConflictState.dropConflictOpen = false
    ConflictState.dropConflictNames = []
    ConflictState.dropPendingSources = []
    ConflictState.dropTargetDir = ""
  }

  // Llamado desde cada DropArea (fila de carpeta, marcador, unidad, fondo
  // de la lista) con el DragEvent real y la carpeta destino ya resuelta.
  function handleFilesDropped(drop, destDir) {
    if (ArchiveState.inArchive) { drop.accepted = false; return }
    if (!drop.hasUrls) { drop.accepted = false; return }
    var paths = drop.urls.map(function (u) { return urlToPath(u) }).filter(function (p) { return p.length > 0 })
    if (paths.length === 0) { drop.accepted = false; return }
    var isMove = drop.source !== null && drop.source !== undefined
    drop.accept(isMove ? Qt.MoveAction : Qt.CopyAction)
    conflictActions.startDropInto(destDir, paths, isMove)
  }
}

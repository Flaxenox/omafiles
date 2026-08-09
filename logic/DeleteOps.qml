import QtQuick
import "../state"

// Borrar (a la papelera, o permanente si ya se está viendo la papelera) --
// vigésimo tercer componente extraído de Omafiles.qml.
Item {
  property Item root: null
  property Item selectionOps: null

  function requestDelete() {
    if (ArchiveState.inArchive) return
    var names = selectionOps.selectedEntries().map(function (e) { return e.name })
    if (names.length === 0) return
    root.pendingDeleteNames = names
  }

  function confirmDelete() {
    var names = root.pendingDeleteNames
    root.pendingDeleteNames = []
    if (names.length === 0) return
    if (NavState.currentPath === Paths.trashDir) {
      // Borrado permanente NATIVO (Fase 13.C): FileOperations.remove en vez
      // de `rm -rf`/`rm -f`. No hay undo posible. TrashState.trashInfo (ver
      // trash-info.sh) sabe la raíz física real de cada ítem -- puede ser la
      // papelera de casa o la de cualquier otro disco montado, ya no se puede
      // asumir Paths.trashDir a secas. Por cada ítem se borra el fichero en
      // <raíz>/files/<n> (recursivo) y su <raíz>/info/<n>.trashinfo, ambos
      // con ignoreMissing (= `rm -f`: que falte no es error).
      var paths = []
      names.forEach(function (n) {
        var info = TrashState.trashInfo[n]
        if (!info) return
        paths.push(info.trashRoot + "/files/" + n)
        paths.push(info.trashRoot + "/info/" + n + ".trashinfo")
      })
      if (paths.length > 0) root.removeFiles(paths, "", true)
    } else {
      // Enviar a papelera NATIVO (Fase 13.D): FileOperations.trash
      // (QFile::moveToTrash, XDG Trash) en vez de `gio trash`. Rutas
      // originales absolutas capturadas AQUÍ (no dentro de los closures de
      // más abajo) -- NavState.currentPath puede haber cambiado para cuando
      // el usuario pulse deshacer, mucho más tarde.
      var origPaths = names.map(function (n) { return root.joinPath(NavState.currentPath, n) })
      var label = names.length === 1 ? "delete \"" + names[0] + "\"" : "delete " + names.length + " items"
      root.trashFiles(origPaths, "", function () {
        // El undo solo se registra si el envío confirmó éxito. Deshacer =
        // restaurar POR RUTA ORIGINAL (Fase 13.E, restoreByOrigPath): busca
        // en TODAS las papeleras activas el .trashinfo cuya ruta original
        // coincide, así funciona igual borre desde donde borre -- y sirve
        // aunque el usuario deshaga mucho después sin haber abierto nunca la
        // Papelera.
        root.pushUndo(label, function () {
          return root.restoreFiles(origPaths, "")
        }, function () {
          return root.trashFiles(origPaths, "")
        })
      })
    }
  }
}

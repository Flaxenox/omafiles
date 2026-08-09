import QtQuick
import qs.Commons
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
    if (NavState.currentPath === root.trashDir) {
      // Borrado permanente NATIVO (Fase 13.C): FileOperations.remove en vez
      // de `rm -rf`/`rm -f`. No hay undo posible. TrashState.trashInfo (ver
      // trash-info.sh) sabe la raíz física real de cada ítem -- puede ser la
      // papelera de casa o la de cualquier otro disco montado, ya no se puede
      // asumir root.trashDir a secas. Por cada ítem se borra el fichero en
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
      var quoted = names.map(function (n) { return Util.shellQuote(root.joinPath(NavState.currentPath, n)) }).join(" ")
      // Rutas originales absolutas capturadas AQUÍ (no dentro de los
      // closures de más abajo) -- NavState.currentPath puede haber cambiado
      // para cuando el usuario pulse deshacer, mucho más tarde.
      var origPaths = names.map(function (n) { return root.joinPath(NavState.currentPath, n) })
      var label = names.length === 1 ? "delete \"" + names[0] + "\"" : "delete " + names.length + " items"
      var deleteCmd = "gio trash -- " + quoted
      root.runAction(deleteCmd, "", function () {
        // Solo se registra el undo si el borrado a papelera confirmó éxito
        // -- antes se registraba siempre, así que un "gio trash" fallido
        // (permiso denegado, etc.) dejaba un undo que restauraba algo que
        // nunca llegó a borrarse.
        root.pushUndo(label, function () {
          // restore-by-origpath.sh busca en TODAS las papeleras activas
          // (no solo la de casa) el .trashinfo cuya ruta original
          // coincide, así funciona igual borre desde donde borre --
          // TrashState.trashInfo (usado por el botón "Restore" normal) no
          // sirve aquí porque solo se rellena mientras se está VIENDO
          // la Papelera, y el usuario puede deshacer mucho después sin
          // haber entrado nunca en ella.
          var restoreCmds = origPaths.map(function (p) {
            return "bash " + Util.shellQuote(root.pluginDir + "/restore-by-origpath.sh") + " " + Util.shellQuote(p)
          })
          return root.runAction(root.chainCmds(restoreCmds))
        }, function () {
          return root.runAction(deleteCmd)
        })
      })
    }
  }
}

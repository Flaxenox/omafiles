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
    if (root.currentPath === root.trashDir) {
      // Borrado permanente -- no hay undo posible. TrashState.trashInfo (ver
      // trash-info.sh) sabe la raíz física real de cada ítem -- puede
      // ser la papelera de casa o la de cualquier otro disco montado,
      // ya no se puede asumir root.trashDir a secas como antes de
      // agregar varias papeleras.
      var cmds = names.map(function (n) {
        var info = TrashState.trashInfo[n]
        if (!info) return "true"
        return "rm -rf -- " + Util.shellQuote(info.trashRoot + "/files/" + n) +
          "; rm -f -- " + Util.shellQuote(info.trashRoot + "/info/" + n + ".trashinfo")
      })
      root.runAction(root.chainCmds(cmds))
    } else {
      var quoted = names.map(function (n) { return Util.shellQuote(root.joinPath(root.currentPath, n)) }).join(" ")
      // Rutas originales absolutas capturadas AQUÍ (no dentro de los
      // closures de más abajo) -- root.currentPath puede haber cambiado
      // para cuando el usuario pulse deshacer, mucho más tarde.
      var origPaths = names.map(function (n) { return root.joinPath(root.currentPath, n) })
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

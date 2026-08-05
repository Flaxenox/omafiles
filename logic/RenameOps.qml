import QtQuick
import qs.Commons
import "../state"

// Renombrar / nueva carpeta / nuevo fichero, con su undo -- decimoséptimo
// componente extraído de Omafiles.qml. Mismo patrón que FileOps: sin
// Process propio, todo pasa por los wrappers de root
// (root.runAction/root.pushUndo).
Item {
  property Item root: null

  function startRename(index) {
    if (ArchiveState.inArchive) return
    if (index < 0 || index >= root.visibleEntries.length) return
    EditModeState.creatingFolder = false
    EditModeState.creatingFile = false
    EditModeState.renamingIndex = index
  }

  function runPendingRename(overwrite) {
    var r = ConflictState.pendingRename
    ConflictState.pendingRename = null
    ConflictState.renameConflictOpen = false
    if (!r) return
    var oldName = r.oldPath.substring(r.oldPath.lastIndexOf("/") + 1)
    // Igual que en makeLinkFor: el undo solo se registra si el "mv" de
    // verdad ocurrió. Antes se registraba siempre, incluso cuando runAction
    // lo descartaba por haber otra acción en curso (el rename ya se había
    // dado por hecho en la UI -- el input se cerraba igual).
    var renameCmd = "mv " + (overwrite ? "-f" : "-n") + " -- " + Util.shellQuote(r.oldPath) + " " + Util.shellQuote(r.newPath)
    root.runAction(renameCmd, undefined, function () {
      root.pushUndo("rename to \"" + oldName + "\"", function () {
        return root.runAction("mv -n -- " + Util.shellQuote(r.newPath) + " " + Util.shellQuote(r.oldPath))
      }, function () {
        return root.runAction(renameCmd)
      })
    })
  }

  function cancelPendingRename() {
    ConflictState.pendingRename = null
    ConflictState.renameConflictOpen = false
  }

  function startNewFolder() {
    if (ArchiveState.inArchive) return
    EditModeState.renamingIndex = -1
    root.searching = false
    EditModeState.creatingFile = false
    EditModeState.creatingFolder = true
  }

  function startNewFile() {
    if (ArchiveState.inArchive) return
    EditModeState.renamingIndex = -1
    root.searching = false
    EditModeState.creatingFolder = false
    EditModeState.creatingFile = true
  }

  // commitNewFile()/commitNewFolder() (comprobar si ya existe algo con
  // ese nombre) viven en logic/ConflictActions.qml, junto a
  // newFileCheckProc/newFolderCheckProc -- mismo patrón que commitRename/
  // renameCheckProc. Estas dos son la ejecución real (con overwrite=true
  // si el usuario confirmó sobrescribir en el diálogo de conflicto).
  function runPendingNewFile(overwrite) {
    var pending = ConflictState.pendingNewFile
    ConflictState.pendingNewFile = null
    ConflictState.newFileConflictOpen = false
    if (!pending) return
    // overwrite: -rf primero (puede ser una carpeta entera, no solo un
    // fichero) y luego touch -- coherente con el "-f" que ya usan
    // paste/drop al sobrescribir (fuerza sin pasar por la papelera).
    var newFileCmd = (overwrite ? "rm -rf -- " + Util.shellQuote(pending.path) + " && " : "")
      + "touch -- " + Util.shellQuote(pending.path)
    root.runAction(newFileCmd, undefined, function () {
      // gio trash en vez de rm: si el usuario ya escribió algo antes de
      // deshacer, va a la papelera en vez de perderse sin recuperación.
      // No intenta restaurar lo que hubiera sobrescrito -- mismo límite
      // que ya tiene pegar/soltar con overwrite.
      root.pushUndo("new file \"" + pending.name + "\"", function () {
        return root.runAction("gio trash -- " + Util.shellQuote(pending.path))
      }, function () {
        return root.runAction(newFileCmd)
      })
    })
  }

  function cancelPendingNewFile() {
    ConflictState.pendingNewFile = null
    ConflictState.newFileConflictOpen = false
  }

  function runPendingNewFolder(overwrite) {
    var pending = ConflictState.pendingNewFolder
    ConflictState.pendingNewFolder = null
    ConflictState.newFolderConflictOpen = false
    if (!pending) return
    var newFolderCmd = (overwrite ? "rm -rf -- " + Util.shellQuote(pending.path) + " && " : "")
      + "mkdir -p -- " + Util.shellQuote(pending.path)
    root.runAction(newFolderCmd, undefined, function () {
      // rmdir en vez de rm -rf: si el usuario ya metió algo dentro antes de
      // deshacer, falla en vez de borrar contenido a lo tonto. No
      // intenta restaurar lo que hubiera sobrescrito.
      root.pushUndo("new folder \"" + pending.name + "\"", function () {
        return root.runAction("rmdir -- " + Util.shellQuote(pending.path))
      }, function () {
        return root.runAction(newFolderCmd)
      })
    })
  }

  function cancelPendingNewFolder() {
    ConflictState.pendingNewFolder = null
    ConflictState.newFolderConflictOpen = false
  }
}

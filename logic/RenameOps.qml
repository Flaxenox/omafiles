import QtQuick
import qs.Commons
import "../state"
import "../services"

// Renombrar / nueva carpeta / nuevo fichero, con su undo -- decimoséptimo
// componente extraído de Omafiles.qml. Mismo patrón que FileOps: sin
// Process propio, todo pasa por los wrappers de root
// (actionEngine.runAction/actionEngine.pushUndo).
//
// Fase 7 (josema): "nueva carpeta" (caso común, sin sobrescribir) es la
// PRIMERA operación cableada al backend nativo -- crea con
// FileOperations.mkdir en vez de "mkdir -p" por shell. El resto de
// operaciones sigue en el motor de acciones shell hasta un escalón
// posterior. El undo se mantiene con rmdir (falla si el usuario ya metió
// algo dentro, a propósito).
Item {
  id: renameOps
  property Item root: null
  property Item actionEngine: null
  property Item navController: null


  // Rutas de "nueva carpeta" nativa en vuelo -> nombre. El undo se registra
  // solo cuando FileOperations.mkdir termina CON ÉXITO (ver la Connections
  // de abajo), no antes ni en un redo. Mismo patrón que Persistence con
  // JsonStore (Connections declarativa sobre el singleton de services).
  property var _nativeMkdirPending: ({})

  function startRename(index) {
    if (ArchiveState.inArchive) return
    if (index < 0 || index >= NavState.visibleEntries.length) return
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
    actionEngine.runAction(renameCmd, undefined, function () {
      actionEngine.pushUndo("rename to \"" + oldName + "\"", function () {
        return actionEngine.runAction("mv -n -- " + Util.shellQuote(r.newPath) + " " + Util.shellQuote(r.oldPath))
      }, function () {
        return actionEngine.runAction(renameCmd)
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
    NavState.searching = false
    EditModeState.creatingFile = false
    EditModeState.creatingFolder = true
  }

  function startNewFile() {
    if (ArchiveState.inArchive) return
    EditModeState.renamingIndex = -1
    NavState.searching = false
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
    actionEngine.runAction(newFileCmd, undefined, function () {
      // gio trash en vez de rm: si el usuario ya escribió algo antes de
      // deshacer, va a la papelera en vez de perderse sin recuperación.
      // No intenta restaurar lo que hubiera sobrescrito -- mismo límite
      // que ya tiene pegar/soltar con overwrite.
      actionEngine.pushUndo("new file \"" + pending.name + "\"", function () {
        return actionEngine.runAction("gio trash -- " + Util.shellQuote(pending.path))
      }, function () {
        return actionEngine.runAction(newFileCmd)
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
    if (overwrite) {
      // Sobrescribir un nombre ya existente (caso raro): implica un rm -rf
      // destructivo, se queda en el motor de acciones shell probado -- Fase
      // 7 solo cablea el mkdir del caso común al backend nativo.
      var cmd = "rm -rf -- " + Util.shellQuote(pending.path) + " && mkdir -p -- " + Util.shellQuote(pending.path)
      actionEngine.runAction(cmd, undefined, function () {
        actionEngine.pushUndo("new folder \"" + pending.name + "\"", function () {
          return actionEngine.runAction("rmdir -- " + Util.shellQuote(pending.path))
        }, function () {
          return actionEngine.runAction(cmd)
        })
      })
      return
    }
    // Caso común: mkdir NATIVO (Fase 7). El undo se registra al terminar con
    // éxito (ver la Connections de abajo).
    renameOps._nativeMkdirPending[pending.path] = pending.name
    FileOperations.mkdir(pending.path)
  }

  // Cierra el ciclo de la "nueva carpeta" nativa: refresca y registra el
  // undo cuando mkdir termina bien. Declarativa como Persistence con
  // JsonStore.
  Connections {
    target: FileOperations
    function onFinished(op, path) {
      if (op !== "mkdir") return
      // Refresco inmediato (como actionProc.onFinished): el panel activo lo
      // cubre el watcher, pero refreshTick refresca también los de fondo que
      // muestren esta misma carpeta.
      navController.refresh()
      NavState.refreshTick += 1
      var name = renameOps._nativeMkdirPending[path]
      if (name === undefined) return // redo u otro mkdir: no re-registrar
      delete renameOps._nativeMkdirPending[path]
      actionEngine.pushUndo("new folder \"" + name + "\"", function () {
        // rmdir (no rm -rf): si ya hay algo dentro, falla en vez de borrarlo.
        return actionEngine.runAction("rmdir -- " + Util.shellQuote(path))
      }, function () {
        FileOperations.mkdir(path) // redo: sin re-registrar
        return true
      })
    }
    function onError(op, path, message) {
      // El aviso al usuario ya lo dio el adaptador (Notifier). Solo limpiar.
      if (op === "mkdir" && renameOps._nativeMkdirPending[path] !== undefined)
        delete renameOps._nativeMkdirPending[path]
    }
  }

  function cancelPendingNewFolder() {
    ConflictState.pendingNewFolder = null
    ConflictState.newFolderConflictOpen = false
  }
}

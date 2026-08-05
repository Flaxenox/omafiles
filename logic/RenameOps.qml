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
    if (root.inArchive) return
    if (index < 0 || index >= root.visibleEntries.length) return
    root.creatingFolder = false
    root.creatingFile = false
    root.renamingIndex = index
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
    if (root.inArchive) return
    root.renamingIndex = -1
    root.searching = false
    root.creatingFile = false
    root.creatingFolder = true
  }

  function startNewFile() {
    if (root.inArchive) return
    root.renamingIndex = -1
    root.searching = false
    root.creatingFolder = false
    root.creatingFile = true
  }

  function commitNewFile(name) {
    root.creatingFile = false
    name = name.trim()
    if (!name) return
    var path = root.joinPath(root.currentPath, name)
    // Comprobación de existencia ANTES del touch -- bug real corregido
    // aquí: touch es idempotente (éxito silencioso sobre un fichero que
    // ya existía), así que sin este guard un "New file" con un nombre en
    // conflicto no creaba nada nuevo pero SÍ registraba un undo de "new
    // file" -- un Ctrl+Z posterior mandaba a la papelera el fichero
    // PREEXISTENTE de verdad (con su contenido real), no uno vacío recién
    // creado. Recuperable vía papelera, pero sorprendente y no lo que
    // pedía el README (conflictos tratados, no ignorados en silencio).
    var newFileCmd = "if [ -e " + Util.shellQuote(path) + " ]; then echo " + Util.shellQuote("\"" + name + "\" already exists") + " >&2; exit 1; fi; touch -- " + Util.shellQuote(path)
    root.runAction(newFileCmd, undefined, function () {
      // gio trash en vez de rm: si el usuario ya escribió algo antes de
      // deshacer, va a la papelera en vez de perderse sin recuperación.
      root.pushUndo("new file \"" + name + "\"", function () {
        return root.runAction("gio trash -- " + Util.shellQuote(path))
      }, function () {
        return root.runAction(newFileCmd)
      })
    })
  }

  function commitNewFolder(name) {
    root.creatingFolder = false
    root.creatingFile = false
    name = name.trim()
    if (!name) return
    var path = root.joinPath(root.currentPath, name)
    // Mismo motivo que commitNewFile: "mkdir -p" no falla si la carpeta
    // ya existe, y sin este guard un Ctrl+Z posterior podía rmdir una
    // carpeta preexistente (vacía) que no tenía nada que ver con esta
    // acción.
    var newFolderCmd = "if [ -e " + Util.shellQuote(path) + " ]; then echo " + Util.shellQuote("\"" + name + "\" already exists") + " >&2; exit 1; fi; mkdir -p -- " + Util.shellQuote(path)
    root.runAction(newFolderCmd, undefined, function () {
      // rmdir en vez de rm -rf: si el usuario ya metió algo dentro antes de
      // deshacer, falla en vez de borrar contenido a lo tonto.
      root.pushUndo("new folder \"" + name + "\"", function () {
        return root.runAction("rmdir -- " + Util.shellQuote(path))
      }, function () {
        return root.runAction(newFolderCmd)
      })
    })
  }
}

import QtQuick
import qs.Commons
import "../state"
import "../services"

// Comprobación de conflicto antes de ejecutar una acción que puede
// sobrescribir algo -- decimonoveno componente extraído de Omafiles.qml,
// y el primero que toca una acción que de verdad mueve/sobrescribe
// ficheros del usuario (a diferencia de Persistence/PreviewLoader/
// PropertiesLoader, que solo leían). Por eso se ha ido añadiendo una
// función a la vez, probada a mano cada una, en vez de mover el bloque
// entero de golpe.
//
// commitRename() se queda aquí junto a renameCheckProc porque es lo único
// que lo lanza -- pero runPendingRename() (el "mv" de verdad, con su
// undo) se queda en Omafiles.qml sin tocar: además de responder al
// resultado automático del check ("0 conflictos" -> renombra ya), lo
// llama directamente ConflictResolveDialog.onConfirmed, y moverlo aquí
// solo habría cambiado de sitio ese único call site sin unir nada más.
Item {
  property Item root: null
  property Item archiveActions: null
  property Item fileOps: null
  property Item renameOps: null
  property Item clipboardOps: null
  property Item selectionOps: null
  property Item bookmarkOps: null

  function paste() {
    if (ArchiveState.inArchive) return
    if (ClipboardState.clipboardPaths.length === 0) {
      // Nada copiado desde DENTRO de Omafiles -- probar el portapapeles
      // del sistema (copiar en Nautilus/el navegador/un chat/etc. y pegar
      // aquí). Se trata siempre como "copy", nunca "cut": un
      // text/uri-list suelto no lleva esa distinción (a diferencia del
      // x-special/gnome-copied-files propio de GTK, que no todas las apps
      // que copian rutas escriben).
      systemClipboardReadProc.start(["wl-paste", "-t", "text/uri-list"])
      return
    }
    var destPaths = ClipboardState.clipboardPaths.map(function (src) {
      var name = src.substring(src.lastIndexOf("/") + 1)
      return root.joinPath(NavState.currentPath, name)
    })
    var checkCmd = destPaths.map(function (p) {
      return "test -e " + Util.shellQuote(p) + " && printf '%s\\n' " + Util.shellQuote(p)
    }).join("; ")
    pasteCheckProc.start(["bash", "-c", checkCmd])
  }

  function startDropInto(destDir, sourcePaths, isMove) {
    if (!destDir) return
    sourcePaths = sourcePaths.filter(function (src) {
      var srcDir = src.substring(0, src.lastIndexOf("/"))
      // Evita soltar sobre la propia carpeta de origen (no-op) o dentro de
      // sí mismo si el fichero arrastrado es en realidad una carpeta.
      return src !== destDir && srcDir !== destDir && (destDir + "/").indexOf(src + "/") !== 0
    })
    if (sourcePaths.length === 0) return
    ConflictState.dropPendingSources = sourcePaths
    ConflictState.dropTargetDir = destDir
    ConflictState.dropIsMove = isMove
    var destPaths = sourcePaths.map(function (src) {
      return root.joinPath(destDir, src.substring(src.lastIndexOf("/") + 1))
    })
    var checkCmd = destPaths.map(function (p) {
      return "test -e " + Util.shellQuote(p) + " && printf '%s\\n' " + Util.shellQuote(p)
    }).join("; ")
    dropCheckProc.start(["bash", "-c", checkCmd])
  }

  function compressSelected() {
    if (ArchiveState.inArchive) return
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return
    var archiveName = entries.length === 1
      ? entries[0].name.replace(/\/$/, "") + ".zip"
      : "selected-files.zip"
    var names = entries.map(function (e) { return Util.shellQuote(e.name) }).join(" ")
    // "rm -f" antes del zip: si el usuario confirma sobrescribir un
    // archiveName ya existente, que sea un reemplazo real -- sin el rm,
    // "zip -r" AÑADE/actualiza entradas dentro del zip existente en vez de
    // sustituirlo, así que confirmar "overwrite" no dejaba en realidad un
    // zip limpio con solo lo seleccionado ahora.
    // "./" delante del nombre del zip + "--" delante de la lista: un
    // archivo real llamado, por ejemplo, "-rf" (nombre válido en Linux) se
    // interpretaría como flags de zip en vez de como nombre de fichero.
    // zip no admite "--" antes del propio nombre del zip (error "can't use
    // -- before archive name"), de ahí el "./" en su lugar.
    var cmd = "cd -- " + Util.shellQuote(NavState.currentPath) + " && rm -f -- " + Util.shellQuote(archiveName)
      + " && zip -r -q " + Util.shellQuote("./" + archiveName) + " -- " + names
    ConflictState.pendingCompress = { archiveName: archiveName, cmd: cmd }
    compressCheckProc.start(["bash", "-c", "test -e " + Util.shellQuote(root.joinPath(NavState.currentPath, archiveName)) + " && echo 1 || echo 0"])
  }

  function commitBulkRename() {
    var entries = selectionOps.selectedEntries()
    DialogsState.bulkRenameOpen = false
    if (entries.length === 0) return
    var pattern = DialogsState.bulkRenamePattern
    bookmarkOps.addBulkRenameHistory(pattern)
    var pairs = entries.map(function (e, i) {
      var ext = e.type === "dir" ? "" : (root.extOf(e.name) ? "." + root.extOf(e.name) : "")
      var base = ext ? e.name.slice(0, -ext.length) : e.name
      var newName = pattern.replace(/\{name\}/g, base).replace(/\{ext\}/g, ext).replace(/\{n\}/g, String(i + 1))
      return {
        oldName: e.name, newName: newName,
        oldPath: root.joinPath(NavState.currentPath, e.name),
        newPath: root.joinPath(NavState.currentPath, newName)
      }
    })
    ConflictState.pendingBulkRename = pairs
    // Antes esto usaba "mv -n" a ciegas: un patrón que produce un nombre ya
    // existente (o que dos ítems de la propia selección acaben con el
    // mismo nombre nuevo) hacía que mv -n no tocara ESE ítem en concreto,
    // sin ningún aviso de cuál se había quedado sin renombrar. Ahora se
    // comprueban antes los conflictos con lo que ya existe en disco...
    var targetCounts = {}
    pairs.forEach(function (p) {
      if (p.newName === p.oldName) return
      targetCounts[p.newPath] = (targetCounts[p.newPath] || 0) + 1
    })
    // ...y también los conflictos DENTRO de la propia selección (dos ítems
    // que el patrón deja con el mismo nombre nuevo).
    ConflictState.bulkRenameInternalDupes = Object.keys(targetCounts).filter(function (k) { return targetCounts[k] > 1 }).length
    var checkCmd = pairs.map(function (p) {
      if (p.newName === p.oldName) return "true"
      return "test -e " + Util.shellQuote(p.newPath) + " && printf '%s\\n' " + Util.shellQuote(p.newName)
    }).join("; ")
    bulkRenameCheckProc.start(["bash", "-c", checkCmd])
  }

  function extractHere(entry) {
    var ext = root.extOf(entry.name)
    var path = Util.shellQuote(root.joinPath(NavState.currentPath, entry.name))
    var dir = Util.shellQuote(NavState.currentPath)
    var cmd, listCmd
    // Todas fuerzan sobrescritura (-o/-y/-o+) -- necesario para que
    // runPendingExtract pueda de verdad sobrescribir tras confirmar el
    // aviso de conflicto de abajo. listCmd usa el modo "lista plana" de
    // cada herramienta (nombre por línea, sin cabecera) para saber qué se
    // pisaría, sin necesidad de parsear tablas.
    if (ext === "zip") { cmd = "unzip -o -q " + path + " -d " + dir; listCmd = "unzip -Z1 -- " + path }
    else if (ext === "7z") { cmd = "7z x -y " + path + " -o" + dir; listCmd = "7z l -ba -slt -- " + path + " | grep '^Path = ' | sed 's/^Path = //'" }
    else if (ext === "rar") { cmd = "unrar x -o+ " + path + " " + dir + "/"; listCmd = "unrar lb -- " + path }
    // Sin "--" a propósito, a diferencia de las otras tres -- con "tf"
    // (forma corta agrupada de -t -f) tar toma el token SIGUIENTE como
    // argumento directo de -f, así que un "--" ahí se interpreta como el
    // propio nombre de fichero a abrir y tar falla con "--: No such file or
    // directory". Bug real: esto hacía que la comprobación de conflictos
    // SIEMPRE fallara en silencio para tar/tar.gz/tar.bz2/tar.xz (listCmd
    // no devolvía nada -> 0 conflictos detectados siempre), aunque zip/7z/
    // rar no se vieran afectados.
    else if (root.tarExt.indexOf(ext) >= 0) { cmd = "tar xf " + path + " -C " + dir; listCmd = "tar tf " + path }
    else return
    // Antes esto sobrescribía sin preguntar, a diferencia de pegar/soltar/
    // renombrar (que sí comprueban conflictos). Antes de extraer, se lista
    // el contenido del archivo y se comprueba si algún elemento de primer
    // nivel ya existe en la carpeta actual.
    ConflictState.pendingExtract = { entry: entry, cmd: cmd }
    extractListProc.start(["bash", "-c", listCmd])
  }

  function commitRename(newName) {
    var index = EditModeState.renamingIndex
    EditModeState.renamingIndex = -1
    // Defensa en profundidad: startRename() ya bloquea EMPEZAR un
    // renombrado dentro de un archivo, pero no cubre el caso de empezar a
    // renombrar FUERA, no confirmar, y entrar en un .zip mientras tanto --
    // renamingIndex se queda apuntando a un índice que ahora pertenece a
    // una entrada del archivo, y sin este guard commitRename ejecutaría mv
    // sobre currentPath/<nombre-del-zip>, que puede coincidir por
    // casualidad con un fichero real.
    if (ArchiveState.inArchive) return
    if (index < 0 || index >= NavState.visibleEntries.length) return
    var oldName = NavState.visibleEntries[index].name
    newName = newName.trim()
    if (!newName || newName === oldName) return
    var oldPath = root.joinPath(NavState.currentPath, oldName)
    var newPath = root.joinPath(NavState.currentPath, newName)
    ConflictState.pendingRename = { oldPath: oldPath, newPath: newPath }
    renameCheckProc.start(["bash", "-c", "test -e " + Util.shellQuote(newPath) + " && echo 1 || echo 0"])
  }

  ProcessRunner {
    id: renameCheckProc
    onFinished: function (result) {
      if (result.stdout.trim() === "1") ConflictState.renameConflictOpen = true
      else renameOps.runPendingRename(false)
    }
  }

  // Comprobación de existencia ANTES de crear -- bug real corregido aquí
  // (josema, 2026-08-05): touch/mkdir -p son idempotentes (éxito
  // silencioso sobre algo que ya existía), así que sin este guard "New
  // file"/"New folder" con un nombre en conflicto no creaba nada nuevo
  // pero SÍ registraba un undo -- un Ctrl+Z posterior mandaba a la
  // papelera el ítem PREEXISTENTE de verdad. Ahora, en vez de fallar en
  // silencio (notify-send fácil de no ver), se ofrece el mismo diálogo
  // Overwrite/Cancel que ya usa renombrar.
  function commitNewFile(name) {
    EditModeState.creatingFile = false
    name = name.trim()
    if (!name) return
    var path = root.joinPath(NavState.currentPath, name)
    ConflictState.pendingNewFile = { path: path, name: name }
    newFileCheckProc.start(["bash", "-c", "test -e " + Util.shellQuote(path) + " && echo 1 || echo 0"])
  }

  ProcessRunner {
    id: newFileCheckProc
    onFinished: function (result) {
      if (result.stdout.trim() === "1") ConflictState.newFileConflictOpen = true
      else renameOps.runPendingNewFile(false)
    }
  }

  function commitNewFolder(name) {
    EditModeState.creatingFolder = false
    EditModeState.creatingFile = false
    name = name.trim()
    if (!name) return
    var path = root.joinPath(NavState.currentPath, name)
    ConflictState.pendingNewFolder = { path: path, name: name }
    newFolderCheckProc.start(["bash", "-c", "test -e " + Util.shellQuote(path) + " && echo 1 || echo 0"])
  }

  ProcessRunner {
    id: newFolderCheckProc
    onFinished: function (result) {
      if (result.stdout.trim() === "1") ConflictState.newFolderConflictOpen = true
      else renameOps.runPendingNewFolder(false)
    }
  }

  ProcessRunner {
    id: systemClipboardReadProc
    onFinished: function (result) {
      // Bug real: RFC 2483 exige CRLF entre URIs de un text/uri-list, y
      // las apps GTK reales (Nautilus, selectores de fichero,
      // Firefox...) lo escriben así -- sin quitar el "\r" que queda
      // pegado al final de cada línea, decodeURIComponent lo dejaba
      // colado en el path, pasteCheckProc.test -e nunca lo encontraba, y
      // pegar desde fuera de Omafiles fallaba en silencio sin ningún
      // aviso.
      var uris = String(result.stdout || "").split("\n").map(function (l) { return l.replace(/\r$/, "") }).filter(function (l) { return l.length > 0 })
      var paths = uris.map(function (u) {
        return u.indexOf("file://") === 0 ? decodeURIComponent(u.substring(7)) : ""
      }).filter(function (p) { return p.length > 0 })
      // Vacío = portapapeles del sistema sin uris (o sin nada) -- no hay
      // nada que avisar, paste() ya no hacía nada tampoco antes en este
      // caso.
      if (paths.length === 0) return
      ClipboardState.clipboardPaths = paths
      ClipboardState.clipboardMode = "copy"
      paste()
    }
  }

  ProcessRunner {
    id: extractListProc
    onFinished: function (result) {
      var top = {}
      String(result.stdout || "").split("\n").forEach(function (line) {
        var name = line.replace(/\/+$/, "")
        if (!name) return
        var slash = name.indexOf("/")
        top[slash >= 0 ? name.substring(0, slash) : name] = true
      })
      var names = Object.keys(top)
      if (names.length === 0) { archiveActions.runPendingExtract(); return }
      var checkCmd = names.map(function (n) {
        return "test -e " + Util.shellQuote(root.joinPath(NavState.currentPath, n)) + " && printf '%s\\n' " + Util.shellQuote(n)
      }).join("; ")
      extractConflictCheckProc.start(["bash", "-c", checkCmd])
    }
  }

  ProcessRunner {
    id: extractConflictCheckProc
    onFinished: function (result) {
      var conflicts = String(result.stdout || "").split("\n").filter(function (l) { return l.length > 0 })
      if (conflicts.length === 0) {
        archiveActions.runPendingExtract()
      } else {
        ConflictState.extractConflictNames = conflicts
        ConflictState.extractConflictOpen = true
      }
    }
  }

  ProcessRunner {
    id: bulkRenameCheckProc
    onFinished: function (result) {
      var conflicts = String(result.stdout || "").split("\n").filter(function (l) { return l.length > 0 })
      var total = conflicts.length + ConflictState.bulkRenameInternalDupes
      if (total === 0) {
        fileOps.runPendingBulkRename()
      } else {
        ConflictState.bulkRenameConflictCount = total
        ConflictState.bulkRenameConflictOpen = true
      }
    }
  }

  ProcessRunner {
    id: compressCheckProc
    onFinished: function (result) {
      if (result.stdout.trim() === "1") ConflictState.compressConflictOpen = true
      else archiveActions.runPendingCompress()
    }
  }

  ProcessRunner {
    id: dropCheckProc
    onFinished: function (result) {
      var conflicts = String(result.stdout || "").split("\n").filter(function (l) { return l.length > 0 })
      if (conflicts.length === 0) {
        runDrop("all")
      } else {
        ConflictState.dropConflictNames = conflicts.map(function (p) { return p.substring(p.lastIndexOf("/") + 1) })
        ConflictState.dropConflictOpen = true
      }
    }
  }

  // Ficheros soltados sobre `destDir` (una fila de carpeta, un marcador,
  // una unidad, o el fondo de la lista = la carpeta abierta ahora mismo).
  // `isMove` viene de DragEvent.source !== null (arrastre interno) --
  // arrastres que vienen de fuera siempre copian, nunca mueven el origen.
  // mode: "all" (sin conflictos) | "overwrite" | "skip". Vivía en
  // logic/DragDropOps.qml -- movido aquí para romper una dependencia
  // circular (DragDropOps necesitaba conflictActions para comprobar
  // conflictos, y conflictActions necesitaba dragDropOps solo para esto).
  function runDrop(mode) {
    var conflictSet = {}
    ConflictState.dropConflictNames.forEach(function (n) { conflictSet[n] = true })
    var sources = ConflictState.dropPendingSources.filter(function (src) {
      if (mode !== "skip") return true
      var name = src.substring(src.lastIndexOf("/") + 1)
      return !conflictSet[name]
    })
    ConflictState.dropConflictOpen = false
    ConflictState.dropConflictNames = []
    if (sources.length > 0) {
      var destDir = ConflictState.dropTargetDir
      var isMove = ConflictState.dropIsMove
      var pairs = sources.map(function (src) {
        var name = src.substring(src.lastIndexOf("/") + 1)
        return { src: src, dest: root.joinPath(destDir, name) }
      })
      var busyVerb = isMove ? "Moving " : "Copying "
      var busyLabel = pairs.length === 1
        ? busyVerb + "\"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\"…"
        : busyVerb + pairs.length + " items…"
      if (!isMove) {
        // Copia NATIVA (Fase 13.A): FileOperations.copy en vez de `cp -r`.
        root.copyFiles(pairs, busyLabel, mode === "overwrite")
      } else {
        // Mover sigue en shell hasta 13.B (con su undo).
        var noClobber = mode !== "overwrite"
        var cmds = pairs.map(function (p) {
          return "mv " + (noClobber ? "-n" : "-f") + " -- " + Util.shellQuote(p.src) + " " + Util.shellQuote(p.dest)
        })
        var dropMoveCmd = root.chainCmds(cmds)
        root.startCopyProgress(pairs.map(function (p) { return p.src }), pairs.map(function (p) { return p.dest }))
        root.runAction(dropMoveCmd, busyLabel, function () {
          var label = pairs.length === 1
            ? "move \"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\""
            : "move " + pairs.length + " items"
          root.pushUndo(label, function () {
            var undoCmds = pairs.map(function (p) {
              return "mv -n -- " + Util.shellQuote(p.dest) + " " + Util.shellQuote(p.src)
            })
            return root.runAction(root.chainCmds(undoCmds))
          }, function () {
            return root.runAction(dropMoveCmd)
          })
        })
      }
    }
    ConflictState.dropPendingSources = []
    ConflictState.dropTargetDir = ""
  }

  ProcessRunner {
    id: pasteCheckProc
    onFinished: function (result) {
      var conflicts = String(result.stdout || "").split("\n").filter(function (l) { return l.length > 0 })
      if (conflicts.length === 0) {
        clipboardOps.runPaste("all")
      } else {
        ConflictState.pasteConflictNames = conflicts.map(function (p) { return p.substring(p.lastIndexOf("/") + 1) })
        ConflictState.pasteConflictOpen = true
      }
    }
  }
}

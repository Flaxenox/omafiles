import QtQuick
import qs.Commons
import "../state"
import "../services"

// Copiar/cortar/pegar (portapapeles interno + sincronizado con
// wl-copy/wl-paste del sistema) -- decimoctavo componente extraído de
// Omafiles.qml.
Item {
  property Item root: null
  property Item selectionOps: null

  function copySelected() {
    if (ArchiveState.inArchive) return
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return
    ClipboardState.clipboardPaths = entries.map(function (e) { return root.joinPath(NavState.currentPath, e.name) })
    ClipboardState.clipboardMode = "copy"
    syncClipboardToSystem()
  }

  function cutSelected() {
    if (ArchiveState.inArchive) return
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return
    ClipboardState.clipboardPaths = entries.map(function (e) { return root.joinPath(NavState.currentPath, e.name) })
    ClipboardState.clipboardMode = "cut"
    syncClipboardToSystem()
  }

  // Antes clipboardPaths era solo interno -- copiar en Omafiles y pegar
  // en otra app (o al revés) no funcionaba. text/uri-list es el tipo MIME
  // más ampliamente reconocido (gestores de archivos, navegadores, apps
  // de chat...) -- wl-copy solo puede servir un tipo por invocación, así
  // que se prioriza compatibilidad amplia sobre poder distinguir cut/copy
  // de cara a OTRAS apps (Omafiles sí distingue cut/copy para sus propias
  // acciones vía clipboardMode; esto es solo para interoperar con fuera).
  // Ruta(s) como texto plano al portapapeles -- para pegar en una
  // terminal/chat/otra app, no confundir con copySelected() (que copia
  // los FICHEROS para pegarlos con paste()). Varias seleccionadas ->
  // una ruta por línea.
  function copyPathFor(entries) {
    if (!entries || entries.length === 0) return
    var paths = entries.map(function (e) { return root.joinPath(NavState.currentPath, e.name) })
    Detached.run(["bash", "-c", "printf '%s' " + Util.shellQuote(paths.join("\n")) + " | wl-copy"])
  }

  function syncClipboardToSystem() {
    if (ClipboardState.clipboardPaths.length === 0) {
      Detached.run(["wl-copy", "-c"])
      return
    }
    // \r\n entre URIs (RFC 2483), no \n a secas -- el DnD mimeData de más
    // abajo (dragMimeDataFor) ya lo hacía bien; esto lo iguala para que
    // cualquier app externa que lea el portapapeles reciba el mismo
    // formato spec-correcto sea cual sea el camino (copiar o arrastrar).
    var uris = ClipboardState.clipboardPaths.map(function (p) {
      return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }).join("\r\n")
    Detached.run(["bash", "-c", "printf '%s' " + Util.shellQuote(uris) + " | wl-copy -t text/uri-list"])
  }

  // mode: "all" (sin conflictos, tal cual) | "overwrite" | "skip"
  function runPaste(mode) {
    var conflictSet = {}
    ConflictState.pasteConflictNames.forEach(function (n) { conflictSet[n] = true })
    var sources = ClipboardState.clipboardPaths.filter(function (src) {
      if (mode !== "skip") return true
      var name = src.substring(src.lastIndexOf("/") + 1)
      return !conflictSet[name]
    })
    ConflictState.pasteConflictOpen = false
    ConflictState.pasteConflictNames = []
    if (sources.length > 0) {
      var isCut = ClipboardState.clipboardMode === "cut"
      var pairs = sources.map(function (src) {
        var name = src.substring(src.lastIndexOf("/") + 1)
        return { src: src, dest: root.joinPath(NavState.currentPath, name) }
      })
      var busyVerb = isCut ? "Moving " : "Copying "
      var busyLabel = pairs.length === 1
        ? busyVerb + "\"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\"…"
        : busyVerb + pairs.length + " items…"
      if (!isCut) {
        // Copia NATIVA (Fase 13.A): FileOperations.copy en vez de `cp -r`.
        // Copiar no tiene undo (deshacerlo es ambiguo, ver ActionEngine).
        root.copyFiles(pairs, busyLabel, mode === "overwrite")
      } else {
        // Mover NATIVO (Fase 13.B): FileOperations.move. Mismo modelo de undo
        // (mover de vuelta / rehacer), ahora también nativo -- 0 shell.
        var overwrite = mode === "overwrite"
        root.moveFiles(pairs, busyLabel, overwrite, function () {
          var label = pairs.length === 1
            ? "move \"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\""
            : "move " + pairs.length + " items"
          var reversed = pairs.map(function (p) { return { src: p.dest, dest: p.src } })
          root.pushUndo(label, function () {
            return root.moveFiles(reversed, "", false)      // deshacer: no-clobber
          }, function () {
            return root.moveFiles(pairs, "", overwrite)     // rehacer: como el original
          })
        })
      }
    }
    if (ClipboardState.clipboardMode === "cut") {
      ClipboardState.clipboardPaths = []
      ClipboardState.clipboardMode = ""
    }
  }

  function cancelPasteConflict() {
    ConflictState.pasteConflictOpen = false
    ConflictState.pasteConflictNames = []
  }
}

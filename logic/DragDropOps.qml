import QtQuick
import qs.Commons

// Arrastrar y soltar (dentro de la app, y desde/hacia otras) --
// decimonoveno componente extraído de Omafiles.qml.
Item {
  property Item root: null
  // conflictActions.startDropInto() es quien de verdad comprueba
  // conflictos y llama a runDrop() -- handleFilesDropped() solo resuelve
  // el DragEvent en sí (aceptar/rechazar, mover vs copiar).
  property Item conflictActions: null

  function urlToPath(url) {
    var s = String(url)
    if (s.indexOf("file://") === 0) s = s.substring(7)
    try { return decodeURIComponent(s) } catch (e) { return s }
  }

  // MimeData del/los ficheros que arranca a arrastrar la fila `index` --
  // si esa fila ya forma parte de una selección múltiple, arrastra toda la
  // selección (igual que Nautilus); si no, solo esa fila.
  function dragMimeDataFor(index) {
    var indices = (root.isSelected(index) && root.selectedIndices.length > 1) ? root.selectedIndices : [index]
    var paths = indices
      .filter(function (i) { return i >= 0 && i < root.visibleEntries.length })
      .map(function (i) { return root.joinPath(root.currentPath, root.visibleEntries[i].name) })
    var data = {}
    data["text/uri-list"] = paths.map(function (p) { return Util.fileUrl(p) }).join("\r\n")
    return data
  }

  // Ficheros soltados sobre `destDir` (una fila de carpeta, un marcador,
  // una unidad, o el fondo de la lista = la carpeta abierta ahora mismo).
  // `isMove` viene de DragEvent.source !== null (arrastre interno) --
  // arrastres que vienen de fuera siempre copian, nunca mueven el origen.
  // mode: "all" (sin conflictos) | "overwrite" | "skip"
  function runDrop(mode) {
    var conflictSet = {}
    root.dropConflictNames.forEach(function (n) { conflictSet[n] = true })
    var sources = root.dropPendingSources.filter(function (src) {
      if (mode !== "skip") return true
      var name = src.substring(src.lastIndexOf("/") + 1)
      return !conflictSet[name]
    })
    root.dropConflictOpen = false
    root.dropConflictNames = []
    if (sources.length > 0) {
      var noClobber = mode !== "overwrite"
      var destDir = root.dropTargetDir
      var isMove = root.dropIsMove
      var pairs = sources.map(function (src) {
        var name = src.substring(src.lastIndexOf("/") + 1)
        return { src: src, dest: root.joinPath(destDir, name) }
      })
      var cmds = pairs.map(function (p) {
        var verb = isMove ? ("mv " + (noClobber ? "-n" : "-f") + " --") : ("cp -r " + (noClobber ? "-n" : "-f") + " --")
        return verb + " " + Util.shellQuote(p.src) + " " + Util.shellQuote(p.dest)
      })
      var busyVerb = isMove ? "Moving " : "Copying "
      var busyLabel = pairs.length === 1
        ? busyVerb + "\"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\"…"
        : busyVerb + pairs.length + " items…"
      var dropMoveCmd = root.chainCmds(cmds)
      root.startCopyProgress(pairs.map(function (p) { return p.src }), pairs.map(function (p) { return p.dest }))
      root.runAction(dropMoveCmd, busyLabel, function () {
        if (!isMove) return
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
    root.dropPendingSources = []
    root.dropTargetDir = ""
  }

  function cancelDropConflict() {
    root.dropConflictOpen = false
    root.dropConflictNames = []
    root.dropPendingSources = []
    root.dropTargetDir = ""
  }

  // Llamado desde cada DropArea (fila de carpeta, marcador, unidad, fondo
  // de la lista) con el DragEvent real y la carpeta destino ya resuelta.
  function handleFilesDropped(drop, destDir) {
    if (root.inArchive) { drop.accepted = false; return }
    if (!drop.hasUrls) { drop.accepted = false; return }
    var paths = drop.urls.map(function (u) { return urlToPath(u) }).filter(function (p) { return p.length > 0 })
    if (paths.length === 0) { drop.accepted = false; return }
    var isMove = drop.source !== null && drop.source !== undefined
    drop.accept(isMove ? Qt.MoveAction : Qt.CopyAction)
    conflictActions.startDropInto(destDir, paths, isMove)
  }
}

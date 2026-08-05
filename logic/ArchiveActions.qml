import QtQuick
import qs.Commons
import "../state"
import "../services"
import "../Utils.js" as Utils

// Modo "dentro de un archivo" (zip/7z/rar/tar, navegación de solo lectura
// sin extraer nada a disco) + confirmar/cancelar comprimir y extraer tras
// resolver conflictos -- decimocuarto componente extraído de
// Omafiles.qml. isArchive/isIso también se usan fuera del modo archivo en
// sí (para elegir icono, decidir qué hace doble clic, menú contextual...),
// pero son predicados puros sin Process propio, así que viajan aquí con
// el resto en vez de quedarse sueltos en root.
Item {
  property Item root: null
  // La ListView principal (id "list" en Omafiles.qml) -- refreshArchiveListing()
  // resetea su scroll igual que hace refresh() con una carpeta normal.
  property Item list: null
  property Item selectionOps: null
  property Item sortOps: null

  function enterArchive(path) {
    selectionOps.selectOnly(-1)
    ArchiveState.inArchive = true
    ArchiveState.archivePath = path
    ArchiveState.archiveSubPath = ""
    refreshArchiveListing()
  }

  function exitArchive() {
    ArchiveState.inArchive = false
    ArchiveState.archivePath = ""
    ArchiveState.archiveSubPath = ""
    root.refresh()
  }

  function refreshArchiveListing() {
    selectionOps.selectOnly(-1)
    list.contentY = list.originY
    archiveListProc.start([root.pluginDir + "/list-archive.sh", ArchiveState.archivePath, ArchiveState.archiveSubPath])
  }

  // Extrae SOLO ese fichero a una caché temporal (no todo el archivo) y lo
  // abre con la app por defecto -- "unzip -p"/"tar xO"/etc. vuelcan un
  // único miembro a stdout sin tocar disco más que ese archivo de salida,
  // igual de eficiente que abrir un fichero normal aunque el .zip sea
  // enorme.
  function openFileInArchive(entry) {
    var full = ArchiveState.archiveSubPath ? ArchiveState.archiveSubPath + "/" + entry.name : entry.name
    var ext = root.extOf(ArchiveState.archivePath)
    var out = root.homeDir + "/.cache/omafiles/archive-open/" + Utils.simpleHash(ArchiveState.archivePath + "|" + full) + "/" + entry.name
    var outDir = out.substring(0, out.lastIndexOf("/"))
    var cmd
    if (ext === "zip") cmd = "unzip -p -- " + Util.shellQuote(ArchiveState.archivePath) + " " + Util.shellQuote(full) + " > " + Util.shellQuote(out)
    else if (ext === "7z") cmd = "7z x -y -so -- " + Util.shellQuote(ArchiveState.archivePath) + " " + Util.shellQuote(full) + " 2>/dev/null > " + Util.shellQuote(out)
    else if (ext === "rar") cmd = "unrar p -inul -- " + Util.shellQuote(ArchiveState.archivePath) + " " + Util.shellQuote(full) + " > " + Util.shellQuote(out)
    else if (root.tarExt.indexOf(ext) >= 0) cmd = "tar xf " + Util.shellQuote(ArchiveState.archivePath) + " -O " + Util.shellQuote(full) + " > " + Util.shellQuote(out)
    else return
    archiveOpenProc.outPath = out
    archiveOpenProc.start(["bash", "-c", "mkdir -p -- " + Util.shellQuote(outDir) + " && " + cmd])
  }

  function isArchive(entry) {
    if (entry.type === "dir") return false
    var ext = root.extOf(entry.name)
    return ext === "zip" || ext === "7z" || ext === "rar" || root.tarExt.indexOf(ext) >= 0
  }

  function isIso(entry) {
    return entry.type !== "dir" && root.extOf(entry.name) === "iso"
  }

  function runPendingCompress() {
    var p = ConflictState.pendingCompress
    ConflictState.pendingCompress = null
    ConflictState.compressConflictOpen = false
    if (!p) return
    root.runAction(p.cmd, "Compressing to \"" + p.archiveName + "\"…")
  }

  function cancelPendingCompress() {
    ConflictState.pendingCompress = null
    ConflictState.compressConflictOpen = false
  }

  function runPendingExtract() {
    var p = ConflictState.pendingExtract
    ConflictState.pendingExtract = null
    ConflictState.extractConflictOpen = false
    ConflictState.extractConflictNames = []
    if (!p) return
    root.runAction(p.cmd, "Extracting \"" + p.entry.name + "\"…")
  }

  function cancelPendingExtract() {
    ConflictState.pendingExtract = null
    ConflictState.extractConflictOpen = false
    ConflictState.extractConflictNames = []
  }

  ProcessRunner {
    id: archiveListProc
    onFinished: function (result) {
      var s = String(result.stdout || "")
      var fields = s.length === 0 ? [] : s.split(String.fromCharCode(0))
      if (fields.length > 0 && fields[fields.length - 1] === "") fields.pop()
      var parsed = []
      for (var i = 0; i + 1 < fields.length; i += 2) {
        parsed.push({ type: fields[i + 1] === "1" ? "dir" : "file", name: fields[i], size: 0, mtime: 0, link: "" })
      }
      root.entries = sortOps.sortEntries(parsed)
      list.positionViewAtBeginning()
      selectionOps.selectOnly(root.visibleEntries.length > 0 ? 0 : -1)
    }
  }

  ProcessRunner {
    id: archiveOpenProc
    property string outPath: ""
    onFinished: function (result) {
      if (result.exitCode !== 0) {
        Notifier.notify("Couldn't open file from archive: " + (result.stderr.trim() || "unknown error"))
        return
      }
      root.openWithDefault(archiveOpenProc.outPath)
    }
  }
}

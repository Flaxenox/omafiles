import QtQuick
import qs.Commons
import "../state"
import Omafiles.Backend as Backend
import "../Utils.js" as Utils

// "Inside an archive" mode (zip/7z/rar/tar, read-only navigation
// without extracting anything to disk) + confirm/cancel compress and extract after
// resolving conflicts -- fourteenth component extracted from
// core. isArchive/isIso are also used outside the archive mode
// itself (to choose an icon, decide what double-click does, context menu...),
// but they are pure predicates without their own Process, so they travel here with
// the rest instead of staying loose in root.
Item {
  property Item root: null
  property Item actionEngine: null
  property Item navController: null

  // The main ListView (id "list" in core) -- refreshArchiveListing()
  // resets its scroll just like refresh() does with a normal folder.
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
    navController.refresh()
  }

  function refreshArchiveListing() {
    selectionOps.selectOnly(-1)
    list.contentY = list.originY
    archiveListProc.start([Paths.resourceDir + "/list-archive.sh", ArchiveState.archivePath, ArchiveState.archiveSubPath])
  }

  // Extracts ONLY that file to a temporary cache (not the whole archive) and
  // opens it with the default app.
  function openFileInArchive(entry) {
    var full = ArchiveState.archiveSubPath ? ArchiveState.archiveSubPath + "/" + entry.name : entry.name
    var ext = Utils.extOf(ArchiveState.archivePath)
    var out = Paths.homeDir + "/.cache/omafiles/archive-open/" + Backend.ThumbnailProvider.cacheKey(ArchiveState.archivePath + "|" + full) + "/" + entry.name
    var outDir = out.substring(0, out.lastIndexOf("/"))
    var cmd
    if (ext === "zip") cmd = "unzip -p -- " + Util.shellQuote(ArchiveState.archivePath) + " " + Util.shellQuote(full) + " > " + Util.shellQuote(out)
    else if (ext === "7z") cmd = "7z x -y -so -- " + Util.shellQuote(ArchiveState.archivePath) + " " + Util.shellQuote(full) + " 2>/dev/null > " + Util.shellQuote(out)
    else if (ext === "rar") cmd = "unrar p -inul -- " + Util.shellQuote(ArchiveState.archivePath) + " " + Util.shellQuote(full) + " > " + Util.shellQuote(out)
    else if (FileTypeConfig.tarExt.indexOf(ext) >= 0) cmd = "tar xf " + Util.shellQuote(ArchiveState.archivePath) + " -O -- " + Util.shellQuote(full) + " > " + Util.shellQuote(out)
    else return
    archiveOpenProc.outPath = out
    archiveOpenProc.start(["bash", "-c", "mkdir -p -- " + Util.shellQuote(outDir) + " && " + cmd])
  }

  function isArchive(entry) {
    if (entry.type === "dir") return false
    var ext = Utils.extOf(entry.name)
    return ext === "zip" || ext === "7z" || ext === "rar" || FileTypeConfig.tarExt.indexOf(ext) >= 0
  }

  function isIso(entry) {
    return entry.type !== "dir" && Utils.extOf(entry.name) === "iso"
  }

  function runPendingCompress() {
    var p = ConflictState.pendingCompress
    ConflictState.pendingCompress = null
    ConflictState.compressConflictOpen = false
    if (!p) return
    actionEngine.runAction(p.cmd, "Compressing to \"" + p.archiveName + "\"…")
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
    actionEngine.runAction(p.cmd, "Extracting \"" + p.entry.name + "\"…")
  }

  function cancelPendingExtract() {
    ConflictState.pendingExtract = null
    ConflictState.extractConflictOpen = false
    ConflictState.extractConflictNames = []
  }

  Backend.ProcessRunner {
    id: archiveListProc
    onFinished: function (result) {
      var s = String(result.stdout || "")
      var fields = s.length === 0 ? [] : s.split(String.fromCharCode(0))
      if (fields.length > 0 && fields[fields.length - 1] === "") fields.pop()
      var parsed = []
      for (var i = 0; i + 1 < fields.length; i += 2) {
        parsed.push({ type: fields[i + 1] === "1" ? "dir" : "file", name: fields[i], size: 0, mtime: 0, link: "" })
      }
      NavState.entries = sortOps.sortEntries(parsed)
      list.positionViewAtBeginning()
      selectionOps.selectOnly(NavState.visibleEntries.length > 0 ? 0 : -1)
    }
  }

  Backend.ProcessRunner {
    id: archiveOpenProc
    property string outPath: ""
    onFinished: function (result) {
      if (result.exitCode !== 0) {
        Backend.Notifier.notify("Couldn't open file from archive: " + (result.stderr.trim() || "unknown error"))
        return
      }
      navController.openWithDefault(archiveOpenProc.outPath)
    }
  }
}

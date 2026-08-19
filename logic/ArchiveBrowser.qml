import QtQuick
import qs.Commons
import "../state"
import Omafiles.Backend as Backend
import "../shared/Utils.js" as Utils

// Archive browsing -- list/enter/open files inside a .zip/.7z/.rar/tar
// WITHOUT extracting it to disk, so it can be navigated as if it were just
// another folder. Extracted from logic/ActionEngine.qml (architectural
// audit 2026-08-17, P2.3): this is the one block that never touched
// runAction()/pushUndo()/the native-batch machinery -- a genuinely
// independent read-only lifecycle ("is inArchive, and if so what's
// listed"), not a mutating file action.
//
// ArchiveState.{inArchive,archivePath,archiveSubPath} remains the single
// source of truth (state/ArchiveState.qml) -- this component is its sole
// writer for real archive-browsing operations (enter/enterSubdir/up/exit/
// forceExit/restore); other files may still read it directly (e.g.
// TabOps.saveActiveTab() snapshotting it for a tab), which is fine, since
// reading a state/ singleton is not the coupling this extraction cares
// about -- writing it from three different unrelated files with three
// slightly different inline recipes was.
Item {
  id: archiveBrowser

  property Item list: null
  property Item navController: null

  // ---------- Entry / exit ----------

  // A real archive file was opened (double-click, "Open", Enter) --
  // always from OUTSIDE archive mode, always the archive root.
  function enter(path) {
    SelectionState.selectOnly(-1)
    ArchiveState.inArchive = true
    ArchiveState.archivePath = path
    ArchiveState.archiveSubPath = ""
    refresh()
  }

  // A folder ROW was activated while already inside the archive --
  // descend one level. Was inline in NavigationController.enter()
  // (direct ArchiveState.archiveSubPath mutation + a call into what was
  // then ActionEngine.refreshArchiveListing()); centralized here so every
  // real write to archiveSubPath goes through the same function.
  function enterSubdir(name) {
    ArchiveState.archiveSubPath = ArchiveState.archiveSubPath
      ? ArchiveState.archiveSubPath + "/" + name : name
    refresh()
  }

  // "Up" was pressed while inside the archive -- ascend one level, or
  // leave archive mode entirely if already at the archive root. Was
  // inline in NavigationController.goUp(); same centralization reason as
  // enterSubdir().
  function up() {
    if (ArchiveState.archiveSubPath === "") { exit(); return }
    var slash = ArchiveState.archiveSubPath.lastIndexOf("/")
    ArchiveState.archiveSubPath = slash > 0 ? ArchiveState.archiveSubPath.substring(0, slash) : ""
    refresh()
  }

  // Explicit exit (from up() at the archive root, or any other caller
  // that wants the underlying real directory re-listed right away).
  function exit() {
    ArchiveState.inArchive = false
    ArchiveState.archivePath = ""
    ArchiveState.archiveSubPath = ""
    navController.refresh()
  }

  // Silent reset: any REAL navigation elsewhere (bookmark, back/forward,
  // tab switch, editing the path by hand) also leaves archive mode, but
  // the caller (NavigationController._goToPath) is about to list a
  // different place itself right after -- calling exit()'s
  // navController.refresh() here would just be immediately discarded
  // work (and briefly re-list the archive's real parent folder for
  // nothing). Was an inline three-property reset in _goToPath(); same
  // centralization reason as enterSubdir()/up().
  function forceExit() {
    ArchiveState.inArchive = false
    ArchiveState.archivePath = ""
    ArchiveState.archiveSubPath = ""
  }

  // ---------- Listing ----------

  function refresh() {
    SelectionState.selectOnly(-1)
    list.setContentY(list.originY)
    listProc.start([Paths.resourceDir + "/scripts/runtime/list-archive.sh", ArchiveState.archivePath, ArchiveState.archiveSubPath])
  }

  // Tab-switch restoration (TabOps._restoreTabArchive): a tab that was
  // browsing inside an archive lands back on that exact position instead
  // of the real folder containing the archive. Was inline ArchiveState
  // writes + a direct call into what was then
  // ActionEngine.refreshArchiveListing(); same centralization reason as
  // enterSubdir()/up()/forceExit().
  function restore(archivePath, archiveSubPath) {
    ArchiveState.inArchive = true
    ArchiveState.archivePath = archivePath
    ArchiveState.archiveSubPath = archiveSubPath || ""
    refresh()
  }

  // ---------- Opening a file inside the archive ----------

  // Extracts ONLY that file to a temporary cache (not the whole archive)
  // and opens it with the default app.
  function openFile(entry) {
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
    openProc.outPath = out
    // outDir is keyed by an unsalted SHA-1 of (archivePath+full) -- fully
    // predictable offline by anyone who knows those two strings. Without
    // this, a symlink pre-planted at `out` (or at `outDir` itself, pointing
    // at some other real directory) would make the shell `>` redirection
    // above follow it and overwrite whatever it points to instead of
    // creating a fresh file (P0-3, forensic audit 2026-08-16). `rm -rf --`
    // on a symlink removes the link itself, never its target, so this is
    // safe even if outDir/out is currently a symlink; mkdir -p then always
    // creates a genuinely fresh real directory before extraction writes into it.
    openProc.start(["bash", "-c", "rm -rf -- " + Util.shellQuote(outDir)
      + " && mkdir -p -- " + Util.shellQuote(outDir) + " && " + cmd])
  }

  // ---------- Detection ----------

  // ISO detection (isIso) deliberately stays out of this component: ISO
  // mounting (logic/MountActions.qml, udisksctl loop-mount) is a
  // different mechanism entirely, not archive browsing -- it only ever
  // sat next to isArchive() in the old ActionEngine because both are
  // "can this file be entered like a folder" checks, not because they
  // share any real implementation.
  function isArchive(entry) {
    if (entry.type === "dir") return false
    var ext = Utils.extOf(entry.name)
    return ext === "zip" || ext === "7z" || ext === "rar" || FileTypeConfig.tarExt.indexOf(ext) >= 0
  }

  Backend.ProcessRunner {
    id: listProc
    onFinished: function (result) {
      var s = String(result.stdout || "")
      var fields = s.length === 0 ? [] : s.split(String.fromCharCode(0))
      if (fields.length > 0 && fields[fields.length - 1] === "") fields.pop()
      var parsed = []
      for (var i = 0; i + 1 < fields.length; i += 2) {
        parsed.push({ type: fields[i + 1] === "1" ? "dir" : "file", name: fields[i], size: 0, mtime: 0, link: "" })
      }
      NavState.entries = SortState.sortEntries(parsed)
      list.positionViewAtBeginning()
      SelectionState.selectOnly(NavState.visibleEntries.length > 0 ? 0 : -1)
    }
  }

  Backend.ProcessRunner {
    id: openProc
    property string outPath: ""
    onFinished: function (result) {
      if (result.exitCode !== 0) {
        Backend.Notifier.notify(result.stderr.trim() || "Couldn't open archive")
        return
      }
      navController.openWithDefault(openProc.outPath)
    }
  }
}

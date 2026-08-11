import "../Utils.js" as Utils
import QtQuick
import qs.Commons
import "../state"
import "../services"

// Copy/cut/paste (internal clipboard + synced with the system's
// wl-copy/wl-paste) -- eighteenth component extracted from
// Omafiles.qml.
Item {
  property Item root: null
  property Item actionEngine: null

  property Item selectionOps: null

  function copySelected() {
    if (ArchiveState.inArchive) return
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return
    ClipboardState.clipboardPaths = entries.map(function (e) { return Utils.entryPath(NavState.currentPath, e) })
    ClipboardState.clipboardMode = "copy"
    syncClipboardToSystem()
  }

  function cutSelected() {
    if (ArchiveState.inArchive) return
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return
    ClipboardState.clipboardPaths = entries.map(function (e) { return Utils.entryPath(NavState.currentPath, e) })
    ClipboardState.clipboardMode = "cut"
    syncClipboardToSystem()
  }

  // Previously clipboardPaths was only internal -- copying in Omafiles and pasting
  // in another app (or the other way around) did not work. text/uri-list is the MIME type
  // most widely recognized (file managers, browsers, chat
  // apps...) -- wl-copy can only serve one type per invocation, so
  // broad compatibility is prioritized over being able to distinguish cut/copy
  // for OTHER apps (Omafiles does distinguish cut/copy for its own
  // actions via clipboardMode; this is only to interoperate with the outside).
  // Path(s) as plain text to the clipboard -- to paste into a
  // terminal/chat/another app, not to be confused with copySelected() (which copies
  // the FILES to paste them with paste()). Several selected ->
  // one path per line.
  function copyPathFor(entries) {
    if (!entries || entries.length === 0) return
    var paths = entries.map(function (e) { return Utils.entryPath(NavState.currentPath, e) })
    Detached.run(["bash", "-c", "printf '%s' " + Util.shellQuote(paths.join("\n")) + " | wl-copy"])
  }

  function syncClipboardToSystem() {
    if (ClipboardState.clipboardPaths.length === 0) {
      Detached.run(["wl-copy", "-c"])
      return
    }
    // \r\n between URIs (RFC 2483), not plain \n -- the DnD mimeData
    // below (dragMimeDataFor) already did it right; this matches it so
    // any external app that reads the clipboard receives the same
    // spec-correct format whichever path (copy or drag).
    var uris = ClipboardState.clipboardPaths.map(function (p) {
      return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }).join("\r\n")
    Detached.run(["bash", "-c", "printf '%s' " + Util.shellQuote(uris) + " | wl-copy -t text/uri-list"])
  }

  // mode: "all" (no conflicts, as is) | "overwrite" | "skip"
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
        return { src: src, dest: Utils.joinPath(NavState.currentPath, name) }
      })
      var busyVerb = isCut ? "Moving " : "Copying "
      var busyLabel = pairs.length === 1
        ? busyVerb + "\"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\"…"
        : busyVerb + pairs.length + " items…"
      if (!isCut) {
        // NATIVE copy (Phase 13.A): FileOperations.copy instead of `cp -r`.
        // Copy has no undo (undoing it is ambiguous, see ActionEngine).
        actionEngine.runNativeCopy(pairs, busyLabel, mode === "overwrite")
      } else {
        // NATIVE move (Phase 13.B): FileOperations.move. Same undo model
        // (move back / redo), now also native -- 0 shell.
        var overwrite = mode === "overwrite"
        actionEngine.runNativeMove(pairs, busyLabel, overwrite, function () {
          var label = pairs.length === 1
            ? "move \"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\""
            : "move " + pairs.length + " items"
          var reversed = pairs.map(function (p) { return { src: p.dest, dest: p.src } })
          actionEngine.pushUndo(label, function () {
            return actionEngine.runNativeMove(reversed, "", false)      // undo: no-clobber
          }, function () {
            return actionEngine.runNativeMove(pairs, "", overwrite)     // redo: like the original
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

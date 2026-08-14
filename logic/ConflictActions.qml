import "../Utils.js" as Utils
import QtQuick
import qs.Commons
import "../state"
import Omafiles.Backend as Backend

// Conflict check before executing an action that may
// overwrite something -- nineteenth component extracted from core,
// and the first one to touch an action that actually moves/overwrites
// the user's files (unlike Persistence/PreviewLoader/
// PropertiesLoader, which only read). That's why one function was
// added at a time, each hand-tested, instead of moving the whole block
// at once.
//
// commitRename() checks the conflict here (native existingPaths, BUG-01)
// -- but runPendingRename() (the real "mv", with its undo) stays in
// core untouched: besides responding to the check result
// ("0 conflicts" -> renames now), it is called directly by
// ConflictResolveDialog.onConfirmed, and moving it here would only have moved
// that single call site without joining anything else.
Item {
  property Item root: null
  property Item actionEngine: null
  property Item fileTypeUtils: null

  property Item archiveActions: null
  property Item fileOps: null
  property Item renameOps: null
  property Item clipboardOps: null
  property Item selectionOps: null
  property Item bookmarkOps: null

  function paste() {
    if (ArchiveState.inArchive) return
    if (ClipboardState.clipboardPaths.length === 0) {
      // Nothing copied from INSIDE Omafiles -- try the system
      // clipboard (copy in Nautilus/the browser/a chat/etc. and paste
      // here). It is always treated as "copy", never "cut": a
      // loose text/uri-list does not carry that distinction (unlike
      // GTK's own x-special/gnome-copied-files, which not all apps
      // that copy paths write).
      systemClipboardReadProc.start(["wl-paste", "-t", "text/uri-list"])
      return
    }
    var destPaths = ClipboardState.clipboardPaths.map(function (src) {
      var name = src.substring(src.lastIndexOf("/") + 1)
      return Utils.joinPath(NavState.currentPath, name)
    })
    // NATIVE conflict detection: FileOperations.existingPaths
    // (synchronous stat) instead of a `test -e` via shell. Same observable
    // result: 0 conflicts -> pastes now; if any, opens the dialog.
    var conflicts = Backend.FileOperations.existingPaths(destPaths)
    if (conflicts.length === 0) {
      clipboardOps.runPaste("all")
    } else {
      ConflictState.pasteConflictNames = conflicts.map(function (p) { return p.substring(p.lastIndexOf("/") + 1) })
      ConflictState.pasteConflictOpen = true
    }
  }

  function startDropInto(destDir, sourcePaths, isMove) {
    if (!destDir) return
    sourcePaths = sourcePaths.filter(function (src) {
      var srcDir = src.substring(0, src.lastIndexOf("/"))
      // Avoids dropping onto the source folder itself (no-op) or inside
      // itself if the dragged file is actually a folder.
      return src !== destDir && srcDir !== destDir && (destDir + "/").indexOf(src + "/") !== 0
    })
    if (sourcePaths.length === 0) return
    ConflictState.dropPendingSources = sourcePaths
    ConflictState.dropTargetDir = destDir
    ConflictState.dropIsMove = isMove
    var destPaths = sourcePaths.map(function (src) {
      return Utils.joinPath(destDir, src.substring(src.lastIndexOf("/") + 1))
    })
    // NATIVE conflict detection: same as paste().
    var conflicts = Backend.FileOperations.existingPaths(destPaths)
    if (conflicts.length === 0) {
      runDrop("all")
    } else {
      ConflictState.dropConflictNames = conflicts.map(function (p) { return p.substring(p.lastIndexOf("/") + 1) })
      ConflictState.dropConflictOpen = true
    }
  }

  function compressSelected() {
    if (ArchiveState.inArchive) return
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return
    var archiveName = entries.length === 1
      ? entries[0].name.replace(/\/$/, "") + ".zip"
      : "selected-files.zip"
    var names = entries.map(function (e) { return Util.shellQuote(e.name) }).join(" ")
    // "rm -f" before the zip: if the user confirms overwriting an
    // already-existing archiveName, make it a real replacement -- without the rm,
    // "zip -r" ADDS/updates entries inside the existing zip instead of
    // replacing it, so confirming "overwrite" did not actually leave a
    // clean zip with only what is selected now.
    // "./" before the zip name + "--" before the list: a
    // real file named, for example, "-rf" (a valid name in Linux) would be
    // interpreted as zip flags instead of as a file name.
    // zip does not accept "--" before the zip name itself (error "can't use
    // -- before archive name"), hence the "./" instead.
    var cmd = "cd -- " + Util.shellQuote(NavState.currentPath) + " && rm -f -- " + Util.shellQuote(archiveName)
      + " && zip -r -q " + Util.shellQuote("./" + archiveName) + " -- " + names
    ConflictState.pendingCompress = { archiveName: archiveName, cmd: cmd }
    // NATIVE conflict (BUG-01): existingPaths instead of `test -e` via shell.
    if (Backend.FileOperations.existingPaths([Utils.joinPath(NavState.currentPath, archiveName)]).length > 0)
      ConflictState.compressConflictOpen = true
    else
      archiveActions.runPendingCompress()
  }

  function commitBulkRename() {
    var entries = selectionOps.selectedEntries()
    DialogsState.bulkRenameOpen = false
    if (entries.length === 0) return
    var pattern = DialogsState.bulkRenamePattern
    bookmarkOps.addBulkRenameHistory(pattern)
    var pairs = entries.map(function (e, i) {
      var ext = e.type === "dir" ? "" : (fileTypeUtils.extOf(e.name) ? "." + fileTypeUtils.extOf(e.name) : "")
      var base = ext ? e.name.slice(0, -ext.length) : e.name
      var newName = pattern.replace(/\{name\}/g, base).replace(/\{ext\}/g, ext).replace(/\{n\}/g, String(i + 1))
      return {
        oldName: e.name, newName: newName,
        oldPath: Utils.joinPath(NavState.currentPath, e.name),
        newPath: Utils.joinPath(NavState.currentPath, newName)
      }
    })
    ConflictState.pendingBulkRename = pairs
    // Before, this used "mv -n" blindly: a pattern that produces an
    // already-existing name (or that two items of the selection itself end up
    // with the same new name) made mv -n not touch THAT particular item,
    // with no notice of which one was left unrenamed. Now the
    // conflicts with what already exists on disk are checked beforehand...
    var targetCounts = {}
    pairs.forEach(function (p) {
      if (p.newName === p.oldName) return
      targetCounts[p.newPath] = (targetCounts[p.newPath] || 0) + 1
    })
    // ...and also the conflicts WITHIN the selection itself (two items
    // that the pattern leaves with the same new name).
    ConflictState.bulkRenameInternalDupes = Object.keys(targetCounts).filter(function (k) { return targetCounts[k] > 1 }).length
    // NATIVE conflict (BUG-01): existingPaths over the destinations that change
    // name, instead of a `test -e` per pair. The total adds the internal
    // dupes of the selection itself, same as before.
    var checkPaths = pairs.filter(function (p) { return p.newName !== p.oldName })
                          .map(function (p) { return p.newPath })
    var total = Backend.FileOperations.existingPaths(checkPaths).length + ConflictState.bulkRenameInternalDupes
    if (total === 0) {
      fileOps.runPendingBulkRename()
    } else {
      ConflictState.bulkRenameConflictCount = total
      ConflictState.bulkRenameConflictOpen = true
    }
  }

  function extractHere(entry) {
    var ext = fileTypeUtils.extOf(entry.name)
    var path = Util.shellQuote(Utils.joinPath(NavState.currentPath, entry.name))
    var dir = Util.shellQuote(NavState.currentPath)
    var cmd, listCmd
    // All force overwrite (-o/-y/-o+) -- needed so that
    // runPendingExtract can actually overwrite after confirming the
    // conflict notice below. listCmd uses the "flat list" mode of
    // each tool (name per line, no header) to know what would be
    // clobbered, without needing to parse tables.
    if (ext === "zip") { cmd = "unzip -o -q " + path + " -d " + dir; listCmd = "unzip -Z1 -- " + path }
    else if (ext === "7z") { cmd = "7z x -y " + path + " -o" + dir; listCmd = "7z l -ba -slt -- " + path + " | grep '^Path = ' | sed 's/^Path = //'" }
    else if (ext === "rar") { cmd = "unrar x -o+ " + path + " " + dir + "/"; listCmd = "unrar lb -- " + path }
    // No "--" on purpose, unlike the other three -- with "tf"
    // (grouped short form of -t -f) tar takes the NEXT token as
    // the direct argument of -f, so a "--" there is interpreted as the
    // file name itself to open and tar fails with "--: No such file or
    // directory". Real bug: this made the conflict check
    // ALWAYS fail silently for tar/tar.gz/tar.bz2/tar.xz (listCmd
    // returned nothing -> 0 conflicts always detected), although zip/7z/
    // rar were not affected.
    else if (FileTypeConfig.tarExt.indexOf(ext) >= 0) { cmd = "tar xf " + path + " -C " + dir; listCmd = "tar tf " + path }
    else return
    // Before, this overwrote without asking, unlike paste/drop/
    // rename (which do check conflicts). Before extracting, the
    // content of the archive is listed and it is checked whether any top-
    // level element already exists in the current folder.
    ConflictState.pendingExtract = { entry: entry, cmd: cmd }
    extractListProc.start(["bash", "-c", listCmd])
  }

  function commitRename(newName) {
    var index = EditModeState.renamingIndex
    EditModeState.renamingIndex = -1
    // Defense in depth: startRename() already blocks STARTING a
    // rename inside an archive, but it doesn't cover the case of starting to
    // rename OUTSIDE, not confirming, and entering a .zip in the meantime --
    // renamingIndex keeps pointing to an index that now belongs to
    // an archive entry, and without this guard commitRename would run mv
    // over currentPath/<zip-name>, which may coincide by
    // chance with a real file.
    if (ArchiveState.inArchive) return
    if (index < 0 || index >= NavState.visibleEntries.length) return
    var oldName = NavState.visibleEntries[index].name
    newName = newName.trim()
    if (!newName || newName === oldName) return
    var oldPath = Utils.joinPath(NavState.currentPath, oldName)
    var newPath = Utils.joinPath(NavState.currentPath, newName)
    ConflictState.pendingRename = { oldPath: oldPath, newPath: newPath }
    // NATIVE conflict (BUG-01): existingPaths instead of `test -e` via shell.
    if (Backend.FileOperations.existingPaths([newPath]).length > 0) ConflictState.renameConflictOpen = true
    else renameOps.runPendingRename(false)
  }

  // Existence check BEFORE creating -- real bug fixed here
  // (josema, 2026-08-05): touch/mkdir -p are idempotent (silent
  // success over something that already existed), so without this guard "New
  // file"/"New folder" with a conflicting name created nothing new
  // but DID register an undo -- a later Ctrl+Z sent to the
  // trash the truly PRE-EXISTING item. Now, instead of failing
  // silently (a notify-send easy to miss), the same
  // Overwrite/Cancel dialog that rename already uses is offered.
  function commitNewFile(name) {
    EditModeState.creatingFile = false
    name = name.trim()
    if (!name) return
    var path = Utils.joinPath(NavState.currentPath, name)
    ConflictState.pendingNewFile = { path: path, name: name }
    // NATIVE conflict (BUG-01): existingPaths instead of `test -e` via shell.
    if (Backend.FileOperations.existingPaths([path]).length > 0) ConflictState.newFileConflictOpen = true
    else renameOps.runPendingNewFile(false)
  }

  function commitNewFolder(name) {
    EditModeState.creatingFolder = false
    EditModeState.creatingFile = false
    name = name.trim()
    if (!name) return
    var path = Utils.joinPath(NavState.currentPath, name)
    ConflictState.pendingNewFolder = { path: path, name: name }
    // NATIVE conflict (BUG-01): existingPaths instead of `test -e` via shell.
    if (Backend.FileOperations.existingPaths([path]).length > 0) ConflictState.newFolderConflictOpen = true
    else renameOps.runPendingNewFolder(false)
  }

  Backend.ProcessRunner {
    id: systemClipboardReadProc
    onFinished: function (result) {
      // Real bug: RFC 2483 requires CRLF between URIs of a text/uri-list, and
      // the real GTK apps (Nautilus, file pickers,
      // Firefox...) write it that way -- without removing the "\r" that stays
      // stuck at the end of each line, decodeURIComponent left it
      // stuck in the path, pasteCheckProc.test -e never found it, and
      // pasting from outside Omafiles failed silently with no
      // notice.
      var uris = String(result.stdout || "").split("\n").map(function (l) { return l.replace(/\r$/, "") }).filter(function (l) { return l.length > 0 })
      var paths = uris.map(function (u) {
        return u.indexOf("file://") === 0 ? decodeURIComponent(u.substring(7)) : ""
      }).filter(function (p) { return p.length > 0 })
      // Empty = system clipboard with no uris (or nothing) -- there is
      // nothing to notify, paste() did nothing either before in this
      // case.
      if (paths.length === 0) return
      ClipboardState.clipboardPaths = paths
      ClipboardState.clipboardMode = "copy"
      paste()
    }
  }

  Backend.ProcessRunner {
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
      // NATIVE conflict (BUG-01): existingPaths over the top-level
      // elements of the archive, instead of a `test -e` per name. (The archive
      // LISTING -- list_raw above -- is still shell: that is not conflict
      // detection and is out of BUG-01's scope.)
      var conflicts = Backend.FileOperations.existingPaths(names.map(function (n) {
        return Utils.joinPath(NavState.currentPath, n)
      })).map(function (p) { return p.substring(p.lastIndexOf("/") + 1) })
      if (conflicts.length === 0) {
        archiveActions.runPendingExtract()
      } else {
        ConflictState.extractConflictNames = conflicts
        ConflictState.extractConflictOpen = true
      }
    }
  }


  // Files dropped onto `destDir` (a folder row, a bookmark,
  // a drive, or the background of the list = the folder open right now).
  // `isMove` comes from DragEvent.source !== null (internal drag) --
  // drags coming from outside always copy, never move the source.
  // mode: "all" (no conflicts) | "overwrite" | "skip". It lived in
  // logic/DragDropOps.qml -- moved here to break a circular
  // dependency (DragDropOps needed conflictActions to check
  // conflicts, and conflictActions needed dragDropOps only for this).
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
        return { src: src, dest: Utils.joinPath(destDir, name) }
      })
      var busyVerb = isMove ? "Moving " : "Copying "
      var busyLabel = pairs.length === 1
        ? busyVerb + "\"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\"…"
        : busyVerb + pairs.length + " items…"
      if (!isMove) {
        // NATIVE copy: FileOperations.copy instead of `cp -r`.
        actionEngine.runNativeCopy(pairs, busyLabel, mode === "overwrite")
      } else {
        // NATIVE move: FileOperations.move. Same undo model
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
    ConflictState.dropPendingSources = []
    ConflictState.dropTargetDir = ""
  }

}

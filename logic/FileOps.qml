import "../Utils.js" as Utils
import QtQuick
import qs.Commons
import "../state"

// Loose file operations with their own undo: bulk rename,
// chmod, create symbolic link, restore from trash --
// fifteenth component extracted from core. They all share the
// same pattern (assemble the command(s), runAction(), pushUndo() with the
// inverse command) without having any Process of their own -- they use the
// central ActionEngine engine through the root wrappers
// (actionEngine.runAction/actionEngine.pushUndo/actionEngine.chainCmds).
Item {
  property Item root: null
  property Item actionEngine: null

  property Item selectionOps: null

  function startBulkRename() {
    if (ArchiveState.inArchive) return
    DialogsState.bulkRenamePattern = "{name}{ext}"
    DialogsState.bulkRenameOpen = true
  }

  function runPendingBulkRename() {
    var pairs = ConflictState.pendingBulkRename
    ConflictState.pendingBulkRename = null
    ConflictState.bulkRenameConflictOpen = false
    if (!pairs) return
    // Before, bulk rename was the only risky operation (along with chmod)
    // without any undo -- a badly written {n}/{name}/{ext} pattern could
    // rename dozens of files at once with no safety net.
    var toRename = pairs.filter(function (p) { return p.newName !== p.oldName })
    var cmds = toRename.map(function (p) {
      return "mv -n -- " + Util.shellQuote(p.oldPath) + " " + Util.shellQuote(p.newPath)
    })
    if (cmds.length === 0) return
    var bulkRenameCmd = actionEngine.chainCmds(cmds)
    actionEngine.runAction(bulkRenameCmd, "Renaming " + cmds.length + " items…", function () {
      var label = toRename.length === 1 ? "rename \"" + toRename[0].oldName + "\"" : "bulk rename " + toRename.length + " items"
      actionEngine.pushUndo(label, function () {
        var undoCmds = toRename.map(function (p) {
          return "mv -n -- " + Util.shellQuote(p.newPath) + " " + Util.shellQuote(p.oldPath)
        })
        return actionEngine.runAction(actionEngine.chainCmds(undoCmds))
      }, function () {
        return actionEngine.runAction(bulkRenameCmd)
      })
    })
  }

  function cancelPendingBulkRename() {
    ConflictState.pendingBulkRename = null
    ConflictState.bulkRenameConflictOpen = false
  }

  function commitChmod(mode) {
    ChmodState.chmodOpen = false
    mode = mode.trim()
    if (!/^[0-7]{3,4}$/.test(mode) || ChmodState.chmodNames.length === 0) return
    // -R is harmless over a loose file (it doesn't descend anywhere),
    // so it can be applied to the whole command without separating files from
    // folders -- simpler than two different chainCmds branches.
    var flag = ChmodState.chmodRecursive ? "-R " : ""
    var cmds = ChmodState.chmodNames.map(function (n) {
      return "chmod " + flag + mode + " -- " + Util.shellQuote(Utils.joinPath(NavState.currentPath, n))
    })
    var label = ChmodState.chmodNames.length === 1
      ? "Setting permissions for \"" + ChmodState.chmodNames[0] + "\"…"
      : "Setting permissions for " + ChmodState.chmodNames.length + " items…"
    // chmod was, along with bulk rename, the only real risky action
    // (even more so with -R) without any undo. It restores the original mode of
    // each selected item -- NOT that of its content if it was applied
    // recursively, see the chmodOriginalModes comment.
    var names = ChmodState.chmodNames
    var originalModes = ChmodState.chmodOriginalModes
    var chmodCmd = actionEngine.chainCmds(cmds)
    actionEngine.runAction(chmodCmd, label, function () {
      var undoLabel = names.length === 1 ? "permissions on \"" + names[0] + "\"" : "permissions on " + names.length + " items"
      actionEngine.pushUndo(undoLabel, function () {
        var undoCmds = names.filter(function (n) { return !!originalModes[n] }).map(function (n) {
          return "chmod " + originalModes[n] + " -- " + Util.shellQuote(Utils.joinPath(NavState.currentPath, n))
        })
        if (undoCmds.length === 0) return false
        return actionEngine.runAction(actionEngine.chainCmds(undoCmds))
      }, function () {
        return actionEngine.runAction(chmodCmd)
      })
    })
  }

  // ownerIdx: 0=owner (you) 1=group 2=other. bit: 4=read 2=write 1=execute.
  function toggleChmodBit(ownerIdx, bit) {
    var mode = String(ChmodState.chmodMode || "0")
    while (mode.length < 3) mode = "0" + mode
    var digits = mode.substring(mode.length - 3)
    var arr = [digits.charCodeAt(0) - 48, digits.charCodeAt(1) - 48, digits.charCodeAt(2) - 48]
    arr[ownerIdx] = arr[ownerIdx] ^ bit
    ChmodState.chmodMode = "" + arr[0] + arr[1] + arr[2]
  }

  function makeLinkFor(entry) {
    if (ArchiveState.inArchive) return
    if (!entry) return
    var target = Utils.joinPath(NavState.currentPath, entry.name)
    var linkName = "Link to " + entry.name
    var linkPath = Utils.joinPath(NavState.currentPath, linkName)
    // The undo is only registered if "ln -s" confirmed success -- before it was
    // registered blindly, so if a file with the name
    // "Link to X" already existed (ln without -f fails silently in that case), a later
    // Ctrl+Z deleted it anyway even though it had nothing to do with
    // the link that was attempted.
    var makeLinkCmd = "ln -s -- " + Util.shellQuote(target) + " " + Util.shellQuote(linkPath)
    actionEngine.runAction(makeLinkCmd, undefined, function () {
      actionEngine.pushUndo("make link \"" + linkName + "\"", function () {
        return actionEngine.runAction("rm -- " + Util.shellQuote(linkPath))
      }, function () {
        return actionEngine.runAction(makeLinkCmd)
      })
    })
  }

  function restoreFromTrash() {
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return
    // NATIVE restore (Phase 13.E): FileOperations.restoreByOrigPath instead
    // of restore-by-origpath.sh. TrashState.trashInfo (see trash-info.sh) already
    // knows the absolute original path of each item, resolved even for the
    // trash of another disk (where Path= is relative to the mount point);
    // restoreByOrigPath uses it to locate the correct .trashinfo in
    // any active trash, without assuming a single one.
    var origPaths = entries
      .filter(function (e) { return !!TrashState.trashInfo[e.name] })
      .map(function (e) { return TrashState.trashInfo[e.name].origPath })
    if (origPaths.length === 0) return
    actionEngine.runNativeRestore(origPaths, entries.length === 1 ? "Restoring \"" + entries[0].name + "\"…" : "Restoring " + entries.length + " items…")
  }
}

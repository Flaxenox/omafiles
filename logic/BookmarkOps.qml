import QtQuick
import "../state"
import "../Utils.js" as Utils

// Bookmarks, recents, bulk-rename history and drive/network
// icons.
Item {
  property Item root: null
  property Item navController: null

  property Item persistence: null
  property Item tabOps: null
  property Item mountOps: null

  // ---------- Recents / history ----------
  // Called on actually opening a file (enter()/launchWith(), NOT on
  // navigating folders -- for that the history and the
  // tabs are already there). Moves to the top if it was already there, cap 20 entries.
  function addRecent(path, name) {
    var next = BookmarksState.recentFiles.filter(function (r) { return r.path !== path })
    next.unshift({ path: path, name: name })
    if (next.length > 20) next = next.slice(0, 20)
    BookmarksState.recentFiles = next
    persistence.saveRecent()
  }

  function removeRecent(path) {
    BookmarksState.recentFiles = BookmarksState.recentFiles.filter(function (r) { return r.path !== path })
    persistence.saveRecent()
  }

  function clearRecent() {
    BookmarksState.recentFiles = []
    persistence.saveRecent()
  }

  function addBulkRenameHistory(pattern) {
    pattern = pattern.trim()
    if (!pattern) return
    var next = BookmarksState.bulkRenameHistory.filter(function (p) { return p !== pattern })
    next.unshift(pattern)
    if (next.length > 8) next = next.slice(0, 8)
    BookmarksState.bulkRenameHistory = next
    persistence.saveBulkRenameHistory()
  }

  // ---------- Bookmarks / drive icons ----------
  function removeBookmark(path) {
    if (path === Paths.trashDir) return
    BookmarksState.bookmarks = BookmarksState.bookmarks.filter(function (b) { return b.path !== path })
    persistence.saveBookmarks()
  }

  // type: "dir" (default) or "file".
  function addBookmark(path, label, type) {
    if (BookmarksState.bookmarks.some(function (b) { return b.path === path })) return
    BookmarksState.bookmarks = BookmarksState.bookmarks.concat([{ label: label, path: path, type: type || "dir" }])
    persistence.saveBookmarks()
  }

  // Sidebar icon -- Home/Trash by special path, Pictures/Videos/Music reuse glyphs
  function iconForBookmark(modelData) {
    if (modelData.path === Paths.homeDir) return "\u{F015}"
    if (modelData.path === Paths.trashDir) return "\u{F0A7A}"
    if (modelData.type === "file") return Utils.iconFor({ type: "file", name: modelData.path.substring(modelData.path.lastIndexOf("/") + 1) })
    var label = modelData.label.toLowerCase()
    if (label.indexOf("picture") >= 0 || label.indexOf("imagen") >= 0) return Utils.iconFor({ name: "x.jpg" })
    if (label.indexOf("video") >= 0) return Utils.iconFor({ name: "x.mp4" })
    if (label.indexOf("music") >= 0 || label.indexOf("música") >= 0) return Utils.iconFor({ name: "x.mp3" })
    return "\u{F024B}"
  }

  function isBookmarked(path) {
    return BookmarksState.bookmarks.some(function (b) { return b.path === path })
  }

  function iconForMount(mount) {
    var fs = (mount.fstype || "").toLowerCase()
    var optical = fs === "iso9660" || fs === "udf"
      || (mount.device || "").indexOf("/dev/loop") === 0
    if (optical) return Utils.iconFor({ type: "file", name: "x.iso" })
    return mount.removable ? "\u{F0553}" : "\u{F02CA}"
  }

  // U+F0870 (md-folder_network) -- already verified against the real cmap of
  // JetBrainsMono Nerd Font in a previous pass (see the file/device
  // type icon notes), reserved then for this very thing.
  function iconForNetworkMount(mount) {
    return "\u{F0870}"
  }

  function networkMountActions(mount) {
    return [
      { label: "Open", action: function () { navController.navigateTo(mount.path) } },
      { label: "Open in new tab", action: function () { tabOps.openInNewTab(mount.path) } },
      { label: "Disconnect", destructive: true, action: function () { mountOps.disconnectNetworkMount(mount) } }
    ]
  }
}

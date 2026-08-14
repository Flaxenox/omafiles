import QtQuick
import "../state"

// Bookmarks, recents, bulk-rename history and drive/network
// icons -- business logic that lived in core despite not
// depending on almost anything (root + persistence, and tabOps/mountOps only for
// the two network-drive menu actions). Found in the same
// audit as logic/SortOps.qml and logic/FileTypeUtils.qml. No
// 3 files (Sidebar.qml, OpenWithOps.qml, ConflictActions.qml).
Item {
  property Item root: null
  property Item navController: null
  property Item fileTypeUtils: null

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
    // Trash is fixed -- it cannot be removed (see the twin guard in
    // bookmarkActions() of core, which does not even offer the
    // option; this is the real guard, in case it is one day called from
    // somewhere else).
    if (path === Paths.trashDir) return
    BookmarksState.bookmarks = BookmarksState.bookmarks.filter(function (b) { return b.path !== path })
    persistence.saveBookmarks()
  }

  // type: "dir" (default, compatible with bookmarks saved before
  // this field existed -- they were all folder ones) or "file".
  function addBookmark(path, label, type) {
    if (BookmarksState.bookmarks.some(function (b) { return b.path === path })) return
    BookmarksState.bookmarks = BookmarksState.bookmarks.concat([{ label: label, path: path, type: type || "dir" }])
    persistence.saveBookmarks()
  }

  // Sidebar icon -- Home/Trash by special path, Pictures/
  // Videos/Music reuse the same glyph that iconFor() already uses for those
  // file types (so there is no need to maintain two icon catalogs), and
  // any other folder (Documents, Downloads, Projects, Almacén,
  // manually added bookmarks...) falls to the generic folder.
  function iconForBookmark(modelData) {
    if (modelData.path === Paths.homeDir) return "\u{F015}"
    if (modelData.path === Paths.trashDir) return "\u{F0A7A}"
    // Bookmark of a loose file (not a folder) -- real icon by
    // extension, like in the main list, instead of guessing by
    // label name (that only makes sense for the special
    // folders below).
    if (modelData.type === "file") return fileTypeUtils.iconFor({ type: "file", name: modelData.path.substring(modelData.path.lastIndexOf("/") + 1) })
    var label = modelData.label.toLowerCase()
    if (label.indexOf("picture") >= 0 || label.indexOf("imagen") >= 0) return fileTypeUtils.iconFor({ name: "x.jpg" })
    if (label.indexOf("video") >= 0) return fileTypeUtils.iconFor({ name: "x.mp4" })
    if (label.indexOf("music") >= 0 || label.indexOf("música") >= 0) return fileTypeUtils.iconFor({ name: "x.mp3" })
    return "\u{F024B}"
  }

  function isBookmarked(path) {
    return BookmarksState.bookmarks.some(function (b) { return b.path === path })
  }

  function iconForMount(mount) {
    // Optical/ISO: a mounted ISO appears as a loop device
    // with fstype iso9660 OR udf (Mafia: udf) -- previously only iso9660 was checked,
    // so the ISO fell to the USB icon. It is detected by optical fstype OR by
    // /dev/loop*, and uses the disc icon (same glyph as the .iso file).
    var fs = (mount.fstype || "").toLowerCase()
    var optical = fs === "iso9660" || fs === "udf"
      || (mount.device || "").indexOf("/dev/loop") === 0
    if (optical) return fileTypeUtils.iconFor({ type: "file", name: "x.iso" })
    // Removable (USB/external disk) vs internal partition.
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

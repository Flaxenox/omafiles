pragma Singleton
import QtQuick
import "../shared/Utils.js" as Utils
import Omafiles.Backend as Backend

QtObject {
  property bool bookmarksLoaded: false
  property var bookmarks: Paths.defaultBookmarks
  property var recentFiles: []
  property var bulkRenameHistory: []

  function addRecent(path, name) {
    var next = recentFiles.filter(function (r) { return r.path !== path })
    next.unshift({ path: path, name: name })
    if (next.length > 20) next = next.slice(0, 20)
    recentFiles = next
    Backend.JsonStore.write(Paths.recentFile, next)
  }

  function removeRecent(path) {
    var next = recentFiles.filter(function (r) { return r.path !== path })
    recentFiles = next
    Backend.JsonStore.write(Paths.recentFile, next)
  }

  function clearRecent() {
    recentFiles = []
    Backend.JsonStore.write(Paths.recentFile, [])
  }

  function addBulkRenameHistory(pattern) {
    pattern = pattern.trim()
    if (!pattern) return
    var next = bulkRenameHistory.filter(function (p) { return p !== pattern })
    next.unshift(pattern)
    if (next.length > 8) next = next.slice(0, 8)
    bulkRenameHistory = next
    Backend.JsonStore.write(Paths.bulkRenameHistoryFile, next)
  }

  function removeBookmark(path) {
    if (path === Paths.trashDir) return
    var next = bookmarks.filter(function (b) { return b.path !== path })
    bookmarks = next
    Backend.JsonStore.write(Paths.bookmarksFile, next)
  }

  function addBookmark(path, label, type) {
    if (bookmarks.some(function (b) { return b.path === path })) return
    var next = bookmarks.concat([{ label: label, path: path, type: type || "dir" }])
    bookmarks = next
    Backend.JsonStore.write(Paths.bookmarksFile, next)
  }

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
    return bookmarks.some(function (b) { return b.path === path })
  }

  function iconForMount(mount) {
    var fs = (mount.fstype || "").toLowerCase()
    var optical = fs === "iso9660" || fs === "udf"
      || (mount.device || "").indexOf("/dev/loop") === 0
    if (optical) return Utils.iconFor({ type: "file", name: "x.iso" })
    return mount.removable ? "\u{F0553}" : "\u{F02CA}"
  }

  function iconForNetworkMount(mount) {
    return "\u{F0870}"
  }
}

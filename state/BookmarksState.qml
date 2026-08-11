pragma Singleton
import QtQuick

// Bookmarks, recents and bulk-rename history -- sixteenth
// singleton of the state/ layer, completes logic/BookmarkOps.qml and
// logic/Persistence.qml (which already had the logic extracted, but
// manipulated this state through root). The file paths
// (bookmarksFile/recentFile/sessionFile/bulkRenameHistoryFile) stay
// in Omafiles.qml -- they are config derived from homeDir, not mutable state.
QtObject {
  property var bookmarks: []
  // { path, name } -- most recent first, cap 20. Persisted separately
  // (not in bookmarks.json, different semantics: this is written by the
  // app itself on opening files, the user does not edit it by hand).
  property var recentFiles: []
  property bool recentLoaded: false
  // Patterns actually used in Bulk rename, most recent first, cap
  // 8 -- shown as shortcuts in the dialog itself instead of
  // having to type them again each time.
  property var bulkRenameHistory: []
  property bool bulkRenameHistoryLoaded: false
  property bool bookmarksLoaded: false
}

import QtQuick
import "../state"
import Omafiles.Backend as Backend

// On-disk persistence (bookmarks, recents, tab session,
// bulk-rename history) -- sixteenth component extracted
// from core, and the first that takes a group of Process out of the
// main file. Only the pure I/O functions were moved here
// (read/write the JSON on disk); the business logic that decides WHAT
// to save (addRecent, removeBookmark, addBulkRenameHistory...) stays in
// core and simply calls "persistence.saveX()" instead of
// "root.saveX()" -- same pattern as the rest of the components: root.xxx
// to read/write app state, passed as a property instead of
// looking it up with its own id.
//
// Phase 6.A (josema): the I/O no longer launches shell processes. Previously each
// read was a `cat` (ProcessRunner→QProcess) and each write a
// `bash -c 'mkdir -p ... && printf > ...'` (Detached); now everything goes
// through Omafiles.Services.JsonStore, a thin adapter over the C++ backend
// (QFile/QSaveFile/QJsonDocument). The parsing is in C++, the write is
// atomic and there are no forks. The observable contract is the same: read() is still
// async (loaded arrives on the next cycle), which is why loadSession()
// can keep triggering refresh()/startDirWatch on its own.
Item {
  property Item root: null
  property Item navController: null

  property Item tabOps: null

  // Fire-and-forget write of a JSON to disk -- JsonStore.write creates the
  // folder ~/.local/state/omafiles/ if needed and writes
  // atomically. None of the 4 calls below needs to know when
  // it finishes, so the return value and the saved signal are ignored.
  function _saveJson(path, data) {
    Backend.JsonStore.write(path, data)
  }

  function loadBookmarks() {
    Backend.JsonStore.read(Paths.bookmarksFile)
  }

  function saveBookmarks() {
    _saveJson(Paths.bookmarksFile, BookmarksState.bookmarks)
  }

  function loadRecent() {
    Backend.JsonStore.read(Paths.recentFile)
  }

  function saveRecent() {
    _saveJson(Paths.recentFile, BookmarksState.recentFiles)
  }

  // Only called on the first open of the Quickshell session, without
  // a path requested by the host -- see open(). Async load (JsonStore.read);
  // refresh()/startDirWatch are triggered from the sessionFile handler
  // as soon as it knows the real path, not here (avoids listing homeDir extra if there
  // was a session).
  function loadSession() {
    Backend.JsonStore.read(Paths.sessionFile)
  }

  // Only saves the path of each tab -- not history/preview/scroll,
  // that is "hot" session (it already survives close/reopen without leaving
  // Quickshell thanks to keepLoaded) and it is not worth the complexity of
  // restoring it after a real restart of the shell.
  function saveSession() {
    tabOps.saveActiveTab()
    var snapshot = TabsState.tabs.map(function (t) { return { path: t.path } })
    _saveJson(Paths.sessionFile, { tabs: snapshot, activeTabIndex: TabsState.activeTabIndex })
  }

  function loadBulkRenameHistory() {
    Backend.JsonStore.read(Paths.bulkRenameHistoryFile)
  }

  function saveBulkRenameHistory() {
    _saveJson(Paths.bulkRenameHistoryFile, BookmarksState.bulkRenameHistory)
  }

  // A single delivery point for the four reads: JsonStore is a
  // singleton, so loaded() is dispatched by `path`. `data` already comes
  // parsed from C++ (JS object/array) or undefined if the file does not
  // exist or the JSON was invalid -- it is normalized to null to keep the
  // same "valid or default value" logic that the four
  // separate ProcessRunner had.
  Connections {
    target: Backend.JsonStore

    function onLoaded(path, data, ok) {
      var parsed = ok ? data : null

      if (path === Paths.bookmarksFile) {
        BookmarksState.bookmarksLoaded = true
        if (Array.isArray(parsed) && parsed.length > 0) {
          BookmarksState.bookmarks = parsed
        } else {
          BookmarksState.bookmarks = Paths.defaultBookmarks
          saveBookmarks()
        }
      } else if (path === Paths.recentFile) {
        BookmarksState.recentLoaded = true
        BookmarksState.recentFiles = Array.isArray(parsed) ? parsed : []
      } else if (path === Paths.sessionFile) {
        var savedTabs = (parsed && Array.isArray(parsed.tabs))
          ? parsed.tabs.filter(function (t) { return t && typeof t.path === "string" && t.path.charAt(0) === "/" })
          : []
        if (savedTabs.length > 0) {
          TabsState.tabs = savedTabs.map(function (t) { return { path: t.path, history: [t.path], historyIndex: 0 } })
          TabsState.activeTabIndex = Math.max(0, Math.min(parsed.activeTabIndex || 0, TabsState.tabs.length - 1))
          NavState.currentPath = TabsState.tabs[TabsState.activeTabIndex].path
          TabsState.navHistory = [NavState.currentPath]
          TabsState.navHistoryIndex = 0
        }
        navController.refresh()
        if (!ArchiveState.inArchive) navController.startDirWatch(NavState.currentPath)
      } else if (path === Paths.bulkRenameHistoryFile) {
        BookmarksState.bulkRenameHistoryLoaded = true
        BookmarksState.bulkRenameHistory = Array.isArray(parsed) ? parsed : []
      }
    }
  }
}

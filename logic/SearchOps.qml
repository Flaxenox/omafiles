import QtQuick
import "../state"

// Search (live filter + deep search in subfolders), hidden files,
// edit path by hand, go all the way up/down -- twentieth component
// extracted from core.
Item {
  property Item root: null
  property Item navController: null

  // The main ListView (id "list" in core) -- these actions
  // reset its scroll just like refresh()/navigateTo() with a normal
  // folder.
  property Item list: null

  function toggleHidden() {
    NavState.showHidden = !NavState.showHidden
    list.contentY = list.originY
    navController.refresh()
    NavState.refreshTick += 1
  }

  function startEditPath() {
    EditModeState.editingPath = true
  }

  function startSearch() {
    if (ArchiveState.inArchive) return
    EditModeState.creatingFolder = false
    EditModeState.creatingFile = false
    NavState.searching = true
    NavState.searchQuery = ""
    NavState.searchTruncated = false
    list.contentY = list.originY
  }

  function exitSearch() {
    searchBackend.cancel()
    NavState.searching = false
    NavState.searchQuery = ""
    NavState.searchTruncated = false
    list.contentY = list.originY
    navController.refresh()
    SelectionState.selectOnly(-1)
  }

  function runDeepSearch() {
    // Phase 19: incremental search only starts with 2+ characters; with
    // 0-1 the searcher shows the normal listing (see restoreListing, called
    // by the SearchBar debounce).
    if (NavState.searchQuery.length < 2) return
    NavState.searchBusy = true
    list.contentY = list.originY
    // Indexed GLOBAL search: SearchBackend queries the system
    // index (tracker3/plocate) and, if there is none, falls back to the
    // recursive SearchWorker from currentPath. Cancelable; a new search
    // invalidates the previous one. The UI doesn't know which backend responded.
    searchBackend.search(NavState.searchQuery, NavState.showHidden, NavState.currentPath)
  }

  // Returns to the normal listing of currentPath without closing the searcher:
  // called by the SearchBar debounce when the query drops below 2 characters.
  function restoreListing() {
    searchBackend.cancel()
    NavState.searchBusy = false
    NavState.searchTruncated = false
    list.contentY = list.originY
    navController.refresh()
  }

  function goTop() {
    if (NavState.visibleEntries.length === 0) return
    SelectionState.selectOnly(0)
    list.positionViewAtBeginning()
  }

  function goBottom() {
    if (NavState.visibleEntries.length === 0) return
    var last = NavState.visibleEntries.length - 1
    SelectionState.selectOnly(last)
    list.positionViewAtIndex(last, ListView.Contain)
  }

  // SearchBackend trims to 200 and marks truncated=true if there were more --
  // same contract SearchWorker/the script gave; the incomplete-list notice is
  // painted by the status bar. The entries ALREADY come sorted by relevance
  // (they are not passed through sortOps: that would break that order).
  SearchBackend {
    id: searchBackend
    indexScript: Paths.resourceDir + "/scripts/runtime/search-index.sh"
    onResults: function (entries, truncated) {
      NavState.searchBusy = false
      NavState.searchTruncated = truncated
      NavState.entries = entries
      list.positionViewAtBeginning()
      SelectionState.selectOnly(NavState.visibleEntries.length > 0 ? 0 : -1)
    }
  }
}

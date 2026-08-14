import QtQuick
import "../state"
import "../Utils.js" as Utils

// List sorting (name/size/date/type, asc/desc) -- pure business
// logic that lived loose in core despite not touching any
// Process nor needing to see other subsystems, only SortState.sortKey/sortDesc/
// entries. Found auditing core against rule 3
// ("all business logic outside the UI") of the architecture prompt.
Item {
  property Item root: null

  // true when the requested order is the one C++ already returns (DirectoryModel):
  // name ascending. In that case DirLister does NOT re-sort.
  readonly property bool isDefaultOrder: SortState.sortKey === "name" && !SortState.sortDesc

  function compareEntries(a, b) {
    var result = 0
    if (SortState.sortKey === "size") {
      result = a.size - b.size
    } else if (SortState.sortKey === "mtime") {
      result = a.mtime - b.mtime
    } else if (SortState.sortKey === "type") {
      var ea = Utils.extOf(a.name), eb = Utils.extOf(b.name)
      result = ea < eb ? -1 : (ea > eb ? 1 : 0)
    }
    if (result === 0) {
      result = Utils.naturalCompare(a.name.toLowerCase(), b.name.toLowerCase())
    }
    return SortState.sortDesc ? -result : result
  }

  // Folders always go before files -- the chosen sort criterion
  // only decides how each group is sorted among itself.
  function sortEntries(list) {
    var dirs = list.filter(function (e) { return e.type === "dir" })
    var files = list.filter(function (e) { return e.type !== "dir" })
    dirs.sort(compareEntries)
    files.sort(compareEntries)
    return dirs.concat(files)
  }

  function sortLabel() {
    return SortState.sortKeyLabels[SortState.sortKey] + (SortState.sortDesc ? " ↓" : " ↑")
  }

  function setSort(key) {
    SortState.sortKey = key
    NavState.entries = sortEntries(NavState.entries)
  }

  function cycleSort() {
    var idx = SortState.sortKeys.indexOf(SortState.sortKey)
    setSort(SortState.sortKeys[(idx + 1) % SortState.sortKeys.length])
  }

  function reverseSort() {
    SortState.sortDesc = !SortState.sortDesc
    NavState.entries = sortEntries(NavState.entries)
  }
}

pragma Singleton
import QtQuick

// State for the "Find duplicates..." dialog (dialogs/DuplicateFinderPanel.qml),
// fed by Backend.DuplicateFinder (backend/DuplicateFinder.h) via
// logic/ActionEngine.qml's startDuplicateFinder()/Connections. Same
// "passive cache" role as the other dialog-adjacent state singletons
// (DialogsState holds only the open flag; this one holds the scan's own
// progress/result/selection, kept separate so DialogsState stays a flat
// list of simple flags).
QtObject {
  id: root

  property string rootPath: ""
  property bool scanning: false
  property int filesScanned: 0
  // [{ size: qint64, paths: [string, ...] }, ...] -- only groups with 2+
  // confirmed byte-identical files (see DuplicateFinder.cpp).
  property var groups: []
  // path -> true for every file currently checked for trashing.
  property var selected: ({})

  function reset(path) {
    rootPath = path
    scanning = true
    filesScanned = 0
    groups = []
    selected = ({})
  }

  function toggle(path) {
    var s = Object.assign({}, selected)
    if (s[path]) delete s[path]
    else s[path] = true
    selected = s
  }

  // Convenience: checks every file in every group except the first --
  // the obvious one-click "keep one copy of each" action.
  function selectAllButFirstPerGroup() {
    var s = {}
    for (var i = 0; i < groups.length; i++) {
      var paths = groups[i].paths
      for (var j = 1; j < paths.length; j++) s[paths[j]] = true
    }
    selected = s
  }

  function clearSelection() { selected = ({}) }

  readonly property int selectedCount: Object.keys(selected).length
}

import QtQuick
import "../state"
import "../services"
import "../Utils.js" as Utils

// Búsqueda (filtro en vivo + búsqueda profunda en subcarpetas), ocultos,
// editar ruta a mano, ir arriba/abajo del todo -- vigésimo componente
// extraído de Omafiles.qml.
Item {
  property Item root: null
  property Item navController: null

  // La ListView principal (id "list" en Omafiles.qml) -- estas acciones
  // resetean su scroll igual que refresh()/navigateTo() con una carpeta
  // normal.
  property Item list: null
  property Item selectionOps: null
  property Item sortOps: null

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
    NavState.searching = false
    NavState.searchQuery = ""
    NavState.deepSearchRoot = ""
    NavState.searchTruncated = false
    list.contentY = list.originY
    navController.refresh()
    selectionOps.selectOnly(-1)
  }

  function runDeepSearch() {
    if (!NavState.searchQuery) return
    NavState.deepSearchRoot = NavState.currentPath
    list.contentY = list.originY
    deepSearchProc.start([Paths.pluginDir + "/search-recursive.sh", NavState.currentPath, NavState.searchQuery, NavState.showHidden ? "1" : "0"])
  }

  function goTop() {
    if (NavState.visibleEntries.length === 0) return
    selectionOps.selectOnly(0)
    list.positionViewAtBeginning()
  }

  function goBottom() {
    if (NavState.visibleEntries.length === 0) return
    var last = NavState.visibleEntries.length - 1
    selectionOps.selectOnly(last)
    list.positionViewAtIndex(last, ListView.Contain)
  }

  ProcessRunner {
    id: deepSearchProc
    onFinished: function (result) {
      var parsed = Utils.parseEntries(result.stdout)
      // search-recursive.sh pide 201 a propósito -- si llegan los 201 es
      // que había más de 200 coincidencias reales; se descarta el que
      // sobra y se avisa en la barra de estado en vez de dar la lista
      // por completa en silencio.
      NavState.searchTruncated = parsed.length > 200
      if (NavState.searchTruncated) parsed = parsed.slice(0, 200)
      NavState.entries = sortOps.sortEntries(parsed)
      list.positionViewAtBeginning()
      selectionOps.selectOnly(NavState.visibleEntries.length > 0 ? 0 : -1)
    }
  }
}

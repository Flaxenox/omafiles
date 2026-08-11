import QtQuick
import "../state"
import "../services"

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
    searchBackend.cancel()
    NavState.searching = false
    NavState.searchQuery = ""
    NavState.searchTruncated = false
    list.contentY = list.originY
    navController.refresh()
    selectionOps.selectOnly(-1)
  }

  function runDeepSearch() {
    // Fase 19: la búsqueda incremental solo arranca con 2+ caracteres; con
    // 0-1 el buscador muestra el listado normal (ver restoreListing, llamado
    // por el debounce de SearchBar).
    if (NavState.searchQuery.length < 2) return
    NavState.searchBusy = true
    list.contentY = list.originY
    // Búsqueda GLOBAL indexada (Fase 26): SearchBackend consulta el índice del
    // sistema (tracker3/plocate) y, si no hay ninguno, cae al SearchWorker
    // recursivo desde currentPath. Cancelable; una nueva búsqueda invalida la
    // anterior. La UI no sabe qué backend respondió.
    searchBackend.search(NavState.searchQuery, NavState.showHidden, NavState.currentPath)
  }

  // Vuelve al listado normal de currentPath sin cerrar el buscador (Fase 19):
  // lo llama el debounce de SearchBar cuando la consulta baja de 2 caracteres.
  function restoreListing() {
    searchBackend.cancel()
    NavState.searchBusy = false
    NavState.searchTruncated = false
    list.contentY = list.originY
    navController.refresh()
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

  // SearchBackend recorta a 200 y marca truncated=true si hubo más -- mismo
  // contrato que daba SearchWorker/el script; el aviso de lista incompleta lo
  // pinta la barra de estado. Las entradas YA vienen ordenadas por relevancia
  // (no se pasan por sortOps: eso rompería ese orden).
  SearchBackend {
    id: searchBackend
    indexScript: Paths.pluginDir + "/search-index.sh"
    contentScript: Paths.pluginDir + "/content-search.sh"
    onResults: function (entries, truncated) {
      NavState.searchBusy = false
      NavState.searchTruncated = truncated
      NavState.entries = entries
      list.positionViewAtBeginning()
      selectionOps.selectOnly(NavState.visibleEntries.length > 0 ? 0 : -1)
    }
  }
}

import QtQuick
import Quickshell.Io
import "../Utils.js" as Utils

// Búsqueda (filtro en vivo + búsqueda profunda en subcarpetas), ocultos,
// editar ruta a mano, ir arriba/abajo del todo -- vigésimo componente
// extraído de Omafiles.qml.
Item {
  property Item root: null
  // La ListView principal (id "list" en Omafiles.qml) -- estas acciones
  // resetean su scroll igual que refresh()/navigateTo() con una carpeta
  // normal.
  property Item list: null

  function toggleHidden() {
    root.showHidden = !root.showHidden
    list.contentY = list.originY
    root.refresh()
    root.refreshTick += 1
  }

  function startEditPath() {
    root.editingPath = true
  }

  function startSearch() {
    if (root.inArchive) return
    root.creatingFolder = false
    root.creatingFile = false
    root.searching = true
    root.searchQuery = ""
    root.searchTruncated = false
    list.contentY = list.originY
  }

  function exitSearch() {
    root.searching = false
    root.searchQuery = ""
    root.deepSearchRoot = ""
    root.searchTruncated = false
    list.contentY = list.originY
    root.refresh()
    root.selectOnly(-1)
  }

  function runDeepSearch() {
    if (!root.searchQuery) return
    root.deepSearchRoot = root.currentPath
    list.contentY = list.originY
    deepSearchProc.command = [root.pluginDir + "/search-recursive.sh", root.currentPath, root.searchQuery, root.showHidden ? "1" : "0"]
    deepSearchProc.running = true
  }

  function goTop() {
    if (root.visibleEntries.length > 0) root.selectOnly(0)
  }

  function goBottom() {
    if (root.visibleEntries.length > 0) root.selectOnly(root.visibleEntries.length - 1)
  }

  Process {
    id: deepSearchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Utils.parseEntries(text)
        // search-recursive.sh pide 201 a propósito -- si llegan los 201 es
        // que había más de 200 coincidencias reales; se descarta el que
        // sobra y se avisa en la barra de estado en vez de dar la lista
        // por completa en silencio.
        root.searchTruncated = parsed.length > 200
        if (root.searchTruncated) parsed = parsed.slice(0, 200)
        root.entries = root.sortEntries(parsed)
        list.positionViewAtBeginning()
        root.selectOnly(root.visibleEntries.length > 0 ? 0 : -1)
      }
    }
  }
}

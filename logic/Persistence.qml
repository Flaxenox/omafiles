import QtQuick
import qs.Commons
import "../state"
import "../services"

// Persistencia en disco (marcadores, recientes, sesión de pestañas,
// historial de renombrado en bloque) -- decimosexto componente extraído
// de Omafiles.qml, y el primero que saca un grupo de Process fuera del
// fichero principal. Solo se movieron aquí las funciones de I/O puro
// (leer/escribir el JSON en disco); la lógica de negocio que decide QUÉ
// guardar (addRecent, removeBookmark, addBulkRenameHistory...) se queda en
// Omafiles.qml y simplemente llama a "persistence.saveX()" en vez de
// "root.saveX()" -- mismo patrón que el resto de componentes: root.xxx
// para leer/escribir estado de la app, pasado como propiedad en vez de
// buscarlo con un id propio.
Item {
  property Item root: null
  property Item tabOps: null

  // Escritura fire-and-forget de un JSON a disco -- mkdir -p por si la
  // carpeta ~/.local/state/omafiles/ aún no existe. Ninguna de las 4
  // llamadas de más abajo necesita saber cuándo termina ni capturar
  // stdout/stderr, así que Detached.run() basta -- antes cada una tenía
  // su propio Process vacío (`Process { id: saveXProc }`, sin stdout/
  // stderr, solo para asignarle `.command` en caliente), 4 copias del
  // mismo patrón de 4 líneas.
  function _saveJson(path, data) {
    var dir = path.substring(0, path.lastIndexOf("/"))
    var json = JSON.stringify(data)
    Detached.run(["bash", "-c", "mkdir -p -- " + Util.shellQuote(dir) + " && printf '%s' " + Util.shellQuote(json) + " > " + Util.shellQuote(path)])
  }

  function loadBookmarks() {
    loadBookmarksProc.start(["cat", root.bookmarksFile])
  }

  function saveBookmarks() {
    _saveJson(root.bookmarksFile, BookmarksState.bookmarks)
  }

  function loadRecent() {
    loadRecentProc.start(["cat", root.recentFile])
  }

  function saveRecent() {
    _saveJson(root.recentFile, BookmarksState.recentFiles)
  }

  // Solo se llama en la primera apertura de la sesión de Quickshell, sin
  // ruta pedida por el host -- ver open(). Carga async (cat + Process,
  // igual que bookmarks/recent); refresh()/startDirWatch se disparan desde
  // el propio handler de loadSessionProc en cuanto sabe la ruta real, no
  // aquí (evita listar homeDir de más si sí había sesión).
  function loadSession() {
    loadSessionProc.start(["cat", root.sessionFile])
  }

  // Solo guarda la ruta de cada pestaña -- no historial/preview/scroll,
  // eso es sesión "en caliente" (ya sobrevive a cerrar/reabrir sin salir
  // de Quickshell gracias a keepLoaded) y no vale la pena la complejidad de
  // restaurarlo tras un reinicio real del shell.
  function saveSession() {
    tabOps.saveActiveTab()
    var snapshot = TabsState.tabs.map(function (t) { return { path: t.path } })
    _saveJson(root.sessionFile, { tabs: snapshot, activeTabIndex: TabsState.activeTabIndex })
  }

  function loadBulkRenameHistory() {
    loadBulkRenameHistoryProc.start(["cat", root.bulkRenameHistoryFile])
  }

  function saveBulkRenameHistory() {
    _saveJson(root.bulkRenameHistoryFile, BookmarksState.bulkRenameHistory)
  }

  ProcessRunner {
    id: loadBookmarksProc
    onFinished: function (result) {
      BookmarksState.bookmarksLoaded = true
      var parsed = null
      try { parsed = JSON.parse(result.stdout) } catch (e) { parsed = null }
      if (Array.isArray(parsed) && parsed.length > 0) {
        BookmarksState.bookmarks = parsed
      } else {
        BookmarksState.bookmarks = root.defaultBookmarks
        saveBookmarks()
      }
    }
  }

  ProcessRunner {
    id: loadRecentProc
    onFinished: function (result) {
      BookmarksState.recentLoaded = true
      var parsed = null
      try { parsed = JSON.parse(result.stdout) } catch (e) { parsed = null }
      BookmarksState.recentFiles = Array.isArray(parsed) ? parsed : []
    }
  }

  ProcessRunner {
    id: loadSessionProc
    onFinished: function (result) {
      var parsed = null
      try { parsed = JSON.parse(result.stdout) } catch (e) { parsed = null }
      var savedTabs = (parsed && Array.isArray(parsed.tabs))
        ? parsed.tabs.filter(function (t) { return t && typeof t.path === "string" && t.path.charAt(0) === "/" })
        : []
      if (savedTabs.length > 0) {
        TabsState.tabs = savedTabs.map(function (t) { return { path: t.path, history: [t.path], historyIndex: 0 } })
        TabsState.activeTabIndex = Math.max(0, Math.min(parsed.activeTabIndex || 0, TabsState.tabs.length - 1))
        root.currentPath = TabsState.tabs[TabsState.activeTabIndex].path
        TabsState.navHistory = [root.currentPath]
        TabsState.navHistoryIndex = 0
      }
      root.refresh()
      if (!ArchiveState.inArchive) root.startDirWatch(root.currentPath)
    }
  }

  ProcessRunner {
    id: loadBulkRenameHistoryProc
    onFinished: function (result) {
      BookmarksState.bulkRenameHistoryLoaded = true
      var parsed = null
      try { parsed = JSON.parse(result.stdout) } catch (e) { parsed = null }
      BookmarksState.bulkRenameHistory = Array.isArray(parsed) ? parsed : []
    }
  }
}

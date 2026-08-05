import QtQuick
import Quickshell.Io
import qs.Commons

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

  function loadBookmarks() {
    loadBookmarksProc.running = true
  }

  function saveBookmarks() {
    var dir = root.bookmarksFile.substring(0, root.bookmarksFile.lastIndexOf("/"))
    var json = JSON.stringify(root.bookmarks)
    saveBookmarksProc.command = ["bash", "-c", "mkdir -p -- " + Util.shellQuote(dir) + " && printf '%s' " + Util.shellQuote(json) + " > " + Util.shellQuote(root.bookmarksFile)]
    saveBookmarksProc.running = true
  }

  function loadRecent() {
    loadRecentProc.running = true
  }

  function saveRecent() {
    var dir = root.recentFile.substring(0, root.recentFile.lastIndexOf("/"))
    var json = JSON.stringify(root.recentFiles)
    saveRecentProc.command = ["bash", "-c", "mkdir -p -- " + Util.shellQuote(dir) + " && printf '%s' " + Util.shellQuote(json) + " > " + Util.shellQuote(root.recentFile)]
    saveRecentProc.running = true
  }

  // Solo se llama en la primera apertura de la sesión de Quickshell, sin
  // ruta pedida por el host -- ver open(). Carga async (cat + Process,
  // igual que bookmarks/recent); refresh()/startDirWatch se disparan desde
  // el propio handler de loadSessionProc en cuanto sabe la ruta real, no
  // aquí (evita listar homeDir de más si sí había sesión).
  function loadSession() {
    loadSessionProc.running = true
  }

  // Solo guarda la ruta de cada pestaña -- no historial/preview/scroll,
  // eso es sesión "en caliente" (ya sobrevive a cerrar/reabrir sin salir
  // de Quickshell gracias a keepLoaded) y no vale la pena la complejidad de
  // restaurarlo tras un reinicio real del shell.
  function saveSession() {
    tabOps.saveActiveTab()
    var snapshot = root.tabs.map(function (t) { return { path: t.path } })
    var json = JSON.stringify({ tabs: snapshot, activeTabIndex: root.activeTabIndex })
    var dir = root.sessionFile.substring(0, root.sessionFile.lastIndexOf("/"))
    saveSessionProc.command = ["bash", "-c", "mkdir -p -- " + Util.shellQuote(dir) + " && printf '%s' " + Util.shellQuote(json) + " > " + Util.shellQuote(root.sessionFile)]
    saveSessionProc.running = true
  }

  function loadBulkRenameHistory() {
    loadBulkRenameHistoryProc.running = true
  }

  function saveBulkRenameHistory() {
    var dir = root.bulkRenameHistoryFile.substring(0, root.bulkRenameHistoryFile.lastIndexOf("/"))
    var json = JSON.stringify(root.bulkRenameHistory)
    saveBulkRenameHistoryProc.command = ["bash", "-c", "mkdir -p -- " + Util.shellQuote(dir) + " && printf '%s' " + Util.shellQuote(json) + " > " + Util.shellQuote(root.bulkRenameHistoryFile)]
    saveBulkRenameHistoryProc.running = true
  }

  Process {
    id: loadBookmarksProc
    command: ["cat", root.bookmarksFile]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.bookmarksLoaded = true
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        if (Array.isArray(parsed) && parsed.length > 0) {
          root.bookmarks = parsed
        } else {
          root.bookmarks = root.defaultBookmarks
          saveBookmarks()
        }
      }
    }
  }

  Process {
    id: saveBookmarksProc
  }

  Process {
    id: loadRecentProc
    command: ["cat", root.recentFile]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.recentLoaded = true
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        root.recentFiles = Array.isArray(parsed) ? parsed : []
      }
    }
  }

  Process {
    id: saveRecentProc
  }

  Process {
    id: loadSessionProc
    command: ["cat", root.sessionFile]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        var savedTabs = (parsed && Array.isArray(parsed.tabs))
          ? parsed.tabs.filter(function (t) { return t && typeof t.path === "string" && t.path.charAt(0) === "/" })
          : []
        if (savedTabs.length > 0) {
          root.tabs = savedTabs.map(function (t) { return { path: t.path, history: [t.path], historyIndex: 0 } })
          root.activeTabIndex = Math.max(0, Math.min(parsed.activeTabIndex || 0, root.tabs.length - 1))
          root.currentPath = root.tabs[root.activeTabIndex].path
          root.navHistory = [root.currentPath]
          root.navHistoryIndex = 0
        }
        root.refresh()
        if (!root.inArchive) root.startDirWatch(root.currentPath)
      }
    }
  }

  Process {
    id: saveSessionProc
  }

  Process {
    id: loadBulkRenameHistoryProc
    command: ["cat", root.bulkRenameHistoryFile]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.bulkRenameHistoryLoaded = true
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        root.bulkRenameHistory = Array.isArray(parsed) ? parsed : []
      }
    }
  }

  Process {
    id: saveBulkRenameHistoryProc
  }
}

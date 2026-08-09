import QtQuick
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
//
// Fase 6.A (josema): la I/O ya no lanza procesos de shell. Antes cada
// lectura era un `cat` (ProcessRunner→QProcess) y cada escritura un
// `bash -c 'mkdir -p ... && printf > ...'` (Detached); ahora todo pasa
// por Omafiles.Services.JsonStore, adaptador fino sobre el backend C++
// (QFile/QSaveFile/QJsonDocument). El parseo es en C++, la escritura es
// atómica y no hay forks. El contrato observable es el mismo: read() sigue
// siendo async (loaded llega en el siguiente ciclo), por eso loadSession()
// puede seguir disparando refresh()/startDirWatch ella sola.
Item {
  property Item root: null
  property Item tabOps: null

  // Escritura fire-and-forget de un JSON a disco -- JsonStore.write crea la
  // carpeta ~/.local/state/omafiles/ si hace falta y escribe de forma
  // atómica. Ninguna de las 4 llamadas de más abajo necesita saber cuándo
  // termina, así que se ignora el valor de retorno y la señal saved.
  function _saveJson(path, data) {
    JsonStore.write(path, data)
  }

  function loadBookmarks() {
    JsonStore.read(root.bookmarksFile)
  }

  function saveBookmarks() {
    _saveJson(root.bookmarksFile, BookmarksState.bookmarks)
  }

  function loadRecent() {
    JsonStore.read(root.recentFile)
  }

  function saveRecent() {
    _saveJson(root.recentFile, BookmarksState.recentFiles)
  }

  // Solo se llama en la primera apertura de la sesión de Quickshell, sin
  // ruta pedida por el host -- ver open(). Carga async (JsonStore.read);
  // refresh()/startDirWatch se disparan desde el handler de sessionFile en
  // cuanto sabe la ruta real, no aquí (evita listar homeDir de más si sí
  // había sesión).
  function loadSession() {
    JsonStore.read(root.sessionFile)
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
    JsonStore.read(root.bulkRenameHistoryFile)
  }

  function saveBulkRenameHistory() {
    _saveJson(root.bulkRenameHistoryFile, BookmarksState.bulkRenameHistory)
  }

  // Un único punto de entrega para las cuatro lecturas: JsonStore es un
  // singleton, así que loaded() se despacha por `path`. `data` ya viene
  // parseado desde C++ (objeto/array JS) o undefined si el fichero no
  // existe o el JSON era inválido -- se normaliza a null para conservar la
  // misma lógica de "válido o valor por defecto" que tenían los cuatro
  // ProcessRunner separados.
  Connections {
    target: JsonStore

    function onLoaded(path, data, ok) {
      var parsed = ok ? data : null

      if (path === root.bookmarksFile) {
        BookmarksState.bookmarksLoaded = true
        if (Array.isArray(parsed) && parsed.length > 0) {
          BookmarksState.bookmarks = parsed
        } else {
          BookmarksState.bookmarks = root.defaultBookmarks
          saveBookmarks()
        }
      } else if (path === root.recentFile) {
        BookmarksState.recentLoaded = true
        BookmarksState.recentFiles = Array.isArray(parsed) ? parsed : []
      } else if (path === root.sessionFile) {
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
        root.refresh()
        if (!ArchiveState.inArchive) root.startDirWatch(NavState.currentPath)
      } else if (path === root.bulkRenameHistoryFile) {
        BookmarksState.bulkRenameHistoryLoaded = true
        BookmarksState.bulkRenameHistory = Array.isArray(parsed) ? parsed : []
      }
    }
  }
}

import QtQuick
import "../state"

// Ciclo de vida de las pestañas/paneles: crear, cerrar, cambiar de activa,
// navegar/deshacer-historial de una pestaña que NO es la activa --
// vigésimo cuarto componente extraído de Omafiles.qml. `_goToPath()` (la
// navegación de la pestaña ACTIVA en sí) se queda en root -- es el núcleo
// de la navegación real, demasiado central para mover, y estas funciones
// ya lo llaman como `navController._goToPath(...)` sin problema.
Item {
  property Item root: null
  property Item navController: null

  // La ListView principal (id "list" en Omafiles.qml) -- guardar/restaurar
  // scroll al cambiar de pestaña.
  property Item list: null
  property Item archiveActions: null
  property Item previewLoader: null

  // Cierra la pestaña/panel en `index`, sea o no la activa (la × de cada
  // panel puede estar en uno que no es el que tiene el foco ahora mismo).
  function closeTabAt(index) {
    if (TabsState.tabs.length <= 1) { root.requestClose(); return }
    if (index === TabsState.activeTabIndex) { closeTab(); return }
    var next = TabsState.tabs.slice()
    next.splice(index, 1)
    TabsState.tabs = next
    if (TabsState.activeTabIndex > index) TabsState.activeTabIndex -= 1
  }

  // Navegar DENTRO de un panel que no es el activo -- no toca
  // NavState.currentPath/NavState.entries (esos son solo del panel activo), solo el
  // propio objeto de esa pestaña. Mantiene su historial igual que
  // navigateTo mantiene el de la pestaña activa.
  function navigateTabTo(index, path) {
    if (!path || index < 0 || index >= TabsState.tabs.length) return
    path = path.replace(/\/+$/, "") || "/"
    if (index === TabsState.activeTabIndex) { navController.navigateTo(path); return }
    var next = TabsState.tabs.slice()
    var tab = next[index]
    if (path === tab.path) return
    var h = (tab.history || [tab.path]).slice(0, (tab.historyIndex !== undefined ? tab.historyIndex : 0) + 1)
    h.push(path)
    next[index] = { path: path, history: h, historyIndex: h.length - 1 }
    TabsState.tabs = next
  }

  // Atrás/adelante para un panel que no es el activo -- mismo concepto que
  // navBack/navForward, pero leyendo/escribiendo el historial guardado en
  // ese objeto de pestaña en concreto en vez de TabsState.navHistory (que es
  // solo el de la activa).
  function navTabBack(index) {
    if (index === TabsState.activeTabIndex) { navController.navBack(); return }
    if (index < 0 || index >= TabsState.tabs.length) return
    var tab = TabsState.tabs[index]
    var hIdx = tab.historyIndex !== undefined ? tab.historyIndex : 0
    if (hIdx <= 0) return
    var hist = tab.history || [tab.path]
    var next = TabsState.tabs.slice()
    next[index] = { path: hist[hIdx - 1], history: hist, historyIndex: hIdx - 1 }
    TabsState.tabs = next
  }

  function navTabForward(index) {
    if (index === TabsState.activeTabIndex) { navController.navForward(); return }
    if (index < 0 || index >= TabsState.tabs.length) return
    var tab = TabsState.tabs[index]
    var hist = tab.history || [tab.path]
    var hIdx = tab.historyIndex !== undefined ? tab.historyIndex : 0
    if (hIdx >= hist.length - 1) return
    var next = TabsState.tabs.slice()
    next[index] = { path: hist[hIdx + 1], history: hist, historyIndex: hIdx + 1 }
    TabsState.tabs = next
  }

  function saveActiveTab() {
    var next = TabsState.tabs.slice()
    next[TabsState.activeTabIndex] = {
      path: NavState.currentPath, history: TabsState.navHistory, historyIndex: TabsState.navHistoryIndex,
      previewOpen: PreviewState.previewOpen, previewEntry: PreviewContentState.previewEntry, scrollY: list.contentY,
      inArchive: ArchiveState.inArchive, archivePath: ArchiveState.archivePath, archiveSubPath: ArchiveState.archiveSubPath,
      // La búsqueda (lupa) es del panel activo, no global: sin guardarla aquí
      // se "colaba" a la pestaña a la que cambiabas (searching/searchQuery viven
      // en NavState, singleton). Se guardan los RESULTADOS también, para
      // restaurarlos al instante sin re-lanzar la búsqueda. Ver _restoreTabSearch.
      searching: NavState.searching, searchQuery: NavState.searchQuery,
      searchTruncated: NavState.searchTruncated,
      searchEntries: NavState.searching ? NavState.entries : undefined
    }
    TabsState.tabs = next
  }

  // Restaura el historial atrás/adelante propio de `tab` como el "en curso"
  // -- usado por switchToTab/closeTab al aterrizar en una pestaña que no es
  // la que se acaba de crear (esa ya trae su historial propio desde cero).
  function _restoreTabHistory(tab) {
    TabsState.navHistory = tab.history || [tab.path]
    TabsState.navHistoryIndex = tab.historyIndex !== undefined ? tab.historyIndex : 0
  }

  // La preview (foto/vídeo/texto) es del panel activo, y _goToPath la
  // cierra siempre (selectOnly(-1) al navegar) -- sin esto, cambiar de
  // pestaña se veía como si la preview se perdiera aunque la pestaña
  // original la siguiera teniendo abierta. Se llama DESPUÉS de _goToPath,
  // que ya dejó currentPath listo para que loadPreview lea el fichero
  // correcto si es de texto.
  // Bug real: navegar DENTRO de un comprimido (inArchive/archivePath/
  // archiveSubPath) no era parte del estado guardado por pestaña -- al
  // cambiar de pestaña con el ratón y volver, _goToPath() ya había
  // salido del modo archivo sin que nada lo restaurase, así que la
  // pestaña aterrizaba en la carpeta real que contiene el .zip en vez de
  // en la ruta de dentro donde estaba navegando. Llamado DESPUÉS de
  // _goToPath (que es quien limpia inArchive), mismo patrón que
  // _restoreTabPreview/_restoreTabScroll.
  function _restoreTabArchive(tab) {
    if (tab.inArchive && tab.archivePath) {
      ArchiveState.inArchive = true
      ArchiveState.archivePath = tab.archivePath
      ArchiveState.archiveSubPath = tab.archiveSubPath || ""
      archiveActions.refreshArchiveListing()
    }
  }

  function _restoreTabPreview(tab) {
    if (tab.previewOpen && tab.previewEntry) {
      previewLoader.loadPreview(tab.previewEntry)
    } else {
      PreviewState.previewOpen = false
    }
  }

  // _goToPath() siempre deja list.contentY = list.originY (arriba del
  // todo) al navegar -- sin esto, volver a una pestaña en la que se había
  // bajado en la lista aterrizaba siempre en la fila 0, perdiendo la
  // posición aunque la carpeta en sí no hubiera cambiado. Se llama
  // DESPUÉS de _goToPath, mismo motivo que _restoreTabPreview: para
  // entonces el modelo (NavState.visibleEntries) ya está actualizado y
  // contentHeight ya refleja el listado correcto.
  // Esto es solo la restauración INMEDIATA (mientras el listProc que
  // _goToPath acaba de lanzar sigue en marcha) -- root._pendingScrollY
  // guarda la misma posición para que listProc la vuelva a aplicar ella
  // misma justo después de su propio positionViewAtBeginning() cuando
  // termine, que si no la pisaría (ver el comentario largo ahí, era el
  // origen real del parpadeo al cambiar de panel de fondo a activo con
  // la papelera).
  function _restoreTabScroll(tab) {
    var y = tab.scrollY || list.originY
    list.contentY = y
    root._pendingScrollY = y
  }

  // Restaura (o limpia) el modo búsqueda propio de `tab`. Se llama DESPUÉS de
  // _goToPath, que ya repobló NavState.entries con el listado normal de la
  // carpeta -- si esta pestaña estaba buscando, le devolvemos sus resultados
  // guardados encima. Si NO estaba buscando, hay que apagar el flag global
  // igualmente: la pestaña que dejamos podía estar en modo búsqueda y ese
  // estado, al ser de NavState (singleton), habría quedado activo aquí. Mismo
  // patrón que _restoreTabArchive/_restoreTabPreview.
  function _restoreTabSearch(tab) {
    if (tab.searching) {
      NavState.searching = true
      NavState.searchQuery = tab.searchQuery || ""
      NavState.searchTruncated = tab.searchTruncated || false
      if (tab.searchEntries !== undefined) NavState.entries = tab.searchEntries
    } else {
      NavState.searching = false
      NavState.searchQuery = ""
      NavState.searchTruncated = false
    }
  }

  function switchToTab(index) {
    if (index < 0 || index >= TabsState.tabs.length || index === TabsState.activeTabIndex) return
    if (root.hasBlockingOverlay) return
    // La lupa NO debe animar su expandir/colapsar por un cambio de pestaña: al
    // adoptar el estado de búsqueda de la nueva tab, `searching` cambia y la
    // barra haría la animación de minimizar/expandir en la tab a la que llegas
    // (se ve mal). Se suprime durante todo el cambio; snap en vez de animación.
    NavState.suppressSearchAnim = true
    saveActiveTab()
    TabsState.activeTabIndex = index
    _restoreTabHistory(TabsState.tabs[index])
    // El panel activo adopta el listado de la pestaña que ya estaba a la
    // vista como panel de fondo -- sin fade (ver root.suppressListFade), o
    // pasar el cursor por un panel produciría un parpadeo redundante. Se
    // limpia justo después: el único cambio de modelo que dispara el fade lo
    // hace _goToPath de forma síncrona (pinta desde tabEntriesCache), así que
    // para cuando vuelve ya se consumió.
    root.suppressListFade = true
    navController._goToPath(TabsState.tabs[index].path)
    root.suppressListFade = false
    _restoreTabArchive(TabsState.tabs[index])
    _restoreTabPreview(TabsState.tabs[index])
    _restoreTabSearch(TabsState.tabs[index])
    _restoreTabScroll(TabsState.tabs[index])
    NavState.suppressSearchAnim = false
  }

  function newTab() {
    saveActiveTab()
    TabsState.tabs = TabsState.tabs.concat([{ path: NavState.currentPath, history: [NavState.currentPath], historyIndex: 0 }])
    TabsState.activeTabIndex = TabsState.tabs.length - 1
    TabsState.navHistory = [NavState.currentPath]
    TabsState.navHistoryIndex = 0
  }

  // Para quien no use Ctrl+T -- una pestaña nueva ya apuntando a `path` (una
  // fila de carpeta, un marcador, una unidad), no a la carpeta actual.
  function openInNewTab(path) {
    if (!path) return
    saveActiveTab()
    TabsState.tabs = TabsState.tabs.concat([{ path: path, history: [path], historyIndex: 0 }])
    TabsState.activeTabIndex = TabsState.tabs.length - 1
    TabsState.navHistory = [path]
    TabsState.navHistoryIndex = 0
    navController._goToPath(path)
  }

  function closeTab() {
    if (TabsState.tabs.length <= 1) { root.requestClose(); return }
    NavState.suppressSearchAnim = true
    var next = TabsState.tabs.slice()
    next.splice(TabsState.activeTabIndex, 1)
    TabsState.tabs = next
    var newIndex = Math.min(TabsState.activeTabIndex, next.length - 1)
    TabsState.activeTabIndex = newIndex
    _restoreTabHistory(TabsState.tabs[newIndex])
    // Igual que switchToTab: la pestaña que queda ya estaba a la vista como
    // panel de fondo, así que se adopta sin fade (evita el parpadeo).
    root.suppressListFade = true
    navController._goToPath(TabsState.tabs[newIndex].path)
    root.suppressListFade = false
    _restoreTabArchive(TabsState.tabs[newIndex])
    _restoreTabPreview(TabsState.tabs[newIndex])
    _restoreTabSearch(TabsState.tabs[newIndex])
    _restoreTabScroll(TabsState.tabs[newIndex])
    NavState.suppressSearchAnim = false
  }

  function nextTab() {
    switchToTab((TabsState.activeTabIndex + 1) % TabsState.tabs.length)
  }
}

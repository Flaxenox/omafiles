import QtQuick
import "../state"

// Ciclo de vida de las pestañas/paneles: crear, cerrar, cambiar de activa,
// navegar/deshacer-historial de una pestaña que NO es la activa --
// vigésimo cuarto componente extraído de Omafiles.qml. `_goToPath()` (la
// navegación de la pestaña ACTIVA en sí) se queda en root -- es el núcleo
// de la navegación real, demasiado central para mover, y estas funciones
// ya lo llaman como `root._goToPath(...)` sin problema.
Item {
  property Item root: null
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
  // root.currentPath/root.entries (esos son solo del panel activo), solo el
  // propio objeto de esa pestaña. Mantiene su historial igual que
  // navigateTo mantiene el de la pestaña activa.
  function navigateTabTo(index, path) {
    if (!path || index < 0 || index >= TabsState.tabs.length) return
    path = path.replace(/\/+$/, "") || "/"
    if (index === TabsState.activeTabIndex) { root.navigateTo(path); return }
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
    if (index === TabsState.activeTabIndex) { root.navBack(); return }
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
    if (index === TabsState.activeTabIndex) { root.navForward(); return }
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
      path: root.currentPath, history: TabsState.navHistory, historyIndex: TabsState.navHistoryIndex,
      previewOpen: PreviewState.previewOpen, previewEntry: PreviewContentState.previewEntry, scrollY: list.contentY,
      inArchive: ArchiveState.inArchive, archivePath: ArchiveState.archivePath, archiveSubPath: ArchiveState.archiveSubPath
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
  // entonces el modelo (root.visibleEntries) ya está actualizado y
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

  function switchToTab(index) {
    if (index < 0 || index >= TabsState.tabs.length || index === TabsState.activeTabIndex) return
    if (root.hasBlockingOverlay) return
    saveActiveTab()
    TabsState.activeTabIndex = index
    _restoreTabHistory(TabsState.tabs[index])
    root._goToPath(TabsState.tabs[index].path)
    _restoreTabArchive(TabsState.tabs[index])
    _restoreTabPreview(TabsState.tabs[index])
    _restoreTabScroll(TabsState.tabs[index])
  }

  function newTab() {
    saveActiveTab()
    TabsState.tabs = TabsState.tabs.concat([{ path: root.currentPath, history: [root.currentPath], historyIndex: 0 }])
    TabsState.activeTabIndex = TabsState.tabs.length - 1
    TabsState.navHistory = [root.currentPath]
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
    root._goToPath(path)
  }

  function closeTab() {
    if (TabsState.tabs.length <= 1) { root.requestClose(); return }
    var next = TabsState.tabs.slice()
    next.splice(TabsState.activeTabIndex, 1)
    TabsState.tabs = next
    var newIndex = Math.min(TabsState.activeTabIndex, next.length - 1)
    TabsState.activeTabIndex = newIndex
    _restoreTabHistory(TabsState.tabs[newIndex])
    root._goToPath(TabsState.tabs[newIndex].path)
    _restoreTabArchive(TabsState.tabs[newIndex])
    _restoreTabPreview(TabsState.tabs[newIndex])
    _restoreTabScroll(TabsState.tabs[newIndex])
  }

  function nextTab() {
    switchToTab((TabsState.activeTabIndex + 1) % TabsState.tabs.length)
  }
}

import QtQuick

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
    if (root.tabs.length <= 1) { root.requestClose(); return }
    if (index === root.activeTabIndex) { closeTab(); return }
    var next = root.tabs.slice()
    next.splice(index, 1)
    root.tabs = next
    if (root.activeTabIndex > index) root.activeTabIndex -= 1
  }

  // Navegar DENTRO de un panel que no es el activo -- no toca
  // root.currentPath/root.entries (esos son solo del panel activo), solo el
  // propio objeto de esa pestaña. Mantiene su historial igual que
  // navigateTo mantiene el de la pestaña activa.
  function navigateTabTo(index, path) {
    if (!path || index < 0 || index >= root.tabs.length) return
    path = path.replace(/\/+$/, "") || "/"
    if (index === root.activeTabIndex) { root.navigateTo(path); return }
    var next = root.tabs.slice()
    var tab = next[index]
    if (path === tab.path) return
    var h = (tab.history || [tab.path]).slice(0, (tab.historyIndex !== undefined ? tab.historyIndex : 0) + 1)
    h.push(path)
    next[index] = { path: path, history: h, historyIndex: h.length - 1 }
    root.tabs = next
  }

  // Atrás/adelante para un panel que no es el activo -- mismo concepto que
  // navBack/navForward, pero leyendo/escribiendo el historial guardado en
  // ese objeto de pestaña en concreto en vez de root.navHistory (que es
  // solo el de la activa).
  function navTabBack(index) {
    if (index === root.activeTabIndex) { root.navBack(); return }
    if (index < 0 || index >= root.tabs.length) return
    var tab = root.tabs[index]
    var hIdx = tab.historyIndex !== undefined ? tab.historyIndex : 0
    if (hIdx <= 0) return
    var hist = tab.history || [tab.path]
    var next = root.tabs.slice()
    next[index] = { path: hist[hIdx - 1], history: hist, historyIndex: hIdx - 1 }
    root.tabs = next
  }

  function navTabForward(index) {
    if (index === root.activeTabIndex) { root.navForward(); return }
    if (index < 0 || index >= root.tabs.length) return
    var tab = root.tabs[index]
    var hist = tab.history || [tab.path]
    var hIdx = tab.historyIndex !== undefined ? tab.historyIndex : 0
    if (hIdx >= hist.length - 1) return
    var next = root.tabs.slice()
    next[index] = { path: hist[hIdx + 1], history: hist, historyIndex: hIdx + 1 }
    root.tabs = next
  }

  function saveActiveTab() {
    var next = root.tabs.slice()
    next[root.activeTabIndex] = {
      path: root.currentPath, history: root.navHistory, historyIndex: root.navHistoryIndex,
      previewOpen: root.previewOpen, previewEntry: root.previewEntry, scrollY: list.contentY,
      inArchive: root.inArchive, archivePath: root.archivePath, archiveSubPath: root.archiveSubPath
    }
    root.tabs = next
  }

  // Restaura el historial atrás/adelante propio de `tab` como el "en curso"
  // -- usado por switchToTab/closeTab al aterrizar en una pestaña que no es
  // la que se acaba de crear (esa ya trae su historial propio desde cero).
  function _restoreTabHistory(tab) {
    root.navHistory = tab.history || [tab.path]
    root.navHistoryIndex = tab.historyIndex !== undefined ? tab.historyIndex : 0
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
      root.inArchive = true
      root.archivePath = tab.archivePath
      root.archiveSubPath = tab.archiveSubPath || ""
      archiveActions.refreshArchiveListing()
    }
  }

  function _restoreTabPreview(tab) {
    if (tab.previewOpen && tab.previewEntry) {
      previewLoader.loadPreview(tab.previewEntry)
    } else {
      root.previewOpen = false
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
    if (index < 0 || index >= root.tabs.length || index === root.activeTabIndex) return
    if (root.hasBlockingOverlay) return
    saveActiveTab()
    root.activeTabIndex = index
    _restoreTabHistory(root.tabs[index])
    root._goToPath(root.tabs[index].path)
    _restoreTabArchive(root.tabs[index])
    _restoreTabPreview(root.tabs[index])
    _restoreTabScroll(root.tabs[index])
  }

  function newTab() {
    saveActiveTab()
    root.tabs = root.tabs.concat([{ path: root.currentPath, history: [root.currentPath], historyIndex: 0 }])
    root.activeTabIndex = root.tabs.length - 1
    root.navHistory = [root.currentPath]
    root.navHistoryIndex = 0
  }

  // Para quien no use Ctrl+T -- una pestaña nueva ya apuntando a `path` (una
  // fila de carpeta, un marcador, una unidad), no a la carpeta actual.
  function openInNewTab(path) {
    if (!path) return
    saveActiveTab()
    root.tabs = root.tabs.concat([{ path: path, history: [path], historyIndex: 0 }])
    root.activeTabIndex = root.tabs.length - 1
    root.navHistory = [path]
    root.navHistoryIndex = 0
    root._goToPath(path)
  }

  function closeTab() {
    if (root.tabs.length <= 1) { root.requestClose(); return }
    var next = root.tabs.slice()
    next.splice(root.activeTabIndex, 1)
    root.tabs = next
    var newIndex = Math.min(root.activeTabIndex, next.length - 1)
    root.activeTabIndex = newIndex
    _restoreTabHistory(root.tabs[newIndex])
    root._goToPath(root.tabs[newIndex].path)
    _restoreTabArchive(root.tabs[newIndex])
    _restoreTabPreview(root.tabs[newIndex])
    _restoreTabScroll(root.tabs[newIndex])
  }

  function nextTab() {
    switchToTab((root.activeTabIndex + 1) % root.tabs.length)
  }
}

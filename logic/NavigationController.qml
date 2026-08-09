import QtQuick
import "../state"
import "../services"
import "../Utils.js" as Utils

// Navegación/historial del panel activo -- vigésimo segundo componente
// extraído de Omafiles.qml. currentPath/tabEntriesCache/entries siguen
// en root (state/TabsState.qml ya documentaba que eran "demasiado
// centrales para mover" en un intento anterior; esta vez se mueve el
// CONTROLADOR, no el estado en sí). refresh/navigateTo/enter/goUp/
// navBack/navForward/startDirWatch/stopDirWatch/openWithDefault/
// _goToPath siguen expuestas como wrappers finos en root -- las llaman
// unos 10 ficheros distintos (KeyboardShortcuts, MountActions,
// Persistence, BookmarkOps, SearchOps, ArchiveActions, ActionEngine,
// BackgroundPanel, TabOps, FileListRow) y no compensa el riesgo de
// tocar todos esos sitios de llamada.
// El listado en sí (parseo/orden/trash-info.sh) vive en DirLister
// (Fase 1.6, josema) -- este componente ya NO es dueño de ningún
// Process propio, solo orquesta CUÁNDO listar y qué hacer con el
// resultado (scroll, selección pendiente...). BackgroundPanel instancia
// su propio DirLister por pestaña de fondo -- mismo mecanismo, sin
// compartir el Process (varias pestañas pueden listar rutas distintas
// a la vez).
Item {
  id: navCtrl
  property Item root: null
  property Item list: null
  property Item archiveActions: null
  property Item mountOps: null
  property Item bookmarkOps: null
  property Item selectionOps: null
  property Item sortOps: null

  // ---------- Refresco / vigilancia de directorio ----------
  function refresh() {
    // Centralizado aquí para que TODO lo que ya llama a refresh() (toggle
    // de ocultos, el "Refresh" de la paleta, el onExited de las acciones
    // de fichero...) recargue lo correcto sin tener que acordarse de
    // comprobar inArchive en cada sitio.
    if (ArchiveState.inArchive) { archiveActions.refreshArchiveListing(); return }
    dirLister.list(root.currentPath)
  }

  // Reasigna root.entries SOLO si el contenido de verdad cambió --
  // QML/ListView no compara el contenido de un array modelo, solo la
  // referencia, así que reasignar aunque los datos sean idénticos
  // dispara un relayout completo (recrea TODAS las filas desde cero).
  // Con pocas filas no se nota, pero con la papelera (agrega varios
  // discos, puede tener bastantes más filas, con subtítulos que a veces
  // envuelven a dos líneas) ese relayout tarda lo bastante como para
  // verse -- root.entries ya se había puesto al instante desde
  // tabEntriesCache en _goToPath, y este listProc "trae una copia fresca
  // por detrás" (ver el comentario ahí) que con la papelera llega
  // notablemente más tarde que con una carpeta normal, así que el doble
  // pintado (caché -> fresco) deja de fundirse en un solo frame y se ve
  // como un salto real (reportado por josema; mis tres intentos
  // anteriores -- trashInfo compartida, carrera de scroll, esperar a
  // trashInfo también en el panel activo -- atacaban mecanismos reales
  // pero no ESTE, que es el que de verdad causaba el salto).
  function _applyEntries(parsed) {
    // Comparación por contenido barata (Fase 10.A): antes eran otros dos
    // JSON.stringify del array completo. entriesEqual es O(n) sin
    // asignaciones.
    var changed = !Utils.entriesEqual(parsed, root.entries)
    if (changed) root.entries = parsed
    _finishListLoad(changed)
  }

  // Ver listProc.onFinished -- lo que queda por hacer una vez
  // root.entries ya está puesto (con la papelera, puede ser justo
  // después de trashInfoProc en vez de inmediatamente). resetView: false
  // cuando _applyEntries() decidió que el contenido no había cambiado de
  // verdad -- en ese caso list.contentY ya estaba bien (nadie lo tocó) y
  // no hace falta el reset+restauración de scroll de abajo.
  function _finishListLoad(resetView) {
    if (resetView) {
      // El array de arriba es un objeto nuevo, no una mutación del
      // anterior -- QML/Qt no siempre reancla bien el origen interno de
      // ListView (originY) al reemplazar el modelo entero así, sobre todo
      // si la lista anterior era más corta. `list.contentY = 0` (puesto
      // ANTES de lanzar este proceso, en toggleHidden/navigateTo/etc) no
      // basta porque corre contra el modelo VIEJO -- esto es lo que
      // realmente deja el hueco arriba del todo. positionViewAtBeginning()
      // es la forma correcta de QML de resetear origen+contentY juntos,
      // justo cuando el modelo nuevo ya está puesto.
      list.positionViewAtBeginning()
      // TabOps._restoreTabScroll() pone list.contentY a la posición
      // guardada justo DESPUÉS de pedir la navegación -- pero esa misma
      // navegación es la que dispara este listProc asíncrono, que siempre
      // acaba resetéandolo con el positionViewAtBeginning() de arriba. Si
      // este Process tarda más que esa restauración síncrona (la papelera,
      // que agrega varios discos, tarda notablemente más que una carpeta
      // normal), gana la carrera al revés. root._pendingScrollY es la
      // forma de que quien pidió la restauración sobreviva a este reset,
      // aplicándose EN el mismo tick que positionViewAtBeginning en vez de
      // antes.
      if (root._pendingScrollY >= 0) {
        list.contentY = root._pendingScrollY
      }
    }
    root._pendingScrollY = -1
    root.loaded = true
    var selectNames = root.pendingSelectNames
    root.pendingSelectNames = []
    var foundIndices = []
    if (selectNames.length > 0) {
      for (var i = 0; i < root.visibleEntries.length; i++) {
        if (selectNames.indexOf(root.visibleEntries[i].name) >= 0) foundIndices.push(i)
      }
    }
    if (foundIndices.length > 0) {
      // selectOnly() ya cubría el caso de 1 (el de siempre: marcador de
      // fichero, reciente, la mayoría de ShowItems reales). Varios a la
      // vez (ShowItems con multi-selección real en el llamador, ver
      // dbus-filemanager1.py) no tenían forma de aplicarse antes -- se
      // resaltaban todos, con el primero como "principal".
      SelectionState.selectedIndex = foundIndices[0]
      SelectionState.anchorIndex = foundIndices[0]
      SelectionState.selectedIndices = foundIndices
      if (PreviewState.previewOpen && foundIndices.length > 1) PreviewState.previewOpen = false
    } else if (SelectionState.selectedIndex >= root.visibleEntries.length) {
      SelectionState.selectedIndex = root.visibleEntries.length - 1
    }
  }

  // Refresco en vivo del panel ACTIVO -- antes nada se refrescaba solo:
  // conectar un USB o crear un fichero por terminal no aparecía hasta F5.
  // Deliberadamente solo el panel activo, no cada panel de fondo (mismo
  // criterio ya aplicado en todo el fichero: los paneles de fondo tienen
  // funcionalidad reducida). Si inotify-tools no está instalado, el
  // Process simplemente falla al arrancar y esto se queda como un no-op
  // silencioso -- mismo patrón de "opcional, degrada con gracia" que
  // ffmpegthumbnailer/pygmentize/pdftoppm.
  function startDirWatch(path) {
    // Fase 6.D (josema): vigilancia NATIVA primero (QFileSystemWatcher
    // dentro de DirectoryModel, inotify del kernel sin forkear
    // inotifywait). Si el modelo no puede vigilar (límite de descriptores,
    // ruta rara), watch() devuelve false y se cae al inotifywait de antes
    // -- fallback exigido por BACKEND_DESIGN.md, no sustitución ciega.
    if (!dirLister.watch(path)) {
      dirWatchProc.start(["inotifywait", "-m", "-q", "-e",
        "create,delete,moved_to,moved_from,modify,attrib,close_write", "--", path])
    }
  }

  function stopDirWatch() {
    dirLister.unwatch()
    dirWatchProc.stop()
  }

  // ---------- Navegación / historial ----------
  function navigateTo(path) {
    if (!path) return
    // Normaliza barras finales/dobles básicas sin depender de un proceso externo.
    path = path.replace(/\/+$/, "") || "/"
    _pushHistory(path)
    _goToPath(path)
  }

  // La navegación real (usada por navigateTo Y por atrás/adelante/cambio de
  // pestaña, que ya deciden ellos mismos la entrada de historial correcta y
  // no quieren que ésta se vuelva a tocar).
  function _goToPath(path) {
    // Cualquier navegación real (bookmark, atrás/adelante, cambio de
    // pestaña, editar la ruta a mano...) sale del modo "dentro de un
    // comprimido" -- currentPath nunca cambia mientras se navega DENTRO
    // del archivo (ver enter()/goUp()/inArchive), así que si esto se
    // ejecuta es que el usuario se fue a otro sitio de verdad.
    if (ArchiveState.inArchive) { ArchiveState.inArchive = false; ArchiveState.archivePath = ""; ArchiveState.archiveSubPath = "" }
    root.currentPath = path
    selectionOps.selectOnly(-1)
    EditModeState.renamingIndex = -1
    EditModeState.creatingFolder = false
    EditModeState.creatingFile = false
    EditModeState.editingPath = false
    // list.contentY nunca se corrige solo: si venías desplazado hacia abajo
    // en la carpeta anterior, esa posición de scroll se queda fija aunque
    // el listado nuevo no tenga nada ahí -- se ve como un hueco vacío
    // arriba del todo en vez de las primeras filas.
    list.contentY = list.originY
    // Si esta ruta ya estaba cargada en un panel de fondo (típico al
    // cambiar de pestaña pasando el cursor), se pinta con esos datos al
    // instante en vez de esperar a que listProc arranque -- sin esto se
    // veía un parpadeo con el listado de la pestaña anterior durante esos
    // milisegundos. refresh() de todas formas trae una copia fresca por
    // detrás enseguida, sustituyéndola sin que se note.
    if (root.tabEntriesCache[path]) root.entries = root.tabEntriesCache[path]
    refresh()
    startDirWatch(path)
  }

  function _pushHistory(path) {
    if (TabsState.navHistory[TabsState.navHistoryIndex] === path) return
    // Trunca cualquier "adelante" antes de añadir -- mismo comportamiento
    // que el historial de cualquier navegador.
    var h = TabsState.navHistory.slice(0, TabsState.navHistoryIndex + 1)
    h.push(path)
    TabsState.navHistory = h
    TabsState.navHistoryIndex = h.length - 1
  }

  function navBack() {
    if (TabsState.navHistoryIndex <= 0) return
    TabsState.navHistoryIndex -= 1
    _goToPath(TabsState.navHistory[TabsState.navHistoryIndex])
  }

  function navForward() {
    if (TabsState.navHistoryIndex >= TabsState.navHistory.length - 1) return
    TabsState.navHistoryIndex += 1
    _goToPath(TabsState.navHistory[TabsState.navHistoryIndex])
  }

  // Usado por BackgroundPanel (doble clic sobre un fichero en un panel de
  // fondo) y launchRecent() para no depender de Quickshell directamente
  // fuera de services/.
  // Detached (execDetached de verdad, sin pipes de stdout/stderr ni
  // seguimiento) + gtk-launch, NO xdg-open ni gio open -- tercer intento
  // real en la misma sesión (Fase 1.5, josema) hasta encontrar algo
  // fiable:
  //  1. xdg-open (Detached): bajo Hyprland (XDG_CURRENT_DESKTOP=Hyprland,
  //     no reconocido como gnome/kde/...) cae en su rama "generic", que
  //     ejecuta el Exec= del .desktop a mano IGNORANDO Terminal=true --
  //     para apps como nvim.desktop eso lanza nvim sin terminal ni TTY,
  //     colgado para siempre sin que se vea nada.
  //  2. gio open (ProcessRunner, con o sin "bash -c" de por medio, con o
  //     sin setsid): sí respeta Terminal=true en pruebas manuales desde
  //     una shell normal, pero lanzado desde el Process de Quickshell el
  //     terminal que abre por dentro para Terminal=true no sobrevivía de
  //     forma fiable (a veces sí, la mayoría no) -- no se encontró la
  //     causa exacta, pero mismo patrón de siempre: Quickshell.Io.Process
  //     con StdioCollector no es de fiar para lanzar algo que a su vez
  //     bifurca una app de larga duración.
  //  3. gtk-launch vía Detached (esta): mismo mecanismo YA verificado
  //     fiable en OpenWithOps.launchWith() ("Abrir con..."), que sí
  //     respeta Terminal=true. Solo falta resolver primero el id del
  //     .desktop por defecto (gtk-launch necesita un id, no una ruta).
  function openWithDefault(path) {
    Detached.run(["bash", "-c", 'id=$(xdg-mime query default "$(xdg-mime query filetype "$1")"); [ -n "$id" ] && exec gtk-launch "$id" "$1"', "_", path])
  }

  function enter(entry) {
    if (!entry) return
    if (ArchiveState.inArchive) {
      if (entry.type === "dir") {
        ArchiveState.archiveSubPath = ArchiveState.archiveSubPath ? ArchiveState.archiveSubPath + "/" + entry.name : entry.name
        archiveActions.refreshArchiveListing()
      } else {
        archiveActions.openFileInArchive(entry)
      }
      return
    }
    if (entry.type === "dir") {
      navigateTo(root.joinPath(root.currentPath, entry.name))
    } else if (archiveActions.isArchive(entry)) {
      archiveActions.enterArchive(root.joinPath(root.currentPath, entry.name))
    } else if (archiveActions.isIso(entry)) {
      mountOps.mountIso(entry)
    } else {
      var openPath = root.joinPath(root.currentPath, entry.name)
      openWithDefault(openPath)
      bookmarkOps.addRecent(openPath, entry.name)
    }
  }

  function goUp() {
    if (ArchiveState.inArchive) {
      if (ArchiveState.archiveSubPath === "") { archiveActions.exitArchive(); return }
      var slash = ArchiveState.archiveSubPath.lastIndexOf("/")
      ArchiveState.archiveSubPath = slash > 0 ? ArchiveState.archiveSubPath.substring(0, slash) : ""
      archiveActions.refreshArchiveListing()
      return
    }
    if (root.currentPath === "/") return
    var idx = root.currentPath.lastIndexOf("/")
    navigateTo(idx > 0 ? root.currentPath.substring(0, idx) : "/")
  }

  // "close_write" (fichero cerrado tras escribir) en vez de fiarse solo
  // de "modify" -- así una copia grande en curso no dispara un refresh
  // por cada bloque escrito, solo cuando el fichero realmente queda
  // listo. inotifywait -m no termina nunca solo (modo monitor); se mata
  // explícitamente (stop()) al navegar a otra carpeta o cerrar la
  // ventana, ver startDirWatch()/stopDirWatch().
  ProcessWatcher {
    id: dirWatchProc
    onLineRead: dirWatchDebounce.restart()
  }

  Timer {
    id: dirWatchDebounce
    // Varios eventos casi seguidos (copiar/mover/borrar varios ficheros
    // a la vez) colapsan en un solo refresh en vez de uno por evento.
    interval: 400
    // No refrescar mientras hay un nombre a medio escribir -- un
    // refresh en pleno renombrado podría reordenar la lista y dejar
    // renamingIndex apuntando a la fila equivocada (mismo tipo de bug
    // ya visto y arreglado para el caso de entrar en un archivo a medio
    // renombrar). Se pierde ese refresh puntual, pero el próximo evento
    // real (o una navegación normal) lo recupera.
    onTriggered: if (!root.hasPendingEdit) refresh()
  }

  // Dueño del Process de listado real -- ver logic/DirLister.qml. Solo
  // hay UNA instancia aquí (el panel activo solo lista una ruta a la
  // vez); cada BackgroundPanel tiene la suya propia.
  DirLister {
    id: dirLister
    pluginDir: root.pluginDir
    trashDir: root.trashDir
    showHidden: root.showHidden
    sortOps: navCtrl.sortOps
    onPathErrorChanged: root.currentPathError = dirLister.pathError
    onListed: _applyEntries(dirLister.entries)
    // Vigilancia nativa: el modelo avisa de un cambio -> mismo debounce +
    // guarda hasPendingEdit de siempre (abajo), solo cambia la FUENTE del
    // aviso (antes dirWatchProc/inotifywait, ahora el QFileSystemWatcher
    // del modelo). El inotifywait sigue como fallback (ver startDirWatch).
    onDirectoryChanged: dirWatchDebounce.restart()
  }
}

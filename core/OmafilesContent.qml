import QtQuick
import qs.Commons
import qs.Ui
import "../dialogs"
import "../panels"
import "../logic"
import "../shared"
import "../state"
import "../services"

// OmafilesContent -- el árbol visual completo + todo el wiring de
// Omafiles (Fase 3, josema: separar el composition root del frontend
// Quickshell). Contiene TODO lo que antes vivía directo en Omafiles.qml
// salvo lo específico del host: sin FloatingWindow, sin HostBridge, sin
// la property `shell`. Omafiles.qml (ahora un bootstrap fino del
// frontend Quickshell) instancia esto dentro de un HostBridge y conecta
// open()/close()/opened/closeRequested() por fuera -- ver ese fichero
// para el lado Quickshell del contrato.
Item {
  id: root

  property string homeDir: Env.get("HOME")
  property string pluginDir: homeDir + "/.config/omarchy/plugins/omafiles"
  // currentPath/entries/showHidden/searchQuery/visibleEntries viven ahora
  // en state/NavState.qml (Fase 11.A). Aquí solo quedan bindings finos de
  // compatibilidad para el árbol visual, que aún lee root.* -- se retirarán
  // al dividir OmafilesContent. logic/ ya lee/escribe NavState.* directo.
  property string currentPath: NavState.currentPath
  // tabs/activeTabIndex/navHistory/navHistoryIndex viven ahora en
  // state/TabsState.qml -- vigesimoprimer y último slice de la capa
  // state/.
  property var entries: NavState.entries
  // Caché de listados por ruta, alimentada por los paneles de fondo cada
  // vez que refrescan -- ver _goToPath().
  property var tabEntriesCache: ({})
  property bool searching: false
  property string deepSearchRoot: ""
  property string searchQuery: NavState.searchQuery
  // Antes la búsqueda recursiva se cortaba en 200 resultados sin decir
  // nada -- una búsqueda con muchas coincidencias parecía completa cuando
  // en realidad faltaban ítems. Ver runDeepSearch()/search-recursive.sh.
  property bool searchTruncated: false
  readonly property var visibleEntries: NavState.visibleEntries
  property bool opened: false
  property bool loaded: false
  // Mensaje si list-dir.sh no pudo listar currentPath (permisos, carpeta
  // borrada entre navegar y listar...) -- vacío = sin error, carpeta
  // realmente vacía o listado en curso.
  property string currentPathError: ""
  // Nombres de entrada a resaltar en cuanto termine el próximo listado --
  // lo usa open() cuando el payload pide "abre esta carpeta y selecciona
  // estos ficheros" (caso ShowItems de org.freedesktop.FileManager1, que
  // puede llegar con varios URIs de golpe -- ej. varias descargas
  // seleccionadas en Firefox y "Mostrar en el gestor de archivos"). Un
  // solo fichero es simplemente un array de 1.
  property var pendingSelectNames: []

  // Posición de scroll pendiente de restaurar EN CUANTO termine el
  // próximo listProc -- ver el comentario largo junto a
  // positionViewAtBeginning() en listProc, quien lo consume. -1 = nada
  // pendiente (sentinel, ya que 0 es una posición de scroll válida en sí
  // misma).
  property real _pendingScrollY: -1

  // ---------- Paneles ----------
  // Cada pestaña abierta se ve a la vez como un panel propio, lado a lado
  // (sustituye a la vista dividida de antes, que era un segundo panel fijo
  // aparte -- ahora cualquier pestaña ES ya un panel visible). Solo el panel
  // ACTIVO tiene la lista/navegación completa de toda la vida (root.entries,
  // marquee, menú contextual...); el resto son paneles sencillos (solo
  // navegar con doble clic y arrastrar), cada uno con su propio listado.
  property int refreshTick: 0

  // undoStack/redoStack viven ahora en state/UndoState.qml (singleton) --
  // tercer slice de la capa state/. Lógica sin cambios en
  // logic/ActionEngine.qml.

  function pushUndo(label, undoFn, redoFn) {
    registry.actionEngine.pushUndo(label, undoFn, redoFn)
  }

  function undoLast() {
    registry.actionEngine.undoLast()
  }

  function redoLast() {
    registry.actionEngine.redoLast()
  }

  property bool showHidden: NavState.showHidden

  // selectedIndex/selectedIndices/anchorIndex/marquee* viven ahora en
  // state/SelectionState.qml (singleton, pragma Singleton) -- primer
  // piloto de la capa state/ (ver [[project_omafiles_architecture_rules]]),
  // en vez de properties sueltas aquí pasadas por prop-drilling. La lógica
  // que las manipula sigue en logic/SelectionOps.qml sin cambios.
  // Altura real medida de una fila (todas iguales, ver updateMarqueeSelection).
  // Sirve para calcular la altura del footer sin pasar por
  // list.contentHeight -- que en esta versión de Qt incluye al propio
  // footer, y usarlo ahí sería una propiedad que depende de sí misma
  // (confirmado en vivo: "Binding loop detected for property height").
  property real measuredRowHeight: 0

  readonly property var sortKeys: ["name", "size", "mtime", "type"]
  readonly property var sortKeyLabels: ({ name: "Name", size: "Size", mtime: "Date", type: "Type" })
  // sortKey/sortDesc viven ahora en state/SortState.qml -- decimotercer
  // slice de la capa state/, completa logic/SortOps.qml.

  // renamingIndex/creatingFolder/creatingFile/editingPath viven ahora en
  // state/EditModeState.qml -- decimoctavo slice de la capa state/.
  // Hay una edición sin confirmar en el panel activo (nombre a medio
  // escribir) -- usado para no tirarla al vuelo por un simple hover sobre
  // otro panel (ver el HoverHandler de bgPanel más abajo).
  readonly property bool hasPendingEdit: EditModeState.renamingIndex >= 0 || EditModeState.creatingFolder || EditModeState.creatingFile || EditModeState.editingPath

  // Bug real (auditoría 2026-08-05): cualquier diálogo con un paso de
  // "confirmar" que relee root.currentPath/registry.selectionOps.selectedEntries() EN EL
  // MOMENTO DEL CLIC (no al abrirse) puede acabar actuando sobre la
  // carpeta equivocada si la pestaña activa cambia mientras el diálogo
  // sigue abierto -- y nada impedía que cambiara, porque el hover-para-
  // activar-panel solo se bloqueaba para hasPendingEdit/contextMenuOpen,
  // no para el resto de diálogos (chmod, abrir-con, conflictos al pegar/
  // extraer/comprimir/renombrar en lote/soltar, confirmar borrado,
  // paleta, conectar a servidor, propiedades). En vez de capturar la
  // ruta a mano en cada sitio, un único punto de bloqueo en
  // switchToTab() cubre todos los casos de golpe: mientras cualquiera de
  // estos está abierto, la pestaña activa (y su currentPath) no se
  // puede mover por debajo del diálogo.
  readonly property bool hasBlockingOverlay: root.hasPendingEdit || ContextMenuState.contextMenuOpen
    || root.pendingDeleteNames.length > 0 || ConflictState.renameConflictOpen || ConflictState.pasteConflictOpen
    || ConflictState.extractConflictOpen || ConflictState.compressConflictOpen || ConflictState.bulkRenameConflictOpen
    || ConflictState.dropConflictOpen || ConflictState.newFileConflictOpen || ConflictState.newFolderConflictOpen
    || PaletteState.paletteOpen || PreviewState.openWithOpen || DialogsState.bulkRenameOpen
    || ChmodState.chmodOpen || PropertiesState.propertiesOpen || DialogsState.connectServerOpen

  // actionBusy/actionLabel/actionProgressPct/actionTotalBytes/
  // actionProgressDestPaths/_actionOnSuccess viven ahora en
  // state/ActionState.qml -- duodécimo slice de la capa state/, completa
  // la migración de logic/ActionEngine.qml (undoStack/redoStack ya estaban
  // en state/UndoState.qml). actionBusyDots se queda aquí -- animación
  // puramente visual, ver el Timer más abajo.
  property string actionBusyDots: ""

  // clipboardPaths/clipboardMode viven ahora en state/ClipboardState.qml
  // (singleton) -- segundo slice de la capa state/, mismo patrón que
  // SelectionState. Lógica sin cambios en logic/ClipboardOps.qml.

  property var pendingDeleteNames: []

  // pendingRename/renameConflictOpen, pasteConflictNames/pasteConflictOpen,
  // pendingExtract/extractConflictNames/extractConflictOpen,
  // pendingCompress/compressConflictOpen, pendingBulkRename/
  // bulkRenameInternalDupes/bulkRenameConflictCount/bulkRenameConflictOpen,
  // dropPendingSources/dropTargetDir/dropIsMove/dropConflictNames/
  // dropConflictOpen viven ahora en state/ConflictState.qml (singleton) --
  // cuarto slice de la capa state/. Lógica sin cambios en
  // logic/ConflictActions.qml y demás.

  // dropHoverIndex/dropHoverPath viven ahora en state/DropHoverState.qml --
  // decimoséptimo slice de la capa state/.

  // contextMenuOpen/X/Y/Actions viven ahora en state/ContextMenuState.qml,
  // paletteOpen/Query/Index en state/PaletteState.qml, y previewOpen/
  // openWithOpen/openWithApps/openWithEntry en state/PreviewState.qml --
  // quinto, sexto y séptimo slice de la capa state/.

  property bool gPending: false

  // bulkRenameOpen/Pattern, shortcutsHelpOpen y connectServerOpen/Uri/
  // Error/networkConnecting viven ahora en state/DialogsState.qml --
  // undécimo slice de la capa state/.

  // chmodOpen/Names/Mixed/Mode/HasDir/Recursive/OriginalModes viven ahora
  // en state/ChmodState.qml -- octavo slice de la capa state/.

  // propertiesOpen/Entry/Size/SizeLoading/Perms/Owner/Mtime/RequestId/
  // _propertiesStatOwner/_propertiesDuOwner/Multi/Count viven ahora en
  // state/PropertiesState.qml -- noveno slice de la capa state/.

  readonly property var tarExt: ["tar", "gz", "tgz", "bz2", "tbz", "xz", "txz"]

  // previewEntry/Text/IsText/Highlighted/PdfImage/AudioInfo/RequestId/
  // _previewTextOwner/_previewHighlightOwner/_previewPdfOwner/
  // _previewAudioOwner viven ahora en state/PreviewContentState.qml --
  // décimo slice de la capa state/.

  property string trashDir: root.homeDir + "/.local/share/Trash/files"
  // trashInfo vive ahora en state/TrashState.qml -- decimonoveno slice
  // de la capa state/.
  // mounts/networkMounts viven ahora en state/MountsState.qml --
  // decimoquinto slice de la capa state/.

  // Navegar dentro de un .zip/.7z/.rar/.tar sin extraerlo -- root.currentPath
  // NUNCA cambia mientras esto está activo (sigue siendo la carpeta real
  // que contiene el archivo); root.entries pasa a venir de list-archive.sh
  // en vez de list-dir.sh. Deliberadamente de solo lectura: sin selección
  // múltiple/menú contextual/renombrar/borrar/chmod/arrastrar -- ver los
  // guards "if (ArchiveState.inArchive) return" en cada acción que muta
  // disco. inArchive/archivePath/archiveSubPath viven ahora en
  // state/ArchiveState.qml -- vigésimo slice de la capa state/.

  readonly property var defaultBookmarks: [
    { label: "Home", path: root.homeDir },
    { label: "Documents", path: root.homeDir + "/Documents" },
    { label: "Downloads", path: root.homeDir + "/Downloads" },
    { label: "Pictures", path: root.homeDir + "/Pictures" },
    { label: "Videos", path: root.homeDir + "/Videos" },
    { label: "Music", path: root.homeDir + "/Music" },
    { label: "Projects", path: root.homeDir + "/Projects" },
    { label: "Trash", path: root.homeDir + "/.local/share/Trash/files" }
  ]

  property string bookmarksFile: root.homeDir + "/.local/state/omafiles/bookmarks.json"
  property string recentFile: root.homeDir + "/.local/state/omafiles/recent.json"
  property string sessionFile: root.homeDir + "/.local/state/omafiles/session.json"
  property string bulkRenameHistoryFile: root.homeDir + "/.local/state/omafiles/bulk-rename-history.json"
  // bookmarks/recentFiles/recentLoaded/bulkRenameHistory/
  // bulkRenameHistoryLoaded/bookmarksLoaded viven ahora en
  // state/BookmarksState.qml -- decimosexto slice de la capa state/.

  readonly property var imageExt: ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
  readonly property var videoExt: ["mp4", "mkv", "webm", "avi", "mov", "flv", "m4v"]
  readonly property var audioExt: ["mp3", "flac", "wav", "ogg", "m4a", "opus"]
  readonly property var archiveExt: ["zip", "tar", "gz", "xz", "rar", "7z", "bz2", "zst"]
  readonly property var codeExt: ["js", "ts", "py", "lua", "sh", "c", "cpp", "h", "rs", "go", "html", "css", "json", "qml", "md", "yml", "yaml", "toml"]

  // ---------- Tipo de fichero (extensión/icono) ----------
  // extOf/iconFor/isImage/isVideo/isAudio/isPdf viven ahora en
  // logic/FileTypeUtils.qml -- envoltorios de una línea, ver el comentario
  // de ese fichero (38 sitios de llamada externos, mismo criterio que
  // ActionEngine).
  function extOf(name) { return registry.fileTypeUtils.extOf(name) }
  function iconFor(entry) { return registry.fileTypeUtils.iconFor(entry) }
  function isImage(entry) { return registry.fileTypeUtils.isImage(entry) }
  function isVideo(entry) { return registry.fileTypeUtils.isVideo(entry) }
  function isAudio(entry) { return registry.fileTypeUtils.isAudio(entry) }
  function isPdf(entry) { return registry.fileTypeUtils.isPdf(entry) }

  // ---------- Miniaturas de vídeo (ffmpegthumbnailer, en cola de 1 a la vez) ----------
  property string thumbCacheDir: root.homeDir + "/.cache/omafiles/thumbnails"
  // videoThumbReady/thumbQueue/thumbBusy viven ahora en
  // state/VideoThumbState.qml -- decimocuarto slice de la capa state/.

  // simpleHash/thumbKeyFor/videoThumbPath: movidas a Utils.js (funciones
  // puras). `basePath`/cacheDir ya no son opcionales -- cada llamada de
  // aquí en adelante los pasa explícitos (ver comentario en Utils.js).

  // ---------- Selección (individual + lazo) ----------

  // ---------- Refresco / vigilancia de directorio ----------
  // La lógica real vive en logic/NavigationController.qml (navController
  // más abajo) -- estos son wrappers finos porque refresh/startDirWatch/
  // stopDirWatch los llaman ~10 ficheros distintos (KeyboardShortcuts,
  // MountActions, Persistence, ArchiveActions, ActionEngine...) y no
  // compensa el riesgo de tocar todos esos sitios de llamada.
  function refresh() { registry.navController.refresh() }
  function startDirWatch(path) { registry.navController.startDirWatch(path) }
  function stopDirWatch() { registry.navController.stopDirWatch() }


  // addRecent/removeRecent/clearRecent/addBulkRenameHistory,
  // removeBookmark/addBookmark/iconForBookmark/isBookmarked,
  // iconForMount/iconForNetworkMount/networkMountActions viven ahora en
  // logic/BookmarkOps.qml.
  // parseMounts/parseNetworkMounts: movidas a Utils.js (funciones puras).


  // ---------- Papelera ----------
  function emptyTrash() {
    // "gio trash --empty" solo vacía la papelera de casa -- ahora que
    // la vista agrega la de cualquier disco montado (ver
    // trash-roots.sh), vaciar tiene que cubrir las mismas o el botón
    // dejaría cosas huérfanas afirmando haber vaciado del todo.
    runAction("bash " + Util.shellQuote(root.pluginDir + "/empty-trash.sh"), "Emptying trash…")
  }

  // parseEntries: movida a Utils.js (función pura, comentario completo
  // sobre el protocolo NUL-delimitado está ahí ahora).

  // naturalCompare: movida a Utils.js (función pura).

  // ---------- Orden de la lista ----------
  // compareEntries/sortEntries/sortLabel/setSort/cycleSort/reverseSort
  // viven ahora en logic/SortOps.qml.

  // ---------- Navegación / historial / pestañas ----------
  function joinPath(base, name) {
    return base === "/" ? "/" + name : base + "/" + name
  }

  // La lógica real de navegación/historial vive en
  // logic/NavigationController.qml (navController más abajo) -- wrappers
  // finos por el mismo motivo que refresh()/startDirWatch() arriba
  // (llamados desde KeyboardShortcuts, MountActions, BookmarkOps,
  // ArchiveActions, TabOps, FileListRow, BackgroundPanel...). _goToPath
  // también se expone así -- TabOps ya la llama como root._goToPath(...).
  function navigateTo(path) { registry.navController.navigateTo(path) }
  function _goToPath(path) { registry.navController._goToPath(path) }
  function navBack() { registry.navController.navBack() }
  function navForward() { registry.navController.navForward() }
  function openWithDefault(path) { registry.navController.openWithDefault(path) }
  function enter(entry) { registry.navController.enter(entry) }
  function goUp() { registry.navController.goUp() }

  // ---------- Ciclo de vida (abrir/cerrar la ventana del host) ----------
  // Host-initiated open/close (`shell toggle`/`shell summon`/`shell hide`).
  // `payload` es "<ruta>" o "<ruta>\n<nombre-a-seleccionar>" en texto
  // plano (o "" / "{}" si no hay ninguna) -- la manda `scripts/open-path.sh`
  // (xdg-open/.desktop, sin selección) o `scripts/dbus-filemanager1.py`
  // (interfaz org.freedesktop.FileManager1, con selección para ShowItems).
  function open(payload) {
    root.opened = true

    var nlIdx = payload ? payload.indexOf("\n") : -1
    var folderPart = nlIdx >= 0 ? payload.substring(0, nlIdx) : payload
    // Varios nombres a seleccionar de golpe se separan con \x1f (ASCII
    // Unit Separator) -- un solo nombre sin \x1f sigue funcionando igual
    // que antes (array de 1). Ver dbus-filemanager1.py, que ahora agrupa
    // varios URIs de la misma carpeta en un único summon() con todos los
    // nombres, en vez de un summon (y una pestaña) por URI.
    var selectPart = nlIdx >= 0 ? payload.substring(nlIdx + 1) : ""
    var selectNames = selectPart ? selectPart.split("\x1f") : []
    var targetPath = (folderPart && folderPart.charAt(0) === "/") ? folderPart : ""

    if (targetPath) root.pendingSelectNames = selectNames

    var restoringSession = false
    if (!root.loaded) {
      if (targetPath) {
        NavState.currentPath = targetPath
        TabsState.tabs = [{ path: targetPath, history: [targetPath], historyIndex: 0 }]
        TabsState.navHistory = [targetPath]
        TabsState.navHistoryIndex = 0
        root.refresh()
      } else {
        // Primera apertura de esta sesión de Quickshell sin una ruta
        // pedida por el host -- intenta restaurar carpeta/pestañas de la
        // sesión anterior (session.json) en vez de abrir siempre en
        // homeDir. loadSession() dispara refresh()/startDirWatch ella
        // sola en cuanto sabe la ruta real (leer el fichero es async), así
        // que aquí no se hace -- evita listar homeDir de más para tirarlo
        // enseguida si sí había sesión guardada.
        restoringSession = true
        registry.persistence.loadSession()
      }
    } else if (targetPath) {
      // Ya estaba cargado antes (uso normal previo): abre en pestaña
      // nueva para no perder la ubicación en la que ya estaba el usuario.
      registry.tabOps.newTab()
      root.navigateTo(targetPath)
      registry.tabOps.saveActiveTab()
    }

    if (!BookmarksState.bookmarksLoaded) registry.persistence.loadBookmarks()
    if (!BookmarksState.recentLoaded) registry.persistence.loadRecent()
    if (!BookmarksState.bulkRenameHistoryLoaded) registry.persistence.loadBulkRenameHistory()
    registry.mountOps.refreshMounts()
    registry.mountOps.refreshNetworkMounts()
    // Cubre los dos casos restantes: primera carga con target (currentPath
    // recién puesto, arriba) y reabrir apuntando a un target (navigateTo ya
    // lo arrancó dentro de _goToPath, esto solo lo reafirma sobre la misma
    // ruta final) o reabrir SIN target (la ventana estaba cerrada -> close()
    // paró el watcher -> sin esto se reabriría mostrando una carpeta sin
    // vigilar). El caso restante (restoringSession) ya lo cubre
    // Persistence.loadSession() por su cuenta.
    if (!restoringSession && !ArchiveState.inArchive) root.startDirWatch(root.currentPath)
  }

  function close() {
    registry.persistence.saveSession()
    root.opened = false
    root.stopDirWatch()
    EditModeState.renamingIndex = -1
    EditModeState.creatingFolder = false
    EditModeState.creatingFile = false
    EditModeState.editingPath = false
    root.pendingDeleteNames = []
    ContextMenuState.contextMenuOpen = false
    // keepLoaded:true mantiene vivo el componente entre cierres -- sin
    // resetear esto, la próxima vez que se abra la ventana aparecería el
    // mismo diálogo/panel todavía abierto de la sesión anterior.
    PropertiesState.propertiesOpen = false
    DialogsState.shortcutsHelpOpen = false
    ChmodState.chmodOpen = false
    PreviewState.openWithOpen = false
    DialogsState.bulkRenameOpen = false
    PreviewState.previewOpen = false
    root.searching = false
    PaletteState.paletteOpen = false
    ConflictState.renameConflictOpen = false
    ConflictState.pasteConflictOpen = false
    ConflictState.dropConflictOpen = false
    ConflictState.extractConflictOpen = false
    ConflictState.pendingExtract = null
    ConflictState.compressConflictOpen = false
    ConflictState.pendingCompress = null
    ConflictState.bulkRenameConflictOpen = false
    ConflictState.pendingBulkRename = null
    DialogsState.connectServerOpen = false
  }

  // User-initiated close (Esc, cerrar la última pestaña, botón de cerrar de
  // la ventana). Antes hablaba con el host directamente (root.shell.hide());
  // ahora solo emite closeRequested() -- Omafiles.qml (el bootstrap del
  // frontend Quickshell) decide si eso significa avisar al host o cerrar
  // directo, sin que este fichero sepa nada de Quickshell.
  signal closeRequested()

  function requestClose() {
    root.closeRequested()
  }


  // onSuccess (opcional) se llama SOLO si el comando termina con exit 0 --
  // úsalo para todo lo que no deba pasar si la acción en realidad falló
  // (sobre todo pushUndo: un undo registrado para algo que nunca ocurrió en
  // disco es peor que no tener undo). Devuelve true si el comando se lanzó,
  // false si se descartó porque ya había otra acción en marcha (el llamador
  // decide si eso merece avisar al usuario).
  function runAction(cmd, busyLabel, onSuccess) {
    return registry.actionEngine.runAction(cmd, busyLabel, onSuccess)
  }

  function chainCmds(cmds) {
    return registry.actionEngine.chainCmds(cmds)
  }

  function cancelAction() {
    registry.actionEngine.cancelAction()
  }

  function startCopyProgress(sourcePaths, destPaths) {
    registry.actionEngine.startCopyProgress(sourcePaths, destPaths)
  }

  // Copia nativa (Fase 13.A): sustituye al `cp` shell en runPaste/runDrop.
  // `pairs` = [{ src, dest }], overwrite = el diálogo eligió sobrescribir.
  function copyFiles(pairs, busyLabel, overwrite, onDone) {
    return registry.actionEngine.runNativeCopy(pairs, busyLabel, overwrite, onDone)
  }

  // Movimiento nativo (Fase 13.B): sustituye al `mv` shell en runPaste/
  // runDrop. Mismo modelo de undo -- el llamador registra el undo/redo en
  // onDone, reutilizando moveFiles con los pares invertidos/originales.
  function moveFiles(pairs, busyLabel, overwrite, onDone) {
    return registry.actionEngine.runNativeMove(pairs, busyLabel, overwrite, onDone)
  }

  function openTerminalHere() {
    // ProcessRunner, no Detached -- mismo motivo que openWithDefault().
    registry.openProc.start(["xdg-terminal-exec", "--dir=" + root.currentPath])
  }

  // ---------- Fachada operativa (delegada a core/CommandFacade.qml) ----------
  // Fase 11.C: los cuerpos de estos builders viven en CommandFacade; aquí
  // quedan delegados finos para que paneles/diálogos/KeyboardShortcuts sigan
  // llamando root.X()/hostRoot.X() sin cambios.
  function paletteCommands() { return commandFacade.paletteCommands() }
  function filteredPaletteCommands() { return commandFacade.filteredPaletteCommands() }
  function openPalette() { commandFacade.openPalette() }
  function closePalette() { commandFacade.closePalette() }
  function runPaletteCommand(index) { commandFacade.runPaletteCommand(index) }
  function openContextMenu(x, y, actions) { commandFacade.openContextMenu(x, y, actions) }
  function itemActions() { return commandFacade.itemActions() }
  function emptyAreaActions() { return commandFacade.emptyAreaActions() }
  function openBookmark(bookmark) { commandFacade.openBookmark(bookmark) }
  function openRecent(item) { commandFacade.openRecent(item) }
  function launchRecent(item) { commandFacade.launchRecent(item) }
  function bookmarkActions(bookmark) { return commandFacade.bookmarkActions(bookmark) }
  function mountActions(mount) { return commandFacade.mountActions(mount) }
  function pathSegments() { return commandFacade.pathSegments() }
  function pathSegmentsFor(targetPath) { return commandFacade.pathSegmentsFor(targetPath) }

  // Autoregistro como gestor de archivos del sistema (MimeType inode/
  // directory + org.freedesktop.FileManager1) -- se lanza una vez al
  // cargar el plugin, sin esperar a que el usuario abra la ventana ni
  // tenga que ejecutar nada a mano. El script es idempotente (ver
  // scripts/install-integrations.sh), así que llamarlo en cada arranque
  // del shell es barato y seguro.

  // dirWatchProc/dirWatchDebounce/listProc/trashInfoProc viven ahora en
  // logic/NavigationController.qml (navController más abajo), junto con
  // el resto del controlador de navegación/listado.

  // Discos/red no tienen un evento fácil de vigilar aquí (habría que
  // suscribirse a señales D-Bus de UDisks2/GVfs) -- un polling modesto
  // es la opción honesta dado el alcance: enchufar un USB o que una
  // ubicación de red se caiga se nota en unos segundos en vez de nunca
  // (antes) o de tener que montar infraestructura D-Bus (después,
  // quizás). "running: root.opened" para que no siga en marcha de fondo
  // con la ventana cerrada.

  // ---------- Controladores (logic/) ----------
  // Fase 11.C: OmafilesContent ya NO instancia los controladores. Su ÚNICO
  // propietario es core/ControllerRegistry.qml (ownership única de la
  // auditoría 2026-08-09). Aquí se instancia el registro y se exponen sus
  // controladores como alias para que la fachada operativa y la capa visual
  // los referencien por el mismo nombre, sin god object ni reescribir cada
  // sitio de llamada.
  ControllerRegistry {
    id: registry
    root: root
    list: mainLayout.list
  }

  // Fachada operativa (builders de menús/comandos/migas). Fase 11.C.
  CommandFacade {
    id: commandFacade
    root: root
    archiveActions: registry.archiveActions
    bookmarkOps: registry.bookmarkOps
    clipboardOps: registry.clipboardOps
    conflictActions: registry.conflictActions
    deleteOps: registry.deleteOps
    fileOps: registry.fileOps
    mountOps: registry.mountOps
    openWithOps: registry.openWithOps
    propertiesLoader: registry.propertiesLoader
    renameOps: registry.renameOps
    searchOps: registry.searchOps
    selectionOps: registry.selectionOps
    sortOps: registry.sortOps
    tabOps: registry.tabOps
  }

  // Wiring de ciclo de vida y temporizadores. Fase 11.C.
  AppBindings {
    id: appBindings
    root: root
    mountOps: registry.mountOps
  }



  MainLayout {
    id: mainLayout
    anchors.fill: parent
    root: root
    bookmarkOps: registry.bookmarkOps
    mountOps: registry.mountOps
    dragDropOps: registry.dragDropOps
    videoThumbs: registry.videoThumbs
    fileMeta: registry.fileMeta
    tabOps: registry.tabOps
    sortOps: registry.sortOps
    searchOps: registry.searchOps
    selectionOps: registry.selectionOps
    conflictActions: registry.conflictActions
    previewLoader: registry.previewLoader
    fileOps: registry.fileOps
    renameOps: registry.renameOps
    clipboardOps: registry.clipboardOps
    deleteOps: registry.deleteOps
    gTimer: appBindings.gTimer
    deleteConfirm: dialogLayer.deleteConfirm
    renameConflictConfirm: dialogLayer.renameConflictConfirm
    extractConflictConfirm: dialogLayer.extractConflictConfirm
    compressConflictConfirm: dialogLayer.compressConflictConfirm
    bulkRenameConflictConfirm: dialogLayer.bulkRenameConflictConfirm
    newFileConflictConfirm: dialogLayer.newFileConflictConfirm
    newFolderConflictConfirm: dialogLayer.newFolderConflictConfirm
  }

  // ---------- Capa de diálogos/overlays (Fase 11.B) ----------
  // Hermana de MainLayout (ambas anchors.fill: parent) -- antes hija de la
  // tarjeta; geométricamente idéntico (la tarjeta llena root). Los siete
  // ConfirmDialog los expone DialogLayer y MainLayout los recibe para su
  // ActiveFileList.
  DialogLayer {
    id: dialogLayer
    anchors.fill: parent
    root: root
    list: mainLayout.list
    conflictActions: registry.conflictActions
    mountOps: registry.mountOps
    fileOps: registry.fileOps
    openWithOps: registry.openWithOps
    deleteOps: registry.deleteOps
    renameOps: registry.renameOps
    archiveActions: registry.archiveActions
    clipboardOps: registry.clipboardOps
    dragDropOps: registry.dragDropOps
  }
}

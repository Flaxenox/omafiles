import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "dialogs"
import "panels"
import "logic"
import "shared"
import "state"
import "Utils.js" as Utils

// Omafiles -- explorador de archivos para Omarchy.
// Ventana normal (FloatingWindow, tileable en Hyprland como cualquier otra
// app), no un overlay modal. Barra lateral con accesos y unidades (montar/
// expulsar), ruta editable a mano, orden por nombre/tamaño/fecha/tipo
// (tecla "s"/"S"), menú contextual y paleta de comandos (Ctrl+P) para todas
// las acciones de fichero, avisos de conflicto al copiar/pegar/renombrar,
// propiedades, drag & drop (dentro y con otras apps), lazo de selección,
// panel dividido opcional.
Item {
  id: root

  property string homeDir: Quickshell.env("HOME")
  property string pluginDir: homeDir + "/.config/omarchy/plugins/omafiles"
  property string currentPath: homeDir
  // tabs/activeTabIndex/navHistory/navHistoryIndex viven ahora en
  // state/TabsState.qml -- vigesimoprimer y último slice de la capa
  // state/.
  property var entries: []
  // Caché de listados por ruta, alimentada por los paneles de fondo cada
  // vez que refrescan -- ver _goToPath().
  property var tabEntriesCache: ({})
  property bool searching: false
  property string deepSearchRoot: ""
  property string searchQuery: ""
  // Antes la búsqueda recursiva se cortaba en 200 resultados sin decir
  // nada -- una búsqueda con muchas coincidencias parecía completa cuando
  // en realidad faltaban ítems. Ver runDeepSearch()/search-recursive.sh.
  property bool searchTruncated: false
  readonly property var visibleEntries: root.searchQuery
    ? root.entries.filter(function (e) { return e.name.toLowerCase().indexOf(root.searchQuery.toLowerCase()) >= 0 })
    : root.entries
  property bool opened: false
  property bool closingFromHost: false
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

  // Ver listProc.onStreamFinished -- cuando se entra en la papelera sin
  // trashInfo previa cargada (ni siquiera compartida desde un panel de
  // fondo), las entries recién listadas se guardan aquí hasta que
  // trashInfoProc termine, en vez de pintarlas ya con el texto a medias.
  property bool _waitingForTrashInfo: false
  property var _pendingListEntries: []

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
    actionEngine.pushUndo(label, undoFn, redoFn)
  }

  function undoLast() {
    actionEngine.undoLast()
  }

  function redoLast() {
    actionEngine.redoLast()
  }

  // Inyectado por el host (shell.qml) via duck-typing al cargar el plugin.
  property var shell: null
  property bool showHidden: false

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
  // "confirmar" que relee root.currentPath/selectionOps.selectedEntries() EN EL
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
  // actionProgressDestPaths/_actionOnSuccess/_actionCancelled viven ahora
  // en state/ActionState.qml -- duodécimo slice de la capa state/, completa
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
  function extOf(name) { return fileTypeUtils.extOf(name) }
  function iconFor(entry) { return fileTypeUtils.iconFor(entry) }
  function isImage(entry) { return fileTypeUtils.isImage(entry) }
  function isVideo(entry) { return fileTypeUtils.isVideo(entry) }
  function isAudio(entry) { return fileTypeUtils.isAudio(entry) }
  function isPdf(entry) { return fileTypeUtils.isPdf(entry) }

  // ---------- Miniaturas de vídeo (ffmpegthumbnailer, en cola de 1 a la vez) ----------
  property string thumbCacheDir: root.homeDir + "/.cache/omafiles/thumbnails"
  // videoThumbReady/thumbQueue/thumbBusy viven ahora en
  // state/VideoThumbState.qml -- decimocuarto slice de la capa state/.

  // simpleHash/thumbKeyFor/videoThumbPath: movidas a Utils.js (funciones
  // puras). `basePath`/cacheDir ya no son opcionales -- cada llamada de
  // aquí en adelante los pasa explícitos (ver comentario en Utils.js).

  // ---------- Selección (individual + lazo) ----------

  // ---------- Refresco / vigilancia de directorio ----------
  function refresh() {
    // Centralizado aquí para que TODO lo que ya llama a refresh() (toggle
    // de ocultos, el "Refresh" de la paleta, el onExited de las acciones
    // de fichero...) recargue lo correcto sin tener que acordarse de
    // comprobar inArchive en cada sitio.
    if (ArchiveState.inArchive) { archiveActions.refreshArchiveListing(); return }
    root.currentPathError = ""
    // La Papelera agrega la de casa MÁS la de cualquier otro disco
    // montado que tenga la suya propia (spec de XDG Trash) -- ver
    // list-trash.sh/trash-roots.sh. No es una carpeta real única, así
    // que no puede pasar por list-dir.sh a secas como el resto.
    if (root.currentPath === root.trashDir) {
      listProc.command = [root.pluginDir + "/list-trash.sh", root.showHidden ? "1" : "0"]
    } else {
      listProc.command = [root.pluginDir + "/list-dir.sh", root.currentPath, root.showHidden ? "1" : "0"]
    }
    listProc.running = true
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
    var changed = JSON.stringify(parsed) !== JSON.stringify(root.entries)
    if (changed) root.entries = parsed
    root._finishListLoad(changed)
  }

  // Ver listProc.onStreamFinished -- lo que queda por hacer una vez
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
    dirWatchProc.running = false
    dirWatchProc.command = ["inotifywait", "-m", "-q", "-e",
      "create,delete,moved_to,moved_from,modify,attrib,close_write", "--", path]
    dirWatchProc.running = true
  }

  function stopDirWatch() {
    dirWatchProc.running = false
  }


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

  function navigateTo(path) {
    if (!path) return
    // Normaliza barras finales/dobles básicas sin depender de un proceso externo.
    path = path.replace(/\/+$/, "") || "/"
    root._pushHistory(path)
    root._goToPath(path)
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
    root.refresh()
    root.startDirWatch(path)
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
    root._goToPath(TabsState.navHistory[TabsState.navHistoryIndex])
  }

  function navForward() {
    if (TabsState.navHistoryIndex >= TabsState.navHistory.length - 1) return
    TabsState.navHistoryIndex += 1
    root._goToPath(TabsState.navHistory[TabsState.navHistoryIndex])
  }

  // Usado por BackgroundPanel (doble clic sobre un fichero en un panel de
  // fondo) -- openProc solo es visible por id dentro de este fichero, así
  // que un componente en otro .qml necesita esta función en vez de tocarlo
  // directo.
  function openWithDefault(path) {
    openProc.command = ["xdg-open", path]
    openProc.running = true
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
      openProc.command = ["xdg-open", openPath]
      openProc.running = true
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

  // ---------- Ciclo de vida (abrir/cerrar la ventana del host) ----------
  // Host-initiated open/close (`shell toggle`/`shell summon`/`shell hide`).
  // `payload` es "<ruta>" o "<ruta>\n<nombre-a-seleccionar>" en texto
  // plano (o "" / "{}" si no hay ninguna) -- la manda `scripts/open-path.sh`
  // (xdg-open/.desktop, sin selección) o `scripts/dbus-filemanager1.py`
  // (interfaz org.freedesktop.FileManager1, con selección para ShowItems).
  function open(payload) {
    root.opened = true
    panel.visible = true

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
        root.currentPath = targetPath
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
        persistence.loadSession()
      }
    } else if (targetPath) {
      // Ya estaba cargado antes (uso normal previo): abre en pestaña
      // nueva para no perder la ubicación en la que ya estaba el usuario.
      tabOps.newTab()
      root.navigateTo(targetPath)
      tabOps.saveActiveTab()
    }

    if (!BookmarksState.bookmarksLoaded) persistence.loadBookmarks()
    if (!BookmarksState.recentLoaded) persistence.loadRecent()
    if (!BookmarksState.bulkRenameHistoryLoaded) persistence.loadBulkRenameHistory()
    mountOps.refreshMounts()
    mountOps.refreshNetworkMounts()
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
    persistence.saveSession()
    root.closingFromHost = true
    root.opened = false
    panel.visible = false
    root.closingFromHost = false
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
  // la ventana). Avisa al shell para que su mapa de paneles abiertos quede
  // consistente y el próximo `toggle` funcione bien -- mismo patrón que
  // dev-gallery/GalleryPanel.qml.
  function requestClose() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide("io.github.percius04.omafiles")
    else root.close()
  }

  // onSuccess (opcional) se llama SOLO si el comando termina con exit 0 --
  // úsalo para todo lo que no deba pasar si la acción en realidad falló
  // (sobre todo pushUndo: un undo registrado para algo que nunca ocurrió en
  // disco es peor que no tener undo). Devuelve true si el comando se lanzó,
  // false si se descartó porque ya había otra acción en marcha (el llamador
  // decide si eso merece avisar al usuario).
  function runAction(cmd, busyLabel, onSuccess) {
    return actionEngine.runAction(cmd, busyLabel, onSuccess)
  }

  function chainCmds(cmds) {
    return actionEngine.chainCmds(cmds)
  }

  function cancelAction() {
    actionEngine.cancelAction()
  }

  function startCopyProgress(sourcePaths, destPaths) {
    actionEngine.startCopyProgress(sourcePaths, destPaths)
  }

  function openTerminalHere() {
    openProc.command = ["xdg-terminal-exec", "--dir=" + root.currentPath]
    openProc.running = true
  }

  function paletteCommands() {
    var hasSelection = SelectionState.selectedIndices.length > 0
    var entry = SelectionState.selectedIndices.length === 1 ? root.visibleEntries[SelectionState.selectedIndex] : null
    var cmds = [
      { label: "New folder", run: function () { renameOps.startNewFolder() } },
      { label: "New file", run: function () { renameOps.startNewFile() } },
      { label: "Rename", enabled: SelectionState.selectedIndices.length === 1, run: function () { renameOps.startRename(SelectionState.selectedIndex) } },
      { label: "Copy", enabled: hasSelection, run: function () { clipboardOps.copySelected() } },
      { label: "Cut", enabled: hasSelection, run: function () { clipboardOps.cutSelected() } },
      { label: "Copy path", enabled: hasSelection, run: function () { clipboardOps.copyPathFor(selectionOps.selectedEntries()) } },
      { label: "Paste", enabled: ClipboardState.clipboardPaths.length > 0, run: function () { conflictActions.paste() } },
      { label: "Delete", enabled: hasSelection, run: function () { deleteOps.requestDelete() } },
      { label: "Select all", run: function () { SelectionState.selectedIndices = Array.from({ length: root.visibleEntries.length }, function (_, i) { return i }) } },
      { label: "Select none", enabled: hasSelection, run: function () { selectionOps.selectNone() } },
      { label: "Invert selection", run: function () { selectionOps.invertSelection() } },
      { label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", run: function () { searchOps.toggleHidden() } },
      { label: "Refresh", run: function () { root.refresh(); mountOps.refreshMounts(); mountOps.refreshNetworkMounts() } },
      { label: "Sort by name", run: function () { sortOps.setSort("name") } },
      { label: "Sort by size", run: function () { sortOps.setSort("size") } },
      { label: "Sort by date", run: function () { sortOps.setSort("mtime") } },
      { label: "Sort by type", run: function () { sortOps.setSort("type") } },
      { label: "Reverse order", run: function () { sortOps.reverseSort() } },
      { label: UndoState.undoStack.length > 0 ? "Undo: " + UndoState.undoStack[UndoState.undoStack.length - 1].label : "Undo",
        enabled: UndoState.undoStack.length > 0, run: function () { root.undoLast() } },
      { label: UndoState.redoStack.length > 0 ? "Redo: " + UndoState.redoStack[UndoState.redoStack.length - 1].label : "Redo",
        enabled: UndoState.redoStack.length > 0, run: function () { root.redoLast() } },
      { label: "Terminal here", run: function () { root.openTerminalHere() } },
      { label: "Go to Home", run: function () { root.navigateTo(root.homeDir) } },
      { label: "Connect to server...", run: function () { mountOps.startConnectToServer() } },
      { label: "New panel", run: function () { tabOps.newTab() } },
      { label: "Close this panel", enabled: TabsState.tabs.length > 1, run: function () { tabOps.closeTab() } },
      { label: "Back", enabled: TabsState.navHistoryIndex > 0, run: function () { root.navBack() } },
      { label: "Forward", enabled: TabsState.navHistoryIndex < TabsState.navHistory.length - 1, run: function () { root.navForward() } },
      { label: "Edit path", run: function () { searchOps.startEditPath() } },
      { label: "Search", run: function () { searchOps.startSearch() } },
      { label: "Compress to .zip", enabled: hasSelection, run: function () { conflictActions.compressSelected() } },
      { label: "Bulk rename...", enabled: SelectionState.selectedIndices.length > 1, run: function () { fileOps.startBulkRename() } },
      { label: "Permissions...", enabled: hasSelection, run: function () { propertiesLoader.startChmod(selectionOps.selectedEntries()) } },
      { label: "Make link", enabled: !!entry, run: function () { if (entry) fileOps.makeLinkFor(entry) } },
      { label: "Properties", enabled: hasSelection, run: function () { propertiesLoader.showPropertiesForSelection() } },
      { label: "Keyboard shortcuts", run: function () { DialogsState.shortcutsHelpOpen = true } }
    ]
    if (root.currentPath === root.trashDir) {
      cmds.push({ label: "Empty trash", run: function () { root.emptyTrash() } })
      cmds.push({ label: "Restore", enabled: hasSelection, run: function () { fileOps.restoreFromTrash() } })
    }
    if (entry && entry.type !== "dir" && archiveActions.isArchive(entry)) {
      cmds.push({ label: "Extract here", run: function () { conflictActions.extractHere(entry) } })
    }
    if (entry && archiveActions.isIso(entry)) {
      cmds.push({ label: "Mount ISO", run: function () { mountOps.mountIso(entry) } })
    }
    if (entry) {
      var fullPath = root.joinPath(root.currentPath, entry.name)
      if (!bookmarkOps.isBookmarked(fullPath)) {
        cmds.push({ label: "Add to bookmarks", run: function () { bookmarkOps.addBookmark(fullPath, entry.name, entry.type) } })
      }
      if (entry.type === "dir") {
        cmds.push({ label: "Open in new tab", run: function () { tabOps.openInNewTab(fullPath) } })
      }
    }
    // Bug real corregido aquí: a diferencia de itemActions() (menú
    // contextual), esta lista no tenía NINGÚN filtro para ArchiveState.inArchive
    // -- "Add to bookmarks"/"Open in new tab" no tienen guard propio (a
    // diferencia de rename/copy/paste/etc., que sí se auto-protegen
    // dentro de su función) y mezclaban la carpeta real con el nombre de
    // un elemento DENTRO del archivo, escribiendo una ruta rota a
    // bookmarks.json sin avisar. El resto de la lista se filtra aquí
    // también, no porque fuera a romper nada (esas funciones ya son
    // no-op dentro de un archivo) sino para no enseñar entradas muertas.
    if (ArchiveState.inArchive) {
      var archiveBlocked = ["New folder", "New file", "Rename", "Copy", "Cut", "Copy path", "Paste", "Delete",
        "Compress to .zip", "Bulk rename...", "Permissions...", "Make link", "Properties",
        "Search", "Add to bookmarks", "Open in new tab", "Extract here", "Mount ISO", "Empty trash", "Restore"]
      cmds = cmds.filter(function (c) { return archiveBlocked.indexOf(c.label) < 0 })
    }
    return cmds
  }

  function filteredPaletteCommands() {
    var all = root.paletteCommands()
    if (!PaletteState.paletteQuery) return all
    var q = PaletteState.paletteQuery.toLowerCase()
    return all.filter(function (c) { return c.label.toLowerCase().indexOf(q) >= 0 })
  }

  function openPalette() {
    PaletteState.paletteQuery = ""
    PaletteState.paletteIndex = 0
    PaletteState.paletteOpen = true
  }

  function closePalette() {
    PaletteState.paletteOpen = false
  }

  function runPaletteCommand(index) {
    var cmds = root.filteredPaletteCommands()
    if (index < 0 || index >= cmds.length) return
    var cmd = cmds[index]
    if (cmd.enabled === false) return
    root.closePalette()
    cmd.run()
  }

  function openContextMenu(x, y, actions) {
    ContextMenuState.contextMenuActions = actions
    ContextMenuState.contextMenuX = Math.min(x, 680)
    ContextMenuState.contextMenuY = y
    ContextMenuState.contextMenuOpen = true
  }

  function itemActions() {
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return []
    // Dentro de un comprimido solo se navega/abre -- nada de lo demás
    // (renombrar/borrar/chmod/comprimir/copiar/enlazar/marcador) tiene
    // sentido sobre una ruta que no existe de verdad en disco.
    if (ArchiveState.inArchive) {
      if (entries.length !== 1) return []
      return [{ label: entries[0].type === "dir" ? "Open" : "Open (extracts a temp copy)", action: function () { root.enter(entries[0]) } }]
    }
    var multi = entries.length > 1
    var suffix = multi ? " (" + entries.length + ")" : ""
    var inTrash = root.currentPath === root.trashDir
    var actions = []

    if (inTrash) {
      actions.push({ label: "Restore" + suffix, action: function () { fileOps.restoreFromTrash() } })
      actions.push({ label: "Delete permanently" + suffix, destructive: true, action: function () { deleteOps.requestDelete() } })
      return actions
    }

    // Orden por grupos (antes era una lista plana en el orden en que se
    // habían ido añadiendo funciones a lo largo de varias sesiones, sin
    // criterio): 1) abrir, 2) portapapeles, 3) organizar (renombrar/
    // enlace/marcador/comprimir/extraer/montar), 4) permisos/borrar/
    // propiedades, 5) vista. Mismo grupo en single y multi-selección para
    // que el menú no "salte" de sitio al seleccionar un segundo ítem.
    if (!multi) {
      actions.push({ label: "Open", action: function () { root.enter(entries[0]) } })
      if (entries[0].type === "dir") {
        // Bug real: usar root.currentPath dentro del closure (en vez de
        // capturarlo aquí) leía la ruta en el momento del CLIC del menú,
        // no en el momento de abrirlo -- si el ratón pasaba por otro
        // panel de fondo mientras el menú seguía abierto (el
        // HoverHandler de cambio de pestaña no se desactiva solo por
        // haber un menú encima), la pestaña activa ya había cambiado y
        // "Open in new tab" abría la carpeta dentro de la carpeta
        // EQUIVOCADA. Capturado como variable local, coherente con como
        // ya lo hace paletteCommands() para el mismo caso.
        var dirFullPath = root.joinPath(root.currentPath, entries[0].name)
        actions.push({ label: "Open in new tab", action: function () {
          tabOps.openInNewTab(dirFullPath)
        } })
      } else {
        actions.push({ label: "Open with...", action: function () { openWithOps.showOpenWith(entries[0]) } })
      }
    }

    actions.push({ label: "Copy" + suffix, action: function () { clipboardOps.copySelected() } })
    actions.push({ label: "Cut" + suffix, action: function () { clipboardOps.cutSelected() } })
    actions.push({ label: "Copy path" + suffix, action: function () { clipboardOps.copyPathFor(entries) } })
    if (ClipboardState.clipboardPaths.length > 0) actions.push({ label: "Paste here", action: function () { conflictActions.paste() } })

    if (!multi) {
      actions.push({ label: "Rename", action: function () { renameOps.startRename(SelectionState.selectedIndex) } })
      actions.push({ label: "Make link", action: function () { fileOps.makeLinkFor(entries[0]) } })
      var fullPath = root.joinPath(root.currentPath, entries[0].name)
      if (!bookmarkOps.isBookmarked(fullPath)) {
        actions.push({ label: "Add to bookmarks", action: function () { bookmarkOps.addBookmark(fullPath, entries[0].name, entries[0].type) } })
      }
      actions.push({ label: "Compress to .zip", action: function () { conflictActions.compressSelected() } })
      if (archiveActions.isArchive(entries[0])) {
        actions.push({ label: "Extract here", action: function () { conflictActions.extractHere(entries[0]) } })
      }
      if (archiveActions.isIso(entries[0])) {
        actions.push({ label: "Mount", action: function () { mountOps.mountIso(entries[0]) } })
      }
    } else {
      actions.push({ label: "Bulk rename...", action: function () { fileOps.startBulkRename() } })
      actions.push({ label: "Compress to .zip", action: function () { conflictActions.compressSelected() } })
    }

    actions.push({ label: "Permissions...", action: function () { propertiesLoader.startChmod(entries) } })
    actions.push({ label: "Delete" + suffix, destructive: true, action: function () { deleteOps.requestDelete() } })
    actions.push({ label: "Properties" + suffix, action: function () { propertiesLoader.showPropertiesForSelection() } })
    actions.push({ label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { searchOps.toggleHidden() } })
    return actions
  }

  function emptyAreaActions() {
    var actions = []
    if (root.currentPath === root.trashDir) {
      actions.push({ label: "Empty trash", destructive: true, action: function () { root.emptyTrash() } })
    } else if (!ArchiveState.inArchive) {
      // Dentro de un archivo estas ya son no-op (cada función se
      // protege sola), pero se quitan de aquí para no enseñar entradas
      // muertas en el menú de hueco vacío.
      actions.push({ label: "New folder", action: function () { renameOps.startNewFolder() } })
      actions.push({ label: "New file", action: function () { renameOps.startNewFile() } })
      actions.push({ label: "Paste", enabled: ClipboardState.clipboardPaths.length > 0, action: function () { conflictActions.paste() } })
    }
    actions.push({ label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { searchOps.toggleHidden() } })
    actions.push({ label: "Refresh", action: function () { root.refresh(); mountOps.refreshMounts(); mountOps.refreshNetworkMounts() } })
    return actions
  }

  // Marcador de fichero: navega a la carpeta que lo contiene y lo deja
  // seleccionado -- reutiliza pendingSelectNames, el mismo mecanismo que
  // ya usa "Mostrar en el gestor de archivos" (dbus-filemanager1.py) para
  // resaltar un fichero concreto al aterrizar en una carpeta.
  function openBookmark(bookmark) {
    if (bookmark.type === "file") {
      var slash = bookmark.path.lastIndexOf("/")
      root.pendingSelectNames = [bookmark.path.substring(slash + 1)]
      root.navigateTo(slash > 0 ? bookmark.path.substring(0, slash) : "/")
    } else {
      root.navigateTo(bookmark.path)
    }
  }

  // Mismo mecanismo que openBookmark() para uno de tipo "file" -- todos
  // los recientes son ficheros (nunca carpetas, ver addRecent()).
  function openRecent(item) {
    var slash = item.path.lastIndexOf("/")
    root.pendingSelectNames = [item.name]
    root.navigateTo(slash > 0 ? item.path.substring(0, slash) : "/")
  }

  // Doble clic en un reciente -- a diferencia de openRecent() (navega y
  // selecciona), esto lo abre de verdad con la app por defecto, igual que
  // hace enter() con una fila normal. addRecent() lo vuelve a subir al
  // principio de la lista, igual que si se acabara de abrir ahora mismo.
  function launchRecent(item) {
    root.openWithDefault(item.path)
    bookmarkOps.addRecent(item.path, item.name)
  }

  function bookmarkActions(bookmark) {
    var actions = [
      { label: "Open", action: function () { root.openBookmark(bookmark) } }
    ]
    if (bookmark.type !== "file") {
      actions.push({ label: "Open in new tab", action: function () { tabOps.openInNewTab(bookmark.path) } })
    }
    if (bookmark.path === root.trashDir) {
      actions.push({ label: "Empty trash", destructive: true, action: function () { root.emptyTrash() } })
    } else {
      // Trash es fija -- josema la quitó por error una vez y no hay
      // forma de recuperarla salvo pidiéndomelo a mano (defaultBookmarks
      // solo se usa la primera vez que se abre la app, nunca más). Sin
      // "Remove bookmark" para ella, no se puede volver a perder igual.
      actions.push({ label: "Remove bookmark", destructive: true, action: function () { bookmarkOps.removeBookmark(bookmark.path) } })
    }
    return actions
  }

  function mountActions(mount) {
    if (!mount.mounted) {
      return [{ label: "Mount", action: function () { mountOps.mountDevice(mount) } }]
    }
    var actions = [
      { label: "Open", action: function () { root.navigateTo(mount.path) } },
      { label: "Open in new tab", action: function () { tabOps.openInNewTab(mount.path) } }
    ]
    if (!bookmarkOps.isBookmarked(mount.path)) {
      actions.push({ label: "Add to bookmarks", action: function () { bookmarkOps.addBookmark(mount.path, mount.label, "dir") } })
    }
    if (mount.removable) {
      actions.push({ label: "Eject", destructive: true, action: function () { mountOps.ejectMount(mount) } })
    }
    return actions
  }

  // Dentro de un comprimido, la ruta real (root.currentPath) no cambia --
  // solo se navega en archiveSubPath (ver enter()/goUp()/inArchive) -- así
  // que el breadcrumb tiene que construirse aparte para reflejarlo. Nadie
  // hace clic en un segmento individual (ver el Repeater real más abajo,
  // sin MouseArea propio a propósito), así que basta con que el ÚLTIMO
  // segmento tenga path === root.currentPath -- es lo único que usa la
  // plantilla compartida para decidir cuál pintar en negrita.
  function pathSegments() {
    if (!ArchiveState.inArchive) return root.pathSegmentsFor(root.currentPath)
    var segs = root.pathSegmentsFor(root.currentPath)
    var archiveName = ArchiveState.archivePath.substring(ArchiveState.archivePath.lastIndexOf("/") + 1)
    var parts = ArchiveState.archiveSubPath ? ArchiveState.archiveSubPath.split("/") : []
    var isLast = parts.length === 0
    segs.push({ label: archiveName, path: isLast ? root.currentPath : "" })
    for (var i = 0; i < parts.length; i++) {
      segs.push({ label: parts[i], path: (i === parts.length - 1) ? root.currentPath : "" })
    }
    return segs
  }

  function pathSegmentsFor(targetPath) {
    if (targetPath === "/") return [{ label: "/", path: "/" }]
    var parts = targetPath.split("/").filter(function (p) { return p.length > 0 })
    var acc = ""
    var segs = [{ label: "/", path: "/" }]
    for (var i = 0; i < parts.length; i++) {
      acc += "/" + parts[i]
      segs.push({ label: parts[i], path: acc })
    }
    return segs
  }

  // Autoregistro como gestor de archivos del sistema (MimeType inode/
  // directory + org.freedesktop.FileManager1) -- se lanza una vez al
  // cargar el plugin, sin esperar a que el usuario abra la ventana ni
  // tenga que ejecutar nada a mano. El script es idempotente (ver
  // scripts/install-integrations.sh), así que llamarlo en cada arranque
  // del shell es barato y seguro.
  Component.onCompleted: {
    installIntegrationsProc.command = [root.pluginDir + "/scripts/install-integrations.sh"]
    installIntegrationsProc.running = true
  }

  Process {
    id: installIntegrationsProc
  }

  // "close_write" (fichero cerrado tras escribir) en vez de fiarse solo
  // de "modify" -- así una copia grande en curso no dispara un refresh
  // por cada bloque escrito, solo cuando el fichero realmente queda
  // listo. inotifywait -m no termina nunca solo (modo monitor); se mata
  // explícitamente (running=false) al navegar a otra carpeta o cerrar
  // la ventana, ver startDirWatch()/stopDirWatch().
  Process {
    id: dirWatchProc
    stdout: SplitParser {
      onRead: dirWatchDebounce.restart()
    }
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
    onTriggered: if (!root.hasPendingEdit) root.refresh()
  }

  // Discos/red no tienen un evento fácil de vigilar aquí (habría que
  // suscribirse a señales D-Bus de UDisks2/GVfs) -- un polling modesto
  // es la opción honesta dado el alcance: enchufar un USB o que una
  // ubicación de red se caiga se nota en unos segundos en vez de nunca
  // (antes) o de tener que montar infraestructura D-Bus (después,
  // quizás). "running: root.opened" para que no siga en marcha de fondo
  // con la ventana cerrada.
  Timer {
    interval: 7000
    repeat: true
    running: root.opened
    onTriggered: { mountOps.refreshMounts(); mountOps.refreshNetworkMounts() }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = sortOps.sortEntries(Utils.parseEntries(text))
        if (root.currentPath === root.trashDir) {
          if (Object.keys(TrashState.trashInfo).length > 0) {
            // Ya hay trashInfo cargada -- de este mismo panel en una
            // visita anterior de esta sesión, o COMPARTIDA desde un panel
            // de fondo que ya la tenía (ver BackgroundPanel.qml/
            // bgTrashInfoProc). Pintar ya con eso; el trashInfoProc de
            // abajo solo la refresca por detrás sin bloquear el pintado.
            root._applyEntries(parsed)
          } else {
            // Primera vez que se ve la papelera en TODA la sesión (ni
            // siquiera un panel de fondo la había cargado antes de que
            // esta pestaña pasara a activa) -- esperar a que
            // trash-info.sh termine para pintar ya con el texto final
            // ("Deleted X ago · from ...") de una sola vez. Mismo bug/
            // mismo motivo que BackgroundPanel.qml -- root.entries
            // saliendo primero con solo el tamaño y esa parte llegando
            // un instante después hacía crecer las filas y saltar todo
            // lo de debajo (parpadeo real, reportado por josema; esta
            // rama concreta -- panel ACTIVO, no de fondo -- es la que
            // se me había escapado en el primer intento de arreglarlo).
            root._pendingListEntries = parsed
            root._waitingForTrashInfo = true
          }
          trashInfoProc.command = [root.pluginDir + "/trash-info.sh"]
          trashInfoProc.running = true
        } else {
          // NO se limpia TrashState.trashInfo al salir de la papelera -- es
          // COMPARTIDA entre el panel activo y todos los de fondo (ver
          // BackgroundPanel.qml/bgTrashInfoProc), así que vaciarla aquí
          // sin más se la quitaba también a un panel de FONDO que
          // siguiera mostrando la papelera en ese mismo instante. Ese
          // vacío + el rellenado casi inmediato que le seguía (el panel
          // de fondo lo notaba y volvía a pedir trash-info.sh) era el
          // salto real reportado por josema: el texto "Deleted X ago..."
          // desaparecía y volvía en unas décimas de segundo cada vez que
          // se cambiaba de pestaña, aunque fuera hacia una carpeta
          // normal. Dejarla con datos obsoletos sin más uso no hace daño
          // -- metaFor() solo la consulta cuando la ruta ES la papelera.
          root._applyEntries(parsed)
        }
      }
    }
    // stdout ya deja entries vacío (list-dir.sh no imprime nada si falla);
    // esto solo añade el porqué, según el código de salida documentado en
    // list-dir.sh.
    onExited: function (exitCode, exitStatus) {
      if (exitCode === 2) root.currentPathError = "Permission denied"
      else if (exitCode === 3) root.currentPathError = "This folder no longer exists"
      else if (exitCode === 4) root.currentPathError = "Not a folder"
      else if (exitCode !== 0) root.currentPathError = "Couldn't open this folder"
    }
  }

  ArchiveActions {
    id: archiveActions
    root: root
    list: list
    selectionOps: selectionOps
    sortOps: sortOps
  }

  FileOps {
    id: fileOps
    root: root
    selectionOps: selectionOps
  }

  VideoThumbnails {
    id: videoThumbs
    root: root
  }

  RenameOps {
    id: renameOps
    root: root
  }

  ClipboardOps {
    id: clipboardOps
    root: root
    selectionOps: selectionOps
  }

  DragDropOps {
    id: dragDropOps
    root: root
    conflictActions: conflictActions
    selectionOps: selectionOps
  }

  SearchOps {
    id: searchOps
    root: root
    list: list
    selectionOps: selectionOps
    sortOps: sortOps
  }

  OpenWithOps {
    id: openWithOps
    root: root
    bookmarkOps: bookmarkOps
  }

  FileMeta {
    id: fileMeta
    root: root
  }

  DeleteOps {
    id: deleteOps
    root: root
    selectionOps: selectionOps
  }

  TabOps {
    id: tabOps
    root: root
    list: list
    archiveActions: archiveActions
    previewLoader: previewLoader
  }

  SelectionOps {
    id: selectionOps
    root: root
    previewLoader: previewLoader
  }

  SortOps {
    id: sortOps
    root: root
  }

  FileTypeUtils {
    id: fileTypeUtils
    root: root
  }

  BookmarkOps {
    id: bookmarkOps
    root: root
    persistence: persistence
    tabOps: tabOps
    mountOps: mountOps
  }

  Process {
    id: trashInfoProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var fields = String(text || "").split("\u0000")
        if (fields.length > 0 && fields[fields.length - 1] === "") fields.pop()
        var info = {}
        for (var i = 0; i + 3 < fields.length; i += 4) {
          info[fields[i]] = { origPath: fields[i + 1], epoch: Number(fields[i + 2] || 0), trashRoot: fields[i + 3] }
        }
        TrashState.trashInfo = info
        if (root._waitingForTrashInfo) {
          root._waitingForTrashInfo = false
          root._applyEntries(root._pendingListEntries)
        }
      }
    }
  }

  Process {
    id: openProc
  }

          MountActions {
            id: mountOps
            root: root
            tabOps: tabOps
          }

  Persistence {
    id: persistence
    root: root
    tabOps: tabOps
  }

  ActionEngine {
    id: actionEngine
    root: root
  }

  ConflictActions {
    id: conflictActions
    root: root
    archiveActions: archiveActions
    fileOps: fileOps
    renameOps: renameOps
    clipboardOps: clipboardOps
    selectionOps: selectionOps
    bookmarkOps: bookmarkOps
  }

  PreviewLoader {
    id: previewLoader
    root: root
    videoThumbs: videoThumbs
    fileMeta: fileMeta
  }


  PropertiesLoader {
    id: propertiesLoader
    root: root
    selectionOps: selectionOps
  }

  Timer {
    id: gTimer
    interval: 600
    onTriggered: root.gPending = false
  }

  FloatingWindow {
    id: panel

    // Los Window de QtQuick nacen visible:true por defecto -- sin esto se
    // abriría solo con keepLoaded, antes de que open() lo pida.
    visible: false
    title: "Omafiles"
    color: Color.menu.background
    implicitWidth: 900
    implicitHeight: 620
    minimumSize: Qt.size(560, 380)

    onVisibleChanged: {
      // Cierre externo (botón de cerrar de la ventana, gestor de ventanas)
      // que no pasó por close()/requestClose() -- avisa al shell para que
      // su mapa de paneles abiertos no quede desincronizado. Mismo patrón
      // que dev-gallery/GalleryPanel.qml.
      if (!visible && !root.closingFromHost && root.opened) {
        root.opened = false
        if (root.shell && typeof root.shell.hide === "function") root.shell.hide("io.github.percius04.omafiles")
      }
    }

    BorderSurface {
      id: card
      anchors.fill: parent
      color: Color.menu.background
      // Sin borde propio: Hyprland ya dibuja el borde de ventana activa/
      // inactiva alrededor de toda la ventana (como en el resto de apps del
      // sistema) -- un BorderSurface aquí dibujaría un segundo borde, con
      // su propio color, pegado al de Hyprland. Eso sí hace falta en los
      // popups reales de Omarchy (audio, red...) porque son layer-shell y
      // Hyprland nunca los decora; Omafiles ya es una ventana normal.
      borderSpec: Border.none()
      radius: Style.cornerRadius
      padding: Style.spacing.panelPadding

      Row {
        id: cardRow
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        // ---------- Barra lateral: accesos anclados ----------
        Sidebar {
          id: sidebar
          width: 160
          height: parent.height
          bookmarks: BookmarksState.bookmarks
          recentFiles: BookmarksState.recentFiles
          mounts: MountsState.mounts
          networkMounts: MountsState.networkMounts
          currentPath: root.currentPath
          dropHoverPath: DropHoverState.dropHoverPath
          positionRelativeTo: card
          iconForBookmark: bookmarkOps.iconForBookmark
          iconFor: root.iconFor
          iconForMount: bookmarkOps.iconForMount
          iconForNetworkMount: bookmarkOps.iconForNetworkMount
          openContextMenu: root.openContextMenu
          bookmarkActionsFor: root.bookmarkActions
          mountActionsFor: root.mountActions
          networkMountActionsFor: bookmarkOps.networkMountActions
          onBookmarkOpened: function (bookmark) { root.openBookmark(bookmark) }
          onRecentOpened: function (item) { root.openRecent(item) }
          onRecentLaunched: function (item) { root.launchRecent(item) }
          onRecentRemoveRequested: function (path) { bookmarkOps.removeRecent(path) }
          onRecentClearRequested: bookmarkOps.clearRecent()
          onMountActivated: function (mount) {
            if (!mount.mounted) mountOps.mountDevice(mount)
            else root.navigateTo(mount.path)
          }
          onNetworkMountOpened: function (mount) { root.navigateTo(mount.path) }
          onConnectRequested: mountOps.startConnectToServer()
          onFilesDropped: function (drop, destPath) { dragDropOps.handleFilesDropped(drop, destPath) }
          onDropHoverChanged: function (path) { DropHoverState.dropHoverPath = path }
        }

        Rectangle {
          width: Style.spacing.hairline
          height: parent.height
          color: Color.menu.border
          // Bajado de 0.3 a 0.15 -- misma alpha que usa PanelSeparator
          // (el separador horizontal real de Omarchy) para el mismo rol
          // conceptual de "línea divisoria discreta". No hay un
          // componente vertical real con el que comparar, pero no hay
          // motivo para que esta línea sea el doble de fuerte que las
          // horizontales del mismo fichero.
          opacity: 0.15
        }

        // ---------- Contenido principal ----------
        Column {
          id: mainColumn
          width: parent.width - sidebar.width - 1 - parent.spacing * 2
          height: parent.height
          spacing: Style.spacing.rowGap

          Item {
            id: panelsRow
            width: parent.width
            height: parent.height
            readonly property int panelCount: TabsState.tabs.length
            // El hueco entre dos paneles lleva panelGap A CADA LADO del
            // divisor (no panelGap repartido entre los dos) -- para que el
            // margen "interior" de un panel (hacia el divisor) sea tan ancho
            // como el "exterior" (hacia la barra lateral o el borde de la
            // ventana), en vez de la mitad.
            readonly property real interPanelGap: 2 * Style.spacing.panelGap + Style.spacing.hairline
            readonly property real slotWidth: (panelsRow.width - (panelCount - 1) * interPanelGap) / panelCount
            function slotX(i) { return i * (panelsRow.slotWidth + panelsRow.interPanelGap) }

            // ---------- Divisores entre paneles ----------
            // Una simple línea, no un recuadro con borde propio -- mismo
            // estilo que ya usa el divisor entre la barra lateral y el
            // contenido (Color.menu.border, opacity 0.15, Style.spacing.hairline).
            Repeater {
              model: Math.max(0, TabsState.tabs.length - 1)
              delegate: Rectangle {
                required property int index
                x: panelsRow.slotX(index) + panelsRow.slotWidth + Style.spacing.panelGap
                y: 0
                width: Style.spacing.hairline
                height: panelsRow.height
                color: Color.menu.border
                opacity: 0.15
              }
            }

            // ---------- Paneles simples (todas las pestañas salvo la activa) ----------
            // Generalización de lo que antes era un único panel de "vista
            // dividida" fijo -- ahora hay uno por cada pestaña que no sea la
            // activa, cada uno con su propio listado (su propio Process,
            // hijo del delegado). Deliberadamente simple: sin lazo de
            // selección ni menú contextual propio, solo navegar con doble
            // clic y arrastrar -- para eso sirve, el panel activo (más
            // abajo) ya tiene todo lo demás.
            Repeater {
              model: TabsState.tabs

              BackgroundPanel {
                hostRoot: root
                hostPanelsRow: panelsRow
                hostVideoThumbs: videoThumbs
                hostDragDropOps: dragDropOps
                hostFileMeta: fileMeta
                hostTabOps: tabOps
                hostSortOps: sortOps
              }
            }

            // ---------- Panel activo ----------
            // Todo lo que ya existía (barra de navegación, campos de
            // nueva carpeta/fichero/búsqueda, la lista completa con lazo de
            // selección/menú contextual/drag&drop/etc.) sin tocar su lógica
            // interna -- solo movido a su propio hueco dentro de la fila de
            // paneles, en la posición de la pestaña activa.
            Item {
              id: activePanel
              x: panelsRow.slotX(TabsState.activeTabIndex)
              y: 0
              width: panelsRow.slotWidth
              height: panelsRow.height

          // Sin tinte de fondo propio en el panel activo -- se probó un
          // Rectangle de Util.alpha(Color.accent, 0.08) de pared a pared,
          // pero josema lo vio feo al pasar el ratón (mancha de color
          // sobre todo el panel). El atenuado opacity:0.8 de bgPanel ya
          // basta por sí solo para distinguir cuál está activo, sin
          // añadir color encima.

          // navRow/listContainer/etc. van en su propia Column interior en
          // vez de directamente en activePanel -- así statusText, fuera de
          // ella, puede anclarse a parent.bottom (igual que bgStatusText)
          // y quedar en el mismo píxel exacto en los dos tipos de panel.
          // Antes, al ser el último hijo de la Column, su posición salía de
          // sumar navRow+listContainer+márgenes -- una cadena de números
          // reales que no siempre cuadraba pixel a pixel con el bottom:
          // parent.bottom de los paneles de fondo (una simple resta).
          Column {
            id: activeTop
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Style.spacing.rowGap

          Row {
            id: navRow
            width: parent.width
            height: Style.spacing.controlHeight
            spacing: Style.spacing.controlGap

            PanelNavButtons {
              anchors.verticalCenter: parent.verticalCenter
              canGoBack: TabsState.navHistoryIndex > 0
              canGoForward: TabsState.navHistoryIndex < TabsState.navHistory.length - 1
              canGoUp: root.currentPath !== "/"
              onBackRequested: root.navBack()
              onForwardRequested: root.navForward()
              onUpRequested: root.goUp()
            }

            Item {
              id: pathArea
              width: parent.width - 3 * (Style.spacing.controlHeight + Style.spacing.controlGap)
              height: parent.height

              MouseArea {
                // Detrás de las migas de pan: clic en hueco vacío -> editar ruta a mano.
                anchors.fill: parent
                visible: !EditModeState.editingPath
                cursorShape: Qt.IBeamCursor
                onClicked: searchOps.startEditPath()
              }

              BreadcrumbSegments {
                id: breadcrumbRow
                visible: !EditModeState.editingPath
                anchors.fill: parent
                segments: root.pathSegments()
                activePath: root.currentPath
              }

              TextField {
                id: pathField
                visible: EditModeState.editingPath
                anchors.fill: parent
                verticalPadding: 2
                Accessible.role: Accessible.EditableText
                Accessible.name: "Path"
                onVisibleChanged: if (visible) { text = root.currentPath; forceActiveFocus(); selectAll() } else list.forceActiveFocus()
                Keys.onPressed: function (event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.navigateTo(text)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    EditModeState.editingPath = false
                    event.accepted = true
                  }
                }
              }
            }
          }

          ActivePanelInputRows {
            id: activeInputRows
            root: root
            list: list
            conflictActions: conflictActions
            searchOps: searchOps
            selectionOps: selectionOps
          }

          Item {
            id: listContainer
            width: parent.width
            // Sin el "- Style.spacing.hairline" que llevaba antes: ese
            // único píxel de más hacía que list.height quedara 1px por
            // debajo de bgList.height (misma fórmula, pero bgList lo
            // deriva de anchors reales, sin ese fudge). En una lista con
            // filas no se notaba (solo cambia el margen bajo la última
            // fila), pero el estado vacío, centrado en el alto total,
            // amplificaba ese único píxel a un desajuste visible al
            // cambiar entre panel activo/de fondo.
            // Las tres filas de activeInputRows son mutuamente excluyentes
            // (ver comentario del propio componente) -- su altura ya ES
            // la de la única fila visible, o 0 si ninguna lo está, así
            // que basta un término en vez de sumar los tres por separado.
            height: activePanel.height - navRow.height
              - (EditModeState.creatingFolder || EditModeState.creatingFile || root.searching ? activeInputRows.height + mainColumn.spacing : 0)
              - statusText.height - mainColumn.spacing * (2 + (EditModeState.creatingFolder || EditModeState.creatingFile || root.searching ? 1 : 0))

            ActiveFileList {
              id: list
              anchors.fill: parent
              root: root
              card: card
              gTimer: gTimer
              previewLoader: previewLoader
              conflictActions: conflictActions
              mountOps: mountOps
              fileOps: fileOps
              videoThumbs: videoThumbs
              renameOps: renameOps
              clipboardOps: clipboardOps
              dragDropOps: dragDropOps
              searchOps: searchOps
              fileMeta: fileMeta
              deleteOps: deleteOps
              tabOps: tabOps
              selectionOps: selectionOps
              sortOps: sortOps
              deleteConfirm: deleteConfirm
              renameConflictConfirm: renameConflictConfirm
              extractConflictConfirm: extractConflictConfirm
              compressConflictConfirm: compressConflictConfirm
              bulkRenameConflictConfirm: bulkRenameConflictConfirm
              newFileConflictConfirm: newFileConflictConfirm
              newFolderConflictConfirm: newFolderConflictConfirm
            }

          }
          } // fin activeTop (Column)
              // ---------- Barra de estado ----------
              // Dentro del panel activo, no como hermana global de
              // panelsRow -- antes quedaba siempre debajo de la columna
              // izquierda aunque la información fuera de la pestaña de la
              // derecha, algo que josema notó como desalineado. Fuera de
              // activeTop y anclada a activePanel.bottom (como
              // bgStatusText) para que quede en el mismo píxel exacto.
              Text {
                id: statusText
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                text: root.visibleEntries.length + (root.visibleEntries.length === 1 ? " item" : " items")
                  + (root.searchQuery ? " of " + root.entries.length : "")
                  + (root.searchTruncated ? " · showing first 200" : "")
                  // Sin tope en la carpeta en sí (a diferencia de la
                  // búsqueda) -- cortar un listado normal a los N primeros
                  // rompería el manejo de ficheros de verdad para carpetas
                  // grandes (node_modules, caches de paquetes...). Solo un
                  // aviso informativo de que puede ir lento, no un límite.
                  + (!root.searchQuery && root.entries.length > 5000 ? " · large folder, may be slow" : "")
                  + (SelectionState.selectedIndices.length > 1 ? " · " + SelectionState.selectedIndices.length + " selected" : "")
                  + (ClipboardState.clipboardPaths.length > 0 ? " · clipboard: " + ClipboardState.clipboardPaths.length + (ClipboardState.clipboardPaths.length === 1 ? " item" : " items") + (ClipboardState.clipboardMode === "cut" ? " (cut)" : " (copied)") : "")
                  + " · sort: " + sortOps.sortLabel()
                font.pixelSize: Style.font.subtitle
                font.family: Style.font.family
                color: Color.menu.text
                opacity: 0.55
              }
            } // fin activePanel (Item)
          } // fin panelsRow (Item)
        }
      }

      // El lazo de selección también debe poder arrancar en el hueco entre
      // la barra lateral y el contenido -- `cardRow` es un Row con
      // `spacing: Style.spacing.panelGap` a cada lado del separador
      // vertical, y ese espaciado no pertenece a ningún hijo (ni sidebar ni
      // mainColumn lo cubren), así que ningún MouseArea dentro de
      // `listContainer` llega hasta ahí por mucho z-order que se ajuste.
      // `mapToItem` en vez de aritmética manual con list.y/contentY --
      // ya nos hemos equivocado antes a mano con esas cuentas.
      MouseArea {
        x: cardRow.x + sidebar.width
        y: cardRow.y
        width: 2 * Style.spacing.panelGap + 1
        height: cardRow.height
        acceptedButtons: Qt.LeftButton
        onPressed: function (mouse) {
          var p = mapToItem(list.contentItem, mouse.x, mouse.y)
          var vp = mapToItem(list, mouse.x, mouse.y)
          selectionOps.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
        }
        onPositionChanged: function (mouse) {
          var p = mapToItem(list.contentItem, mouse.x, mouse.y)
          var vp = mapToItem(list, mouse.x, mouse.y)
          selectionOps.moveMarquee(p.x, p.y, vp.y)
        }
        onReleased: selectionOps.endMarquee()
        onCanceled: selectionOps.endMarquee()
      }

      // ---------- Renombrar en lote ----------
      BulkRenamePanel {
        anchors.fill: parent
        open: DialogsState.bulkRenameOpen
        selectedCount: SelectionState.selectedIndices.length
        pattern: DialogsState.bulkRenamePattern
        history: BookmarksState.bulkRenameHistory
        onCloseRequested: DialogsState.bulkRenameOpen = false
        onRenameRequested: function (pattern) { DialogsState.bulkRenamePattern = pattern; conflictActions.commitBulkRename() }
        onFocusReturnRequested: list.forceActiveFocus()
      }

      // ---------- Conectar a servidor ----------
      ConnectServer {
        anchors.fill: parent
        open: DialogsState.connectServerOpen
        connecting: DialogsState.networkConnecting
        uri: DialogsState.connectServerUri
        errorText: DialogsState.connectServerError
        onConnectRequested: function (uri) { DialogsState.connectServerUri = uri; mountOps.commitConnectToServer() }
        onCancelConnectingRequested: mountOps.cancelNetworkConnect()
        onCloseRequested: mountOps.cancelConnectToServer()
        onFocusReturnRequested: list.forceActiveFocus()
      }

      // ---------- Permisos (chmod) ----------
      ChmodPanel {
        anchors.fill: parent
        open: ChmodState.chmodOpen
        names: ChmodState.chmodNames
        mixed: ChmodState.chmodMixed
        mode: ChmodState.chmodMode
        hasDir: ChmodState.chmodHasDir
        recursive: ChmodState.chmodRecursive
        onCloseRequested: ChmodState.chmodOpen = false
        onBitToggled: function (ownerIdx, bit) { fileOps.toggleChmodBit(ownerIdx, bit) }
        onRecursiveToggled: ChmodState.chmodRecursive = !ChmodState.chmodRecursive
        onApplyRequested: function (mode) { fileOps.commitChmod(mode) }
      }

      // ---------- Propiedades ----------
      PropertiesPanel {
        anchors.fill: parent
        open: PropertiesState.propertiesOpen
        multi: PropertiesState.propertiesMulti
        count: PropertiesState.propertiesCount
        entry: PropertiesState.propertiesEntry
        sizeLoading: PropertiesState.propertiesSizeLoading
        size: PropertiesState.propertiesSize
        perms: PropertiesState.propertiesPerms
        owner: PropertiesState.propertiesOwner
        mtime: PropertiesState.propertiesMtime
        onCloseRequested: PropertiesState.propertiesOpen = false
      }

      // ---------- Ayuda de atajos de teclado ----------
      // Primer componente extraído a su propio fichero (ShortcutsHelp.qml)
      // -- ver comentario ahí sobre por qué se eligió este trozo primero.
      ShortcutsHelp {
        anchors.fill: parent
        open: DialogsState.shortcutsHelpOpen
        onRequestClose: DialogsState.shortcutsHelpOpen = false
      }

      // ---------- Copiar/mover en curso ----------
      // No bloquea el resto de la ventana (sin MouseArea de fondo a pantalla
      // completa) -- cp/mv no reportan progreso real, así que esto es solo
      // "sigue vivo" (puntos animados) + Cancel, no una barra de porcentaje.
      BorderSurface {
        id: actionBusyCard
        visible: ActionState.actionBusy
        width: Math.min(parent.width - 80, 420)
        height: actionBusyColumn.implicitHeight + contentTopInset + contentBottomInset
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.lg
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 25

        Column {
          id: actionBusyColumn
          anchors.fill: parent
          anchors.topMargin: actionBusyCard.contentTopInset
          anchors.rightMargin: actionBusyCard.contentRightInset
          anchors.bottomMargin: actionBusyCard.contentBottomInset
          anchors.leftMargin: actionBusyCard.contentLeftInset
          spacing: Style.spacing.xs

          Row {
            id: actionBusyRow
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - cancelActionButton.width - parent.spacing
              // Porcentaje real para copiar/mover (ver
              // startCopyProgress/actionProgressPct); puntos animados
              // para cualquier otra acción, que no tiene un "tamaño
              // total" con el que calcular nada.
              text: ActionState.actionLabel + (ActionState.actionProgressPct >= 0 ? " " + Math.round(ActionState.actionProgressPct) + "%" : root.actionBusyDots)
              font.pixelSize: Style.font.subtitle
              font.family: Style.font.family
              color: Color.menu.text
              elide: Text.ElideRight
            }

            Button {
              id: cancelActionButton
              text: "Cancel"
              bordered: true
              anchors.verticalCenter: parent.verticalCenter
              Accessible.role: Accessible.Button
              Accessible.name: text
              onClicked: root.cancelAction()
            }
          }

          Rectangle {
            visible: ActionState.actionProgressPct >= 0
            width: parent.width
            height: 3
            radius: height / 2
            color: Qt.darker(Color.menu.text, 2.5)

            Rectangle {
              width: parent.width * (ActionState.actionProgressPct / 100)
              height: parent.height
              radius: height / 2
              color: Color.accent

              Behavior on width { NumberAnimation { duration: 200 } }
            }
          }
        }
      }

      Timer {
        running: ActionState.actionBusy
        repeat: true
        interval: 400
        onTriggered: root.actionBusyDots = root.actionBusyDots.length >= 3 ? "" : root.actionBusyDots + "."
      }

      // ---------- Abrir con... ----------
      OpenWithPanel {
        anchors.fill: parent
        open: PreviewState.openWithOpen
        entry: PreviewState.openWithEntry
        apps: PreviewState.openWithApps
        onCloseRequested: PreviewState.openWithOpen = false
        onAppSelected: function (appId) { openWithOps.launchWith(appId) }
      }

      // ---------- Menú contextual ----------
      ContextMenuPanel {
        anchors.fill: parent
        open: ContextMenuState.contextMenuOpen
        menuX: ContextMenuState.contextMenuX
        menuY: ContextMenuState.contextMenuY
        actions: ContextMenuState.contextMenuActions
        onCloseRequested: ContextMenuState.contextMenuOpen = false
      }

      ConfirmDialog {
        id: deleteConfirm
        anchors.fill: parent
        z: 10
        opened: root.pendingDeleteNames.length > 0
        message: root.currentPath === root.trashDir
          ? (root.pendingDeleteNames.length === 1
            ? "Delete \"" + root.pendingDeleteNames[0] + "\" PERMANENTLY? This cannot be undone."
            : "Delete " + root.pendingDeleteNames.length + " items PERMANENTLY? This cannot be undone.")
          : (root.pendingDeleteNames.length === 1
            ? "Send \"" + root.pendingDeleteNames[0] + "\" to trash?"
            : "Send " + root.pendingDeleteNames.length + " items to trash?")
        confirmText: "Delete"
        cancelText: "Cancel"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: root.pendingDeleteNames = []
        onConfirmed: deleteOps.confirmDelete()
      }

      ConfirmDialog {
        id: renameConflictConfirm
        anchors.fill: parent
        z: 10
        opened: ConflictState.renameConflictOpen
        message: ConflictState.pendingRename
          ? "\"" + ConflictState.pendingRename.newPath.substring(ConflictState.pendingRename.newPath.lastIndexOf("/") + 1) + "\" already exists here. Overwrite?"
          : ""
        confirmText: "Overwrite"
        cancelText: "Cancel"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: renameOps.cancelPendingRename()
        onConfirmed: renameOps.runPendingRename(true)
      }

      ConfirmDialog {
        id: newFileConflictConfirm
        anchors.fill: parent
        z: 10
        opened: ConflictState.newFileConflictOpen
        message: ConflictState.pendingNewFile
          ? "\"" + ConflictState.pendingNewFile.name + "\" already exists here. Overwrite?"
          : ""
        confirmText: "Overwrite"
        cancelText: "Cancel"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: renameOps.cancelPendingNewFile()
        onConfirmed: renameOps.runPendingNewFile(true)
      }

      ConfirmDialog {
        id: newFolderConflictConfirm
        anchors.fill: parent
        z: 10
        opened: ConflictState.newFolderConflictOpen
        message: ConflictState.pendingNewFolder
          ? "\"" + ConflictState.pendingNewFolder.name + "\" already exists here. Overwrite?"
          : ""
        confirmText: "Overwrite"
        cancelText: "Cancel"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: renameOps.cancelPendingNewFolder()
        onConfirmed: renameOps.runPendingNewFolder(true)
      }

      ConfirmDialog {
        id: extractConflictConfirm
        anchors.fill: parent
        z: 10
        opened: ConflictState.extractConflictOpen
        message: ConflictState.extractConflictNames.length === 1
          ? "\"" + ConflictState.extractConflictNames[0] + "\" already exists here and will be overwritten."
          : ConflictState.extractConflictNames.length + " items already exist here and will be overwritten."
        confirmText: "Overwrite"
        cancelText: "Cancel"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: archiveActions.cancelPendingExtract()
        onConfirmed: archiveActions.runPendingExtract()
      }

      ConfirmDialog {
        id: compressConflictConfirm
        anchors.fill: parent
        z: 10
        opened: ConflictState.compressConflictOpen
        message: ConflictState.pendingCompress ? "\"" + ConflictState.pendingCompress.archiveName + "\" already exists. Overwrite it?" : ""
        confirmText: "Overwrite"
        cancelText: "Cancel"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: archiveActions.cancelPendingCompress()
        onConfirmed: archiveActions.runPendingCompress()
      }

      ConfirmDialog {
        id: bulkRenameConflictConfirm
        anchors.fill: parent
        z: 10
        opened: ConflictState.bulkRenameConflictOpen
        message: ConflictState.bulkRenameConflictCount === 1
          ? "1 rename would collide with an existing name and will be skipped. Rename the rest?"
          : ConflictState.bulkRenameConflictCount + " renames would collide with existing or duplicate names and will be skipped. Rename the rest?"
        confirmText: "Continue"
        cancelText: "Cancel"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: fileOps.cancelPendingBulkRename()
        onConfirmed: fileOps.runPendingBulkRename()
      }

      // ---------- Conflicto al pegar ----------
      ConflictResolveDialog {
        anchors.fill: parent
        open: ConflictState.pasteConflictOpen
        names: ConflictState.pasteConflictNames
        onOverwriteRequested: clipboardOps.runPaste("overwrite")
        onSkipRequested: clipboardOps.runPaste("skip")
        onCancelRequested: clipboardOps.cancelPasteConflict()
      }

      // ---------- Conflicto al soltar (drag & drop) ----------
      ConflictResolveDialog {
        anchors.fill: parent
        open: ConflictState.dropConflictOpen
        names: ConflictState.dropConflictNames
        onOverwriteRequested: conflictActions.runDrop("overwrite")
        onSkipRequested: conflictActions.runDrop("skip")
        onCancelRequested: dragDropOps.cancelDropConflict()
      }

      // ---------- Paleta de comandos (: o Ctrl+P) ----------
      CommandPalettePanel {
        anchors.fill: parent
        open: PaletteState.paletteOpen
        query: PaletteState.paletteQuery
        index: PaletteState.paletteIndex
        commands: PaletteState.paletteOpen ? root.filteredPaletteCommands() : []
        onQueryEdited: function (text) { PaletteState.paletteQuery = text; PaletteState.paletteIndex = 0 }
        onCloseRequested: root.closePalette()
        onIndexRequested: function (idx) { PaletteState.paletteIndex = idx }
        onCommandActivated: function (idx) { root.runPaletteCommand(idx) }
        onFocusReturnRequested: list.forceActiveFocus()
      }
    }
  }
}

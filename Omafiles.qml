import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
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
  property var tabs: [{ path: homeDir, history: [homeDir], historyIndex: 0 }]
  property int activeTabIndex: 0
  // Historial atrás/adelante de la pestaña ACTIVA -- cada pestaña guarda el
  // suyo propio en su objeto (campos history/historyIndex de arriba) y este
  // par de propiedades es solo la "vista en curso" de esa pestaña, que se
  // intercambia al cambiar de pestaña (ver switchToTab/newTab/etc.).
  property var navHistory: [homeDir]
  property int navHistoryIndex: 0
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

  // ---------- Paneles ----------
  // Cada pestaña abierta se ve a la vez como un panel propio, lado a lado
  // (sustituye a la vista dividida de antes, que era un segundo panel fijo
  // aparte -- ahora cualquier pestaña ES ya un panel visible). Solo el panel
  // ACTIVO tiene la lista/navegación completa de toda la vida (root.entries,
  // marquee, menú contextual...); el resto son paneles sencillos (solo
  // navegar con doble clic y arrastrar), cada uno con su propio listado.
  property int refreshTick: 0

  // Cierra la pestaña/panel en `index`, sea o no la activa (la × de cada
  // panel puede estar en uno que no es el que tiene el foco ahora mismo).
  function closeTabAt(index) {
    if (root.tabs.length <= 1) { root.requestClose(); return }
    if (index === root.activeTabIndex) { root.closeTab(); return }
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

  // ---------- Deshacer/Rehacer (Ctrl+Z / Ctrl+Shift+Z) ----------
  // Pila simple de acciones reversibles: renombrar, nueva carpeta/fichero,
  // borrar (a la papelera), mover (cortar+pegar/arrastrar), renombrado en
  // lote, chmod y enlace. Copiar/comprimir se quedan fuera a propósito --
  // deshacerlos es más ambiguo (¿borrar la copia? ¿y si ya se movió/editó?)
  // que perder por error algo renombrado/movido/borrado/con permisos
  // cambiados.
  property var undoStack: []
  // redoFn es opcional -- solo las entradas que lo llevan aparecen en
  // Ctrl+Shift+Z. Cualquier acción NUEVA (pushUndo de verdad, no un
  // redo/undo de una ya existente) invalida el redo pendiente, mismo
  // comportamiento que cualquier editor de texto.
  property var redoStack: []

  function pushUndo(label, undoFn, redoFn) {
    root.undoStack = root.undoStack.concat([{ label: label, undo: undoFn, redo: redoFn }]).slice(-20)
    root.redoStack = []
  }

  function undoLast() {
    if (root.undoStack.length === 0) return
    var entry = root.undoStack[root.undoStack.length - 1]
    root.undoStack = root.undoStack.slice(0, -1)
    // entry.undo() devuelve lo que runAction() devuelve: false si se
    // descartó por haber otra acción en curso. Antes esto decía "Undone"
    // pase lo que pase, incluso cuando el undo ni siquiera llegó a
    // lanzarse, Y la entrada se perdía de la pila igual. Ahora, si no
    // llegó a lanzarse, se devuelve a la pila para poder reintentarlo.
    var started = entry.undo()
    if (started === false) {
      root.undoStack = root.undoStack.concat([entry])
      Quickshell.execDetached(["notify-send", "Omafiles", "Couldn't undo \"" + entry.label + "\": still busy with another action"])
      return
    }
    // Solo pasa a la pila de redo si de verdad lleva forma de rehacerse
    // -- no todas las entradas del undoStack tienen redoFn (ver el
    // comentario junto a pushUndo).
    if (entry.redo) root.redoStack = root.redoStack.concat([entry]).slice(-20)
    Quickshell.execDetached(["notify-send", "Omafiles", "Undoing: " + entry.label])
  }

  function redoLast() {
    if (root.redoStack.length === 0) return
    var entry = root.redoStack[root.redoStack.length - 1]
    root.redoStack = root.redoStack.slice(0, -1)
    var started = entry.redo()
    if (started === false) {
      root.redoStack = root.redoStack.concat([entry])
      Quickshell.execDetached(["notify-send", "Omafiles", "Couldn't redo \"" + entry.label + "\": still busy with another action"])
      return
    }
    // De vuelta a undoStack SIN pasar por pushUndo() -- eso vaciaría
    // redoStack, que es justo lo que no queremos en pleno ciclo
    // deshacer/rehacer/deshacer.
    root.undoStack = root.undoStack.concat([entry]).slice(-20)
    Quickshell.execDetached(["notify-send", "Omafiles", "Redoing: " + entry.label])
  }

  // Inyectado por el host (shell.qml) via duck-typing al cargar el plugin.
  property var shell: null
  property int selectedIndex: -1
  property var selectedIndices: []
  property int anchorIndex: -1
  property bool showHidden: false

  // ---------- Lazo de selección (arrastrar sobre hueco vacío) ----------
  // Coordenadas en el espacio de contenido de la ListView (independientes
  // del scroll), no del viewport -- así el rectángulo sigue correcto si
  // el usuario arrastra hacia dentro de la zona con scroll.
  property bool marqueeActive: false
  property real marqueeStartX: 0
  property real marqueeStartY: 0
  property real marqueeCurrentX: 0
  property real marqueeCurrentY: 0
  property bool marqueeAdditive: false
  property var marqueeBaseSelection: []
  // Posición del cursor relativa al viewport de `list` (0 = arriba del
  // todo, list.height = abajo del todo) -- para el auto-scroll cuando el
  // lazo llega a un borde con más filas de las que caben en pantalla.
  property real marqueeViewportY: 0
  // Altura real medida de una fila (todas iguales, ver updateMarqueeSelection).
  // Sirve para calcular la altura del footer sin pasar por
  // list.contentHeight -- que en esta versión de Qt incluye al propio
  // footer, y usarlo ahí sería una propiedad que depende de sí misma
  // (confirmado en vivo: "Binding loop detected for property height").
  property real measuredRowHeight: 0

  readonly property var sortKeys: ["name", "size", "mtime", "type"]
  readonly property var sortKeyLabels: ({ name: "Name", size: "Size", mtime: "Date", type: "Type" })
  property string sortKey: "name"
  property bool sortDesc: false

  property int renamingIndex: -1
  property bool creatingFolder: false
  property bool creatingFile: false
  property bool editingPath: false
  // Hay una edición sin confirmar en el panel activo (nombre a medio
  // escribir) -- usado para no tirarla al vuelo por un simple hover sobre
  // otro panel (ver el HoverHandler de bgPanel más abajo).
  readonly property bool hasPendingEdit: root.renamingIndex >= 0 || root.creatingFolder || root.creatingFile || root.editingPath

  // Bug real (auditoría 2026-08-05): cualquier diálogo con un paso de
  // "confirmar" que relee root.currentPath/root.selectedEntries() EN EL
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
  readonly property bool hasBlockingOverlay: root.hasPendingEdit || root.contextMenuOpen
    || root.pendingDeleteNames.length > 0 || root.renameConflictOpen || root.pasteConflictOpen
    || root.extractConflictOpen || root.compressConflictOpen || root.bulkRenameConflictOpen
    || root.dropConflictOpen || root.paletteOpen || root.openWithOpen || root.bulkRenameOpen
    || root.chmodOpen || root.propertiesOpen || root.connectServerOpen

  // Feedback de "en curso". cp/mv no reportan progreso ellos mismos, así
  // que para copiar/mover se ESTIMA por fuera: tamaño total del origen
  // conocido de antemano (du), y un sondeo periódico de cuánto hay ya en
  // el destino mientras la acción corre -- no es exacto al byte (el
  // sondeo tiene un intervalo, y du sobre un fichero a medio escribir da
  // su tamaño en ese instante) pero da una cifra real en vez de solo
  // "sigue vivo". -1 = sin progreso que mostrar (cualquier acción que no
  // sea copiar/mover: renombrar, chmod, comprimir...).
  property bool actionBusy: false
  property string actionLabel: ""
  property string actionBusyDots: ""
  property real actionProgressPct: -1
  property real actionTotalBytes: 0
  property var actionProgressDestPaths: []

  property var clipboardPaths: []
  property string clipboardMode: "" // "copy" | "cut"

  property var pendingDeleteNames: []

  property var pendingRename: null // { oldPath, newPath }
  property bool renameConflictOpen: false

  property var pasteConflictNames: []
  property bool pasteConflictOpen: false

  property var pendingExtract: null // { entry, cmd }
  property var extractConflictNames: []
  property bool extractConflictOpen: false

  property var pendingCompress: null // { archiveName, cmd }
  property bool compressConflictOpen: false

  property var pendingBulkRename: null // [{ oldName, newName, oldPath, newPath }]
  property int bulkRenameInternalDupes: 0
  property int bulkRenameConflictCount: 0
  property bool bulkRenameConflictOpen: false

  // ---------- Arrastrar y soltar ----------
  // Deliberadamente separado del portapapeles de Ctrl+C/X/V (clipboardPaths/
  // clipboardMode) -- un drag no debe pisar lo que el usuario tenga copiado
  // a mano. Interno (misma app) = mover; desde fuera (otra app) = copiar,
  // decidido por DragEvent.source (null si el drag viene de fuera).
  property var dropPendingSources: []
  property string dropTargetDir: ""
  property bool dropIsMove: false
  property var dropConflictNames: []
  property bool dropConflictOpen: false
  property int dropHoverIndex: -1
  property string dropHoverPath: ""

  property bool contextMenuOpen: false
  property real contextMenuX: 0
  property real contextMenuY: 0
  property var contextMenuActions: []

  property bool gPending: false

  property bool paletteOpen: false
  property string paletteQuery: ""
  property int paletteIndex: 0

  property bool previewOpen: false
  property bool openWithOpen: false
  property var openWithApps: []
  property var openWithEntry: null

  property bool bulkRenameOpen: false
  property string bulkRenamePattern: "{name}{ext}"

  property bool chmodOpen: false
  // Lista de nombres en vez de un string suelto -- chmod ahora admite
  // aplicar el mismo modo a toda la selección, no solo a un fichero.
  property var chmodNames: []
  // true si al abrir el diálogo los ítems seleccionados NO tenían todos
  // el mismo modo octal -- chmodMode se deja en blanco en ese caso (no
  // tiene sentido precargar el modo de "uno cualquiera" de ellos) y la UI
  // avisa de que es una selección mixta.
  property bool chmodMixed: false
  property string chmodMode: ""
  // true si al menos uno de los seleccionados es una carpeta -- controla
  // si se muestra el toggle "Apply to subfolders" (chmod -R no tiene
  // nada que ofrecer sobre una selección de solo ficheros).
  property bool chmodHasDir: false
  property bool chmodRecursive: false
  // { "<nombre>": "<modo octal previo>" }, capturado por chmodStatProc al
  // abrir el diálogo -- para poder deshacer. Restaura solo el modo del
  // propio ítem seleccionado, NO el de su contenido si se aplicó con
  // -R -- capturar el árbol entero antes de cambiar nada sería mucho
  // más caro (find+stat recursivo) para lo que pedía el hueco real
  // (chmod era, junto a bulk rename, la única acción de riesgo sin
  // ningún undo).
  property var chmodOriginalModes: ({})

  property bool shortcutsHelpOpen: false

  property bool propertiesOpen: false
  property var propertiesEntry: null
  property string propertiesSize: ""
  property bool propertiesSizeLoading: false
  property string propertiesPerms: ""
  property string propertiesOwner: ""
  property string propertiesMtime: ""
  // Guard de carrera: showProperties()/showPropertiesForSelection() suben
  // este contador cada vez que se abre el panel para un ítem nuevo, y
  // anotan ese número como "dueño" del stat/du que lanzan. Si el usuario
  // cambia de selección antes de que un "du" lento de una carpeta grande
  // termine, la respuesta tardía ya no coincide con propertiesRequestId
  // (que para entonces ya subió) y se descarta en vez de sobreescribir el
  // tamaño del ítem que se está mirando ahora con el de otro distinto.
  property int propertiesRequestId: 0
  property int _propertiesStatOwner: -1
  property int _propertiesDuOwner: -1
  // Selección múltiple: sin permisos/dueño/fecha (no tiene sentido combinar
  // varios), solo cuenta de items y tamaño total.
  property bool propertiesMulti: false
  property int propertiesCount: 0

  readonly property var tarExt: ["tar", "gz", "tgz", "bz2", "tbz", "xz", "txz"]
  property var previewEntry: null
  property string previewText: ""
  property bool previewIsText: false
  // HTML con estilos inline (Pygments, noclasses=True) para el fragmento
  // en previsualización -- vacío si el lenguaje no se reconoce o
  // highlight-preview.sh falla, en cuyo caso se cae al Text plano de
  // siempre con previewText. Ver loadPreview()/highlightPreviewProc.
  property string previewHighlighted: ""
  // Render de la primera página como PNG (pdftoppm) -- vacío mientras se
  // genera o si pdftoppm falla, igual que videoThumbReady con los vídeos.
  property string previewPdfImage: ""
  // Metadatos de audio (ffprobe): duración/formato/bitrate/etc, mismo
  // formato { label, value } que ya usa el Repeater de Properties.
  property var previewAudioInfo: []
  // Guard de carrera, mismo mecanismo que propertiesRequestId: loadPreview()
  // sube este contador cada vez que se previsualiza un ítem nuevo y anota
  // ese número como "dueño" de cada proceso que lanza (texto/resaltado/
  // PDF/audio). Sin esto, seleccionar rápido un fichero A (con highlight-
  // preview.sh/pdftoppm/ffprobe lento) y pasar a un fichero B antes de que
  // termine dejaba que el resultado de A, al llegar tarde, se pintara
  // encima de la previsualización de B.
  property int previewRequestId: 0
  property int _previewTextOwner: -1
  property int _previewHighlightOwner: -1
  property int _previewPdfOwner: -1
  property int _previewAudioOwner: -1

  property string trashDir: root.homeDir + "/.local/share/Trash/files"
  // { "<nombre en Trash/files>": { origPath, epoch } } -- leído de
  // ~/.local/share/Trash/info/*.trashinfo por trash-info.sh, solo cuando
  // el panel activo está mostrando la papelera (ver listProc.onStreamFinished
  // y metaFor()). Antes la papelera se veía como "una carpeta más": el
  // subtítulo mostraba el mtime propio del fichero (de antes de borrarlo)
  // como si fuera la fecha de borrado, y no había forma de saber de dónde
  // venía cada cosa sin mirar el .trashinfo a mano.
  property var trashInfo: ({})
  property var mounts: []
  // Ubicaciones de red (SFTP/SMB/WebDAV/FTP) montadas vía GVfs -- cada
  // una es un directorio real bajo $XDG_RUNTIME_DIR/gvfs/, list-dir.sh la
  // navega igual que cualquier carpeta local sin cambios. Ver
  // list-network-mounts.sh y la sección "NETWORK" de la barra lateral.
  property var networkMounts: []
  property bool connectServerOpen: false
  property string connectServerUri: ""
  property string connectServerError: ""
  // "Conectando…" es un estado propio (no reutiliza actionBusy) porque
  // gio mount puede quedarse colgado esperando credenciales que nunca
  // van a llegar -- necesita su propio botón de Cancelar siempre visible,
  // no compartir el mecanismo de acciones de fichero normal.
  property bool networkConnecting: false

  // Navegar dentro de un .zip/.7z/.rar/.tar sin extraerlo -- root.currentPath
  // NUNCA cambia mientras esto está activo (sigue siendo la carpeta real
  // que contiene el archivo); root.entries pasa a venir de list-archive.sh
  // en vez de list-dir.sh. Deliberadamente de solo lectura: sin selección
  // múltiple/menú contextual/renombrar/borrar/chmod/arrastrar -- ver los
  // guards "if (root.inArchive) return" en cada acción que muta disco.
  property bool inArchive: false
  property string archivePath: ""
  property string archiveSubPath: ""

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

  property var bookmarks: []
  property string bookmarksFile: root.homeDir + "/.local/state/omafiles/bookmarks.json"
  property string recentFile: root.homeDir + "/.local/state/omafiles/recent.json"
  // { path, name } -- más reciente primero, tope 20. Persistido aparte
  // (no en bookmarks.json, semántica distinta: esto lo escribe la propia
  // app sola al abrir ficheros, el usuario no lo edita a mano).
  property var recentFiles: []
  property bool recentLoaded: false
  property string sessionFile: root.homeDir + "/.local/state/omafiles/session.json"
  property string bulkRenameHistoryFile: root.homeDir + "/.local/state/omafiles/bulk-rename-history.json"
  // Patrones usados de verdad en Bulk rename, más reciente primero, tope
  // 8 -- mostrados como accesos rápidos en el propio diálogo en vez de
  // tener que volver a teclearlos cada vez.
  property var bulkRenameHistory: []
  property bool bulkRenameHistoryLoaded: false
  property bool bookmarksLoaded: false

  readonly property var imageExt: ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
  readonly property var videoExt: ["mp4", "mkv", "webm", "avi", "mov", "flv", "m4v"]
  readonly property var audioExt: ["mp3", "flac", "wav", "ogg", "m4a", "opus"]
  readonly property var archiveExt: ["zip", "tar", "gz", "xz", "rar", "7z", "bz2", "zst"]
  readonly property var codeExt: ["js", "ts", "py", "lua", "sh", "c", "cpp", "h", "rs", "go", "html", "css", "json", "qml", "md", "yml", "yaml", "toml"]

  function extOf(name) {
    var idx = name.lastIndexOf(".")
    return idx > 0 ? name.substring(idx + 1).toLowerCase() : ""
  }

  function iconFor(entry) {
    var ext = extOf(entry.name)
    if (ext === "iso") return "󰗮"
    if (imageExt.indexOf(ext) >= 0) return "󰺰"
    if (videoExt.indexOf(ext) >= 0) return "󰸬"
    if (audioExt.indexOf(ext) >= 0) return "󰸪"
    if (archiveExt.indexOf(ext) >= 0) return "󰗄"
    if (ext === "pdf") return "󰈦"
    if (codeExt.indexOf(ext) >= 0) return "󱀫"
    return "󰈤"
  }

  function isImage(entry) {
    return entry.type === "file" && imageExt.indexOf(extOf(entry.name)) >= 0
  }

  function isVideo(entry) {
    return entry.type === "file" && videoExt.indexOf(extOf(entry.name)) >= 0
  }

  function isAudio(entry) {
    return entry.type === "file" && audioExt.indexOf(extOf(entry.name)) >= 0
  }

  function isPdf(entry) {
    return entry.type === "file" && extOf(entry.name) === "pdf"
  }

  // ---------- Miniaturas de vídeo (ffmpegthumbnailer, en cola de 1 a la vez) ----------
  property string thumbCacheDir: root.homeDir + "/.cache/omafiles/thumbnails"
  property var videoThumbReady: ({}) // "ruta|mtime" -> fichero .jpg local
  property var thumbQueue: []
  property bool thumbBusy: false

  // simpleHash/thumbKeyFor/videoThumbPath: movidas a Utils.js (funciones
  // puras). `basePath`/cacheDir ya no son opcionales -- cada llamada de
  // aquí en adelante los pasa explícitos (ver comentario en Utils.js).

  function requestVideoThumb(entry, basePath) {
    basePath = basePath || root.currentPath
    var key = Utils.thumbKeyFor(entry, basePath)
    if (root.videoThumbReady[key]) return
    if (root.thumbQueue.some(function (q) { return Utils.thumbKeyFor(q.entry, q.basePath) === key })) return
    root.thumbQueue = root.thumbQueue.concat([{ entry: entry, basePath: basePath }])
    root.processThumbQueue()
  }

  function processThumbQueue() {
    if (root.thumbBusy || root.thumbQueue.length === 0) return
    root.thumbBusy = true
    var next = root.thumbQueue.slice()
    var queued = next.shift()
    root.thumbQueue = next
    var entry = queued.entry
    var basePath = queued.basePath
    var src = root.joinPath(basePath, entry.name)
    var dest = Utils.videoThumbPath(entry, basePath, root.thumbCacheDir)
    thumbProc.currentKey = Utils.thumbKeyFor(entry, basePath)
    thumbProc.currentDest = dest
    thumbProc.command = ["bash", root.pluginDir + "/thumbnail-video.sh", src, dest]
    thumbProc.running = true
  }

  function isSelected(index) {
    return root.selectedIndices.indexOf(index) >= 0
  }

  function selectOnly(index) {
    root.selectedIndex = index
    root.anchorIndex = index
    root.selectedIndices = index >= 0 ? [index] : []
    if (root.previewOpen) {
      if (index >= 0 && index < root.visibleEntries.length && root.visibleEntries[index].type !== "dir") {
        root.loadPreview(root.visibleEntries[index])
      } else {
        root.previewOpen = false
      }
    }
  }

  function toggleSelect(index) {
    var next = root.selectedIndices.slice()
    var pos = next.indexOf(index)
    if (pos >= 0) next.splice(pos, 1)
    else next.push(index)
    root.selectedIndices = next
    root.selectedIndex = index
    root.anchorIndex = index
  }

  function selectNone() {
    root.selectOnly(-1)
  }

  function invertSelection() {
    var current = root.selectedIndices
    var next = []
    for (var i = 0; i < root.visibleEntries.length; i++) {
      if (current.indexOf(i) < 0) next.push(i)
    }
    root.selectedIndices = next
    root.selectedIndex = next.length > 0 ? next[next.length - 1] : -1
    root.anchorIndex = root.selectedIndex
  }

  function selectRange(index) {
    var start = root.anchorIndex >= 0 ? root.anchorIndex : index
    var from = Math.min(start, index)
    var to = Math.max(start, index)
    var next = []
    for (var i = from; i <= to; i++) next.push(i)
    root.selectedIndices = next
    root.selectedIndex = index
  }

  // Arranca/mueve/termina el lazo -- compartido por todos los catchers que
  // pueden recibir el press inicial (huecos de arriba/abajo/izquierda,
  // gutters de cada fila) para no duplicar la lógica. `contentY` es la
  // posición dentro de list.contentItem (mapToItem ya la da corregida por
  // scroll); `viewportY` es la posición dentro de `list` sin corregir,
  // para detectar si el cursor está pegado a un borde y hace falta
  // auto-scroll.
  function startMarquee(x, contentY, viewportY, ctrlHeld) {
    root.marqueeAdditive = ctrlHeld
    root.marqueeBaseSelection = ctrlHeld ? root.selectedIndices.slice() : []
    if (!ctrlHeld) root.selectOnly(-1)
    root.marqueeStartX = x
    root.marqueeCurrentX = x
    root.marqueeStartY = contentY
    root.marqueeCurrentY = contentY
    root.marqueeViewportY = viewportY
    root.marqueeActive = true
  }

  function moveMarquee(x, contentY, viewportY) {
    if (!root.marqueeActive) return
    root.marqueeCurrentX = x
    root.marqueeCurrentY = contentY
    root.marqueeViewportY = viewportY
    root.updateMarqueeSelection(root.marqueeAdditive, root.marqueeBaseSelection)
  }

  function endMarquee() {
    root.marqueeActive = false
  }

  // Recalcula la selección a partir del rectángulo del lazo (marqueeStartY/
  // marqueeCurrentY, en coordenadas de contenido). Filas de altura uniforme
  // (nombres/metadatos no hacen wrap, siempre una línea) -- basta con
  // dividir por la altura media en vez de inspeccionar los delegados reales
  // de la ListView, más simple y ajeno a la virtualización.
  function updateMarqueeSelection(additive, base) {
    var total = root.visibleEntries.length
    if (total === 0 || root.measuredRowHeight <= 0) return
    var rowH = root.measuredRowHeight
    var contentEnd = total * rowH
    var top = Math.min(root.marqueeStartY, root.marqueeCurrentY)
    var bottom = Math.max(root.marqueeStartY, root.marqueeCurrentY)
    var picked = []
    if (bottom > 0 && top < contentEnd) {
      var firstIdx = Math.max(0, Math.floor(top / rowH))
      var lastIdx = Math.min(total - 1, Math.ceil(bottom / rowH) - 1)
      for (var i = firstIdx; i <= lastIdx; i++) picked.push(i)
    }
    var next = additive
      ? base.concat(picked.filter(function (i) { return base.indexOf(i) < 0 }))
      : picked
    root.selectedIndices = next
    root.selectedIndex = next.length > 0 ? next[next.length - 1] : -1
  }

  function selectedEntries() {
    return root.selectedIndices
      .filter(function (i) { return i >= 0 && i < root.visibleEntries.length })
      .map(function (i) { return root.visibleEntries[i] })
  }

  function refresh() {
    // Centralizado aquí para que TODO lo que ya llama a refresh() (toggle
    // de ocultos, el "Refresh" de la paleta, el onExited de las acciones
    // de fichero...) recargue lo correcto sin tener que acordarse de
    // comprobar inArchive en cada sitio.
    if (root.inArchive) { root.refreshArchiveListing(); return }
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

  function refreshMounts() {
    mountsProc.running = true
  }

  function refreshNetworkMounts() {
    networkMountsProc.running = true
  }

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

  // Llamado al abrir un fichero de verdad (enter()/launchWith(), NO al
  // navegar por carpetas -- para eso ya están el historial y las
  // pestañas). Mueve al principio si ya estaba, tope 20 entradas.
  function addRecent(path, name) {
    var next = root.recentFiles.filter(function (r) { return r.path !== path })
    next.unshift({ path: path, name: name })
    if (next.length > 20) next = next.slice(0, 20)
    root.recentFiles = next
    root.saveRecent()
  }

  function removeRecent(path) {
    root.recentFiles = root.recentFiles.filter(function (r) { return r.path !== path })
    root.saveRecent()
  }

  function clearRecent() {
    root.recentFiles = []
    root.saveRecent()
  }

  // Solo se llama en la primera apertura de la sesión de Quickshell, sin
  // ruta pedida por el host -- ver open(). Carga async (cat + Process,
  // igual que bookmarks/recent); refresh()/startDirWatch se disparan
  // desde el propio handler de loadSessionProc en cuanto sabe la ruta
  // real, no aquí (evita listar homeDir de más si sí había sesión).
  function loadSession() {
    loadSessionProc.running = true
  }

  // Solo guarda la ruta de cada pestaña -- no historial/preview/scroll,
  // eso son sesión "en caliente" (ya sobrevive a cerrar/reabrir sin salir
  // de Quickshell gracias a keepLoaded) y no vale la pena la complejidad
  // de restaurarlo tras un reinicio real del shell.
  function saveSession() {
    root.saveActiveTab()
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

  function addBulkRenameHistory(pattern) {
    pattern = pattern.trim()
    if (!pattern) return
    var next = root.bulkRenameHistory.filter(function (p) { return p !== pattern })
    next.unshift(pattern)
    if (next.length > 8) next = next.slice(0, 8)
    root.bulkRenameHistory = next
    root.saveBulkRenameHistory()
  }

  function removeBookmark(path) {
    root.bookmarks = root.bookmarks.filter(function (b) { return b.path !== path })
    root.saveBookmarks()
  }

  // type: "dir" (por defecto, compatible con marcadores guardados antes
  // de que existiera este campo -- todos eran de carpeta) o "file".
  function addBookmark(path, label, type) {
    if (root.bookmarks.some(function (b) { return b.path === path })) return
    root.bookmarks = root.bookmarks.concat([{ label: label, path: path, type: type || "dir" }])
    root.saveBookmarks()
  }

  // Icono de la barra lateral -- Home/Trash por ruta especial, Imágenes/
  // Vídeos/Música reutilizan el mismo glyph que ya usa iconFor() para esos
  // tipos de fichero (así no hay que mantener dos catálogos de icono), y
  // cualquier otra carpeta (Documents, Downloads, Projects, Almacén,
  // marcadores añadidos a mano...) cae en la carpeta genérica.
  function iconForBookmark(modelData) {
    if (modelData.path === root.homeDir) return "\u{F015}"
    if (modelData.path === root.trashDir) return "\u{F0A7A}"
    // Marcador de fichero suelto (no carpeta) -- icono real por
    // extensión, como en la lista principal, en vez de adivinar por
    // nombre de etiqueta (eso solo tiene sentido para las carpetas
    // especiales de abajo).
    if (modelData.type === "file") return root.iconFor({ type: "file", name: modelData.path.substring(modelData.path.lastIndexOf("/") + 1) })
    var label = modelData.label.toLowerCase()
    if (label.indexOf("picture") >= 0 || label.indexOf("imagen") >= 0) return root.iconFor({ name: "x.jpg" })
    if (label.indexOf("video") >= 0) return root.iconFor({ name: "x.mp4" })
    if (label.indexOf("music") >= 0 || label.indexOf("música") >= 0) return root.iconFor({ name: "x.mp3" })
    return "\u{F024B}"
  }

  function isBookmarked(path) {
    return root.bookmarks.some(function (b) { return b.path === path })
  }

  // parseMounts: movida a Utils.js (función pura).

  function iconForMount(mount) {
    if (mount.fstype === "iso9660") return root.iconFor({ type: "file", name: "x.iso" })
    return mount.removable ? "\u{F0553}" : "\u{F02CA}"
  }

  // parseNetworkMounts: movida a Utils.js (función pura).

  // U+F0870 (md-folder_network) -- ya verificado contra el cmap real de
  // JetBrainsMono Nerd Font en una pasada anterior (ver notas de iconos
  // de tipo de fichero/dispositivo), reservado entonces para esto mismo.
  function iconForNetworkMount(mount) {
    return "\u{F0870}"
  }

  function networkMountActions(mount) {
    return [
      { label: "Open", action: function () { root.navigateTo(mount.path) } },
      { label: "Open in new tab", action: function () { root.openInNewTab(mount.path) } },
      { label: "Disconnect", destructive: true, action: function () { root.disconnectNetworkMount(mount) } }
    ]
  }

  function disconnectNetworkMount(mount) {
    if (networkUnmountProc.running) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Still disconnecting a network location — try again in a moment"])
      return
    }
    networkUnmountProc.wasInside = root.currentPath === mount.path || root.currentPath.indexOf(mount.path + "/") === 0
    networkUnmountProc.tabIndex = root.activeTabIndex
    networkUnmountProc.command = ["gio", "mount", "-u", mount.path]
    networkUnmountProc.running = true
  }

  function startConnectToServer() {
    root.connectServerUri = ""
    root.connectServerError = ""
    root.connectServerOpen = true
  }

  function cancelConnectToServer() {
    root.connectServerOpen = false
  }

  // "setsid" + matar el grupo entero al cancelar, mismo motivo que
  // runAction()/cancelAction(): gio mount puede quedarse esperando
  // credenciales que nunca van a llegar (esta app no tiene un diálogo de
  // usuario/contraseña -- ver comentario largo en connectServerOpen más
  // abajo en el fichero, junto al diálogo), y sin esto Cancelar no
  // conseguiría matar el proceso de verdad.
  function commitConnectToServer() {
    var uri = root.connectServerUri.trim()
    if (!uri) return
    root.connectServerError = ""
    root.networkConnecting = true
    networkMountProc.errorText = ""
    networkMountProc.command = ["setsid", "gio", "mount", "--", uri]
    networkMountProc.running = true
  }

  function cancelNetworkConnect() {
    var pid = networkMountProc.processId
    if (pid) Quickshell.execDetached(["kill", "-TERM", "--", "-" + pid])
    networkMountProc.running = false
    root.networkConnecting = false
  }

  function ejectMount(mount) {
    // Sin esta guardia, hacer doble clic en "Expulsar" reasignaba
    // ejectProc.command a mitad de la primera llamada, reiniciándola --
    // mismo problema que runAction() ya evitaba para las acciones de
    // fichero, pero este proceso no lo tenía.
    // Aviso explícito en vez de un return mudo -- sin esto, el segundo
    // clic no hacía nada visible y parecía que la app había ignorado la
    // pulsación, igual que le pasaba antes a runAction() (ver ahí).
    if (ejectProc.running) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Still ejecting a drive — try again in a moment"])
      return
    }
    var wasInside = root.currentPath === mount.path || root.currentPath.indexOf(mount.path + "/") === 0
    ejectProc.command = ["udisksctl", "unmount", "-b", mount.device]
    ejectProc.mountPath = mount.path
    ejectProc.wasInside = wasInside
    ejectProc.tabIndex = root.activeTabIndex
    ejectProc.device = mount.device
    ejectProc.running = true
  }

  // udisksctl imprime "Mounted /dev/sdX at /run/media/user/Label." -- se
  // extrae la ruta de ahí en vez de relanzar list-mounts.sh y adivinar cuál
  // es la unidad recién montada.
  function mountDevice(mount) {
    if (mountProc.running) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Still mounting a drive — try again in a moment"])
      return
    }
    // Capturado aquí (no releído en onExited) -- si el ratón pasa a otro
    // panel mientras el montaje tarda, el resultado debe navegar el
    // panel que lo pidió, no el que resulte estar activo cuando termine.
    mountProc.tabIndex = root.activeTabIndex
    mountProc.command = ["udisksctl", "mount", "-b", mount.device]
    mountProc.running = true
  }

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

  function compareEntries(a, b) {
    var result = 0
    if (root.sortKey === "size") {
      result = a.size - b.size
    } else if (root.sortKey === "mtime") {
      result = a.mtime - b.mtime
    } else if (root.sortKey === "type") {
      var ea = root.extOf(a.name), eb = root.extOf(b.name)
      result = ea < eb ? -1 : (ea > eb ? 1 : 0)
    }
    if (result === 0) {
      result = Utils.naturalCompare(a.name.toLowerCase(), b.name.toLowerCase())
    }
    return root.sortDesc ? -result : result
  }

  // Las carpetas siempre van antes que los ficheros -- el criterio de orden
  // elegido solo decide cómo se ordena cada grupo entre sí.
  function sortEntries(list) {
    var dirs = list.filter(function (e) { return e.type === "dir" })
    var files = list.filter(function (e) { return e.type !== "dir" })
    dirs.sort(root.compareEntries)
    files.sort(root.compareEntries)
    return dirs.concat(files)
  }

  function sortLabel() {
    return root.sortKeyLabels[root.sortKey] + (root.sortDesc ? " ↓" : " ↑")
  }

  function setSort(key) {
    root.sortKey = key
    root.entries = root.sortEntries(root.entries)
  }

  function cycleSort() {
    var idx = root.sortKeys.indexOf(root.sortKey)
    root.setSort(root.sortKeys[(idx + 1) % root.sortKeys.length])
  }

  function reverseSort() {
    root.sortDesc = !root.sortDesc
    root.entries = root.sortEntries(root.entries)
  }

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
    if (root.inArchive) { root.inArchive = false; root.archivePath = ""; root.archiveSubPath = "" }
    root.currentPath = path
    root.selectOnly(-1)
    root.renamingIndex = -1
    root.creatingFolder = false
    root.creatingFile = false
    root.editingPath = false
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
    if (root.navHistory[root.navHistoryIndex] === path) return
    // Trunca cualquier "adelante" antes de añadir -- mismo comportamiento
    // que el historial de cualquier navegador.
    var h = root.navHistory.slice(0, root.navHistoryIndex + 1)
    h.push(path)
    root.navHistory = h
    root.navHistoryIndex = h.length - 1
  }

  function navBack() {
    if (root.navHistoryIndex <= 0) return
    root.navHistoryIndex -= 1
    root._goToPath(root.navHistory[root.navHistoryIndex])
  }

  function navForward() {
    if (root.navHistoryIndex >= root.navHistory.length - 1) return
    root.navHistoryIndex += 1
    root._goToPath(root.navHistory[root.navHistoryIndex])
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
      root.refreshArchiveListing()
    }
  }

  function _restoreTabPreview(tab) {
    if (tab.previewOpen && tab.previewEntry) {
      root.loadPreview(tab.previewEntry)
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
  function _restoreTabScroll(tab) {
    list.contentY = tab.scrollY || list.originY
  }

  function switchToTab(index) {
    if (index < 0 || index >= root.tabs.length || index === root.activeTabIndex) return
    if (root.hasBlockingOverlay) return
    root.saveActiveTab()
    root.activeTabIndex = index
    root._restoreTabHistory(root.tabs[index])
    root._goToPath(root.tabs[index].path)
    root._restoreTabArchive(root.tabs[index])
    root._restoreTabPreview(root.tabs[index])
    root._restoreTabScroll(root.tabs[index])
  }

  function newTab() {
    root.saveActiveTab()
    root.tabs = root.tabs.concat([{ path: root.currentPath, history: [root.currentPath], historyIndex: 0 }])
    root.activeTabIndex = root.tabs.length - 1
    root.navHistory = [root.currentPath]
    root.navHistoryIndex = 0
  }

  // Para quien no use Ctrl+T -- una pestaña nueva ya apuntando a `path` (una
  // fila de carpeta, un marcador, una unidad), no a la carpeta actual.
  function openInNewTab(path) {
    if (!path) return
    root.saveActiveTab()
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
    root._restoreTabHistory(root.tabs[newIndex])
    root._goToPath(root.tabs[newIndex].path)
    root._restoreTabArchive(root.tabs[newIndex])
    root._restoreTabPreview(root.tabs[newIndex])
    root._restoreTabScroll(root.tabs[newIndex])
  }

  function nextTab() {
    root.switchToTab((root.activeTabIndex + 1) % root.tabs.length)
  }

  function enter(entry) {
    if (!entry) return
    if (root.inArchive) {
      if (entry.type === "dir") {
        root.archiveSubPath = root.archiveSubPath ? root.archiveSubPath + "/" + entry.name : entry.name
        root.refreshArchiveListing()
      } else {
        root.openFileInArchive(entry)
      }
      return
    }
    if (entry.type === "dir") {
      navigateTo(root.joinPath(root.currentPath, entry.name))
    } else if (root.isArchive(entry)) {
      root.enterArchive(root.joinPath(root.currentPath, entry.name))
    } else if (root.isIso(entry)) {
      root.mountIso(entry)
    } else {
      var openPath = root.joinPath(root.currentPath, entry.name)
      openProc.command = ["xdg-open", openPath]
      openProc.running = true
      root.addRecent(openPath, entry.name)
    }
  }

  function enterArchive(path) {
    root.selectOnly(-1)
    root.inArchive = true
    root.archivePath = path
    root.archiveSubPath = ""
    root.refreshArchiveListing()
  }

  function exitArchive() {
    root.inArchive = false
    root.archivePath = ""
    root.archiveSubPath = ""
    root.refresh()
  }

  function refreshArchiveListing() {
    root.selectOnly(-1)
    list.contentY = list.originY
    archiveListProc.command = [root.pluginDir + "/list-archive.sh", root.archivePath, root.archiveSubPath]
    archiveListProc.running = true
  }

  // Extrae SOLO ese fichero a una caché temporal (no todo el archivo) y lo
  // abre con la app por defecto -- "unzip -p"/"tar xO"/etc. vuelcan un
  // único miembro a stdout sin tocar disco más que ese archivo de salida,
  // igual de eficiente que abrir un fichero normal aunque el .zip sea
  // enorme.
  function openFileInArchive(entry) {
    var full = root.archiveSubPath ? root.archiveSubPath + "/" + entry.name : entry.name
    var ext = root.extOf(root.archivePath)
    var out = root.homeDir + "/.cache/omafiles/archive-open/" + Utils.simpleHash(root.archivePath + "|" + full) + "/" + entry.name
    var outDir = out.substring(0, out.lastIndexOf("/"))
    var cmd
    if (ext === "zip") cmd = "unzip -p -- " + Util.shellQuote(root.archivePath) + " " + Util.shellQuote(full) + " > " + Util.shellQuote(out)
    else if (ext === "7z") cmd = "7z x -y -so -- " + Util.shellQuote(root.archivePath) + " " + Util.shellQuote(full) + " 2>/dev/null > " + Util.shellQuote(out)
    else if (ext === "rar") cmd = "unrar p -inul -- " + Util.shellQuote(root.archivePath) + " " + Util.shellQuote(full) + " > " + Util.shellQuote(out)
    else if (root.tarExt.indexOf(ext) >= 0) cmd = "tar xf " + Util.shellQuote(root.archivePath) + " -O " + Util.shellQuote(full) + " > " + Util.shellQuote(out)
    else return
    archiveOpenProc.outPath = out
    archiveOpenProc.command = ["bash", "-c", "mkdir -p -- " + Util.shellQuote(outDir) + " && " + cmd]
    archiveOpenProc.running = true
  }

  function goUp() {
    if (root.inArchive) {
      if (root.archiveSubPath === "") { root.exitArchive(); return }
      var slash = root.archiveSubPath.lastIndexOf("/")
      root.archiveSubPath = slash > 0 ? root.archiveSubPath.substring(0, slash) : ""
      root.refreshArchiveListing()
      return
    }
    if (root.currentPath === "/") return
    var idx = root.currentPath.lastIndexOf("/")
    navigateTo(idx > 0 ? root.currentPath.substring(0, idx) : "/")
  }

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
        root.tabs = [{ path: targetPath, history: [targetPath], historyIndex: 0 }]
        root.navHistory = [targetPath]
        root.navHistoryIndex = 0
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
        root.loadSession()
      }
    } else if (targetPath) {
      // Ya estaba cargado antes (uso normal previo): abre en pestaña
      // nueva para no perder la ubicación en la que ya estaba el usuario.
      root.newTab()
      root.navigateTo(targetPath)
      root.saveActiveTab()
    }

    if (!root.bookmarksLoaded) root.loadBookmarks()
    if (!root.recentLoaded) root.loadRecent()
    if (!root.bulkRenameHistoryLoaded) root.loadBulkRenameHistory()
    root.refreshMounts()
    root.refreshNetworkMounts()
    // Cubre los dos casos restantes: primera carga con target (currentPath
    // recién puesto, arriba) y reabrir apuntando a un target (navigateTo ya
    // lo arrancó dentro de _goToPath, esto solo lo reafirma sobre la misma
    // ruta final) o reabrir SIN target (la ventana estaba cerrada -> close()
    // paró el watcher -> sin esto se reabriría mostrando una carpeta sin
    // vigilar). El caso restante (restoringSession) ya lo cubre
    // loadSessionProc por su cuenta.
    if (!restoringSession && !root.inArchive) root.startDirWatch(root.currentPath)
  }

  function close() {
    root.saveSession()
    root.closingFromHost = true
    root.opened = false
    panel.visible = false
    root.closingFromHost = false
    root.stopDirWatch()
    root.renamingIndex = -1
    root.creatingFolder = false
    root.creatingFile = false
    root.editingPath = false
    root.pendingDeleteNames = []
    root.contextMenuOpen = false
    // keepLoaded:true mantiene vivo el componente entre cierres -- sin
    // resetear esto, la próxima vez que se abra la ventana aparecería el
    // mismo diálogo/panel todavía abierto de la sesión anterior.
    root.propertiesOpen = false
    root.shortcutsHelpOpen = false
    root.chmodOpen = false
    root.openWithOpen = false
    root.bulkRenameOpen = false
    root.previewOpen = false
    root.searching = false
    root.paletteOpen = false
    root.renameConflictOpen = false
    root.pasteConflictOpen = false
    root.dropConflictOpen = false
    root.extractConflictOpen = false
    root.pendingExtract = null
    root.compressConflictOpen = false
    root.pendingCompress = null
    root.bulkRenameConflictOpen = false
    root.pendingBulkRename = null
    root.connectServerOpen = false
  }

  // User-initiated close (Esc, cerrar la última pestaña, botón de cerrar de
  // la ventana). Avisa al shell para que su mapa de paneles abiertos quede
  // consistente y el próximo `toggle` funcione bien -- mismo patrón que
  // dev-gallery/GalleryPanel.qml.
  function requestClose() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide("io.github.percius04.omafiles")
    else root.close()
  }

  function parseAudioInfo(text) {
    var out = []
    var data
    try { data = JSON.parse(text) } catch (e) { return out }
    var fmt = (data && data.format) || {}
    var stream = (data && data.streams && data.streams[0]) || {}
    var dur = parseFloat(fmt.duration || stream.duration || 0)
    if (dur > 0) {
      var mins = Math.floor(dur / 60)
      var secs = Math.round(dur % 60)
      out.push({ label: "Duration", value: mins + ":" + (secs < 10 ? "0" : "") + secs })
    }
    if (stream.codec_name) out.push({ label: "Codec", value: String(stream.codec_name).toUpperCase() })
    if (fmt.bit_rate) out.push({ label: "Bitrate", value: Math.round(fmt.bit_rate / 1000) + " kbps" })
    if (stream.sample_rate) out.push({ label: "Sample rate", value: Math.round(stream.sample_rate / 1000) + " kHz" })
    if (stream.channels) {
      out.push({ label: "Channels", value: stream.channels === 1 ? "Mono" : stream.channels === 2 ? "Stereo" : String(stream.channels) })
    }
    var tags = fmt.tags || {}
    if (tags.artist) out.push({ label: "Artist", value: tags.artist })
    if (tags.title) out.push({ label: "Title", value: tags.title })
    if (tags.album) out.push({ label: "Album", value: tags.album })
    return out
  }

  // formatSize/relativeTime: movidas a Utils.js (funciones puras).

  // Subtítulo de la fila -- tamaño + fecha relativa para ficheros, solo
  // fecha para carpetas (mismo espíritu que el "Connected" de los ejemplos
  // reales de fila compuesta de Omarchy: nombre + una línea de contexto).
  // basePath: la ruta del panel que está pintando esta fila -- por
  // defecto root.currentPath (panel activo), pero un panel de fondo debe
  // pasar la suya propia (bgPanel.modelData.path) o el aviso de "en la
  // papelera" saldría según la carpeta del panel ACTIVO, no la de este
  // panel (mismo tipo de bug ya documentado para thumbKeyFor/etc.).
  function metaFor(entry, basePath) {
    if (entry.link === "broken") return "Broken link"
    var atPath = basePath !== undefined ? basePath : root.currentPath
    if (atPath === root.trashDir) {
      var parts = []
      if (entry.type !== "dir") parts.push(Utils.formatSize(entry.size))
      // root.trashInfo solo se rellena para la papelera del panel ACTIVO
      // (ver listProc) -- si este es un panel de fondo mostrando la
      // papelera, simplemente no hay info extra que añadir todavía; se
      // degrada a solo el tamaño en vez de mostrar algo incorrecto.
      var info = root.trashInfo[entry.name]
      if (info) {
        var rel = Utils.relativeTime(info.epoch)
        parts.push(rel ? "Deleted " + rel : "Deleted")
        if (info.origPath) {
          var slash = info.origPath.lastIndexOf("/")
          parts.push("from " + (slash > 0 ? info.origPath.substring(0, slash) : "/"))
        }
      }
      return parts.join(" · ")
    }
    var parts = []
    if (entry.type !== "dir") parts.push(Utils.formatSize(entry.size))
    var rel = Utils.relativeTime(entry.mtime)
    if (rel) parts.push(rel)
    return parts.join(" · ")
  }

  // onSuccess (opcional) se llama SOLO si el comando termina con exit 0 --
  // úsalo para todo lo que no deba pasar si la acción en realidad falló
  // (sobre todo pushUndo: un undo registrado para algo que nunca ocurrió en
  // disco es peor que no tener undo). Devuelve true si el comando se lanzó,
  // false si se descartó porque ya había otra acción en marcha (el llamador
  // decide si eso merece avisar al usuario).
  function runAction(cmd, busyLabel, onSuccess) {
    // actionProc es un único proceso compartido por todas las acciones de
    // fichero (renombrar, borrar, copiar/mover, comprimir...). Sin esta
    // guardia, una segunda llamada mientras la primera sigue en marcha
    // (doble clic, o una tecla de más durante una operación larga) le
    // cambiaba el comando y lo reiniciaba, cortando la operación en curso
    // a media copia sin ningún aviso.
    if (actionProc.running) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Still busy with the previous action — try again in a moment"])
      return false
    }
    root.actionLabel = busyLabel || ""
    root.actionBusy = !!busyLabel
    root._actionOnSuccess = onSuccess || null
    root._actionCancelled = false
    // "setsid" delante de bash: lo convierte en líder de una sesión/grupo
    // de procesos nuevo (su PGID pasa a ser su propio PID) en vez de
    // compartir el grupo de Quickshell. Sin esto, cancelAction() solo podía
    // matar el "bash -c" en sí -- cualquier cp/mv/zip que ese bash hubiera
    // lanzado como hijo se quedaba huérfano y seguía corriendo de fondo
    // como si nada, aunque la UI ya diera la acción por cancelada.
    actionProc.command = ["setsid", "bash", "-c", cmd]
    actionProc.running = true
    return true
  }

  // Callback pendiente del runAction en curso -- ver actionProc.onExited.
  property var _actionOnSuccess: null
  // true mientras se procesa un cancelAction() explícito -- así
  // actionProc.onExited no muestra "Action failed" por un proceso que el
  // propio usuario mandó parar (sale con código != 0 por la señal, pero
  // eso no es un fallo real).
  property bool _actionCancelled: false

  // Une comandos de una operación por lotes (pegar/soltar/borrar N archivos,
  // renombrado masivo...) para que el fallo de uno no se coma los demás.
  // Antes se unían con "&&": en cuanto el ítem 2 de 5 fallaba (ya no
  // existía, permiso denegado...) los ítems 3-5 no se llegaban a intentar
  // y encima no había ningún aviso. Con esto se intentan todos, y si alguno
  // falla el proceso sale con estado != 0 para que actionProc lo reporte
  // (ver runAction/actionProc más arriba) -- sin decir cuál en concreto,
  // pero ya no se pierden en silencio.
  function chainCmds(cmds) {
    if (cmds.length <= 1) return cmds[0] || "true"
    return "st=0; " + cmds.map(function (c) { return "{ " + c + "; } || st=1" }).join("; ") + "; exit $st"
  }

  function cancelAction() {
    // actionProc.running = false solo mata el "setsid bash -c ..." en sí;
    // con el grupo de procesos propio que le da setsid en runAction(), esto
    // manda la señal a TODO el grupo (setsid + bash + el cp/mv/zip real que
    // esté corriendo dentro), no solo al primero.
    var pid = actionProc.processId
    if (pid) Quickshell.execDetached(["kill", "-TERM", "--", "-" + pid])
    root._actionCancelled = true
    actionProc.running = false
    root.actionBusy = false
    root.actionLabel = ""
    root.actionProgressPct = -1
    root.refresh()
    root.refreshTick += 1
  }

  // Lanza el sondeo de progreso para una copia/movimiento -- llamar justo
  // antes de runAction() con los mismos origen/destino. Sin esto
  // actionProgressPct se queda en -1 (sin barra, solo puntos animados)
  // para cualquier otra acción, que es lo que queremos: chmod/comprimir/
  // renombrar no tienen un "tamaño total" que tenga sentido mostrar así.
  function startCopyProgress(sourcePaths, destPaths) {
    root.actionProgressPct = 0
    root.actionTotalBytes = 0
    root.actionProgressDestPaths = destPaths
    var quoted = sourcePaths.map(function (p) { return Util.shellQuote(p) }).join(" ")
    actionProgressTotalProc.command = ["bash", "-c", "du -sbc -- " + quoted + " | tail -n1 | cut -f1"]
    actionProgressTotalProc.running = true
  }

  function startRename(index) {
    if (root.inArchive) return
    if (index < 0 || index >= root.visibleEntries.length) return
    root.creatingFolder = false
    root.creatingFile = false
    root.renamingIndex = index
  }

  function commitRename(newName) {
    var index = root.renamingIndex
    root.renamingIndex = -1
    // Defensa en profundidad: startRename() ya bloquea EMPEZAR un
    // renombrado dentro de un archivo, pero no cubre el caso de empezar
    // a renombrar FUERA, no confirmar, y entrar en un .zip mientras
    // tanto -- renamingIndex se queda apuntando a un índice que ahora
    // pertenece a una entrada del archivo, y sin este guard commitRename
    // ejecutaría mv sobre currentPath/<nombre-del-zip>, que puede
    // coincidir por casualidad con un fichero real.
    if (root.inArchive) return
    if (index < 0 || index >= root.visibleEntries.length) return
    var oldName = root.visibleEntries[index].name
    newName = newName.trim()
    if (!newName || newName === oldName) return
    var oldPath = root.joinPath(root.currentPath, oldName)
    var newPath = root.joinPath(root.currentPath, newName)
    root.pendingRename = { oldPath: oldPath, newPath: newPath }
    renameCheckProc.command = ["bash", "-c", "test -e " + Util.shellQuote(newPath) + " && echo 1 || echo 0"]
    renameCheckProc.running = true
  }

  function runPendingRename(overwrite) {
    var r = root.pendingRename
    root.pendingRename = null
    root.renameConflictOpen = false
    if (!r) return
    var oldName = r.oldPath.substring(r.oldPath.lastIndexOf("/") + 1)
    // Igual que en makeLinkFor: el undo solo se registra si el "mv" de
    // verdad ocurrió. Antes se registraba siempre, incluso cuando runAction
    // lo descartaba por haber otra acción en curso (el rename ya se había
    // dado por hecho en la UI -- el input se cerraba igual).
    var renameCmd = "mv " + (overwrite ? "-f" : "-n") + " -- " + Util.shellQuote(r.oldPath) + " " + Util.shellQuote(r.newPath)
    runAction(renameCmd, undefined, function () {
      root.pushUndo("rename to \"" + oldName + "\"", function () {
        return root.runAction("mv -n -- " + Util.shellQuote(r.newPath) + " " + Util.shellQuote(r.oldPath))
      }, function () {
        return root.runAction(renameCmd)
      })
    })
  }

  function cancelPendingRename() {
    root.pendingRename = null
    root.renameConflictOpen = false
  }

  function startNewFolder() {
    if (root.inArchive) return
    root.renamingIndex = -1
    root.searching = false
    root.creatingFile = false
    root.creatingFolder = true
  }

  function startNewFile() {
    if (root.inArchive) return
    root.renamingIndex = -1
    root.searching = false
    root.creatingFolder = false
    root.creatingFile = true
  }

  function commitNewFile(name) {
    root.creatingFile = false
    name = name.trim()
    if (!name) return
    var path = root.joinPath(root.currentPath, name)
    // Comprobación de existencia ANTES del touch -- bug real corregido
    // aquí: touch es idempotente (éxito silencioso sobre un fichero que
    // ya existía), así que sin este guard un "New file" con un nombre en
    // conflicto no creaba nada nuevo pero SÍ registraba un undo de "new
    // file" -- un Ctrl+Z posterior mandaba a la papelera el fichero
    // PREEXISTENTE de verdad (con su contenido real), no uno vacío recién
    // creado. Recuperable vía papelera, pero sorprendente y no lo que
    // pedía el README (conflictos tratados, no ignorados en silencio).
    var newFileCmd = "if [ -e " + Util.shellQuote(path) + " ]; then echo " + Util.shellQuote("\"" + name + "\" already exists") + " >&2; exit 1; fi; touch -- " + Util.shellQuote(path)
    runAction(newFileCmd, undefined, function () {
      // gio trash en vez de rm: si el usuario ya escribió algo antes de
      // deshacer, va a la papelera en vez de perderse sin recuperación.
      root.pushUndo("new file \"" + name + "\"", function () {
        return root.runAction("gio trash -- " + Util.shellQuote(path))
      }, function () {
        return root.runAction(newFileCmd)
      })
    })
  }

  function commitNewFolder(name) {
    root.creatingFolder = false
    root.creatingFile = false
    name = name.trim()
    if (!name) return
    var path = root.joinPath(root.currentPath, name)
    // Mismo motivo que commitNewFile: "mkdir -p" no falla si la carpeta
    // ya existe, y sin este guard un Ctrl+Z posterior podía rmdir una
    // carpeta preexistente (vacía) que no tenía nada que ver con esta
    // acción.
    var newFolderCmd = "if [ -e " + Util.shellQuote(path) + " ]; then echo " + Util.shellQuote("\"" + name + "\" already exists") + " >&2; exit 1; fi; mkdir -p -- " + Util.shellQuote(path)
    runAction(newFolderCmd, undefined, function () {
      // rmdir en vez de rm -rf: si el usuario ya metió algo dentro antes de
      // deshacer, falla en vez de borrar contenido a lo tonto.
      root.pushUndo("new folder \"" + name + "\"", function () {
        return root.runAction("rmdir -- " + Util.shellQuote(path))
      }, function () {
        return root.runAction(newFolderCmd)
      })
    })
  }

  function requestDelete() {
    if (root.inArchive) return
    var names = root.selectedEntries().map(function (e) { return e.name })
    if (names.length === 0) return
    root.pendingDeleteNames = names
  }

  function confirmDelete() {
    var names = root.pendingDeleteNames
    root.pendingDeleteNames = []
    if (names.length === 0) return
    if (root.currentPath === root.trashDir) {
      // Borrado permanente -- no hay undo posible. root.trashInfo (ver
      // trash-info.sh) sabe la raíz física real de cada ítem -- puede
      // ser la papelera de casa o la de cualquier otro disco montado,
      // ya no se puede asumir root.trashDir a secas como antes de
      // agregar varias papeleras.
      var cmds = names.map(function (n) {
        var info = root.trashInfo[n]
        if (!info) return "true"
        return "rm -rf -- " + Util.shellQuote(info.trashRoot + "/files/" + n) +
          "; rm -f -- " + Util.shellQuote(info.trashRoot + "/info/" + n + ".trashinfo")
      })
      runAction(root.chainCmds(cmds))
    } else {
      var quoted = names.map(function (n) { return Util.shellQuote(root.joinPath(root.currentPath, n)) }).join(" ")
      // Rutas originales absolutas capturadas AQUÍ (no dentro de los
      // closures de más abajo) -- root.currentPath puede haber cambiado
      // para cuando el usuario pulse deshacer, mucho más tarde.
      var origPaths = names.map(function (n) { return root.joinPath(root.currentPath, n) })
      var label = names.length === 1 ? "delete \"" + names[0] + "\"" : "delete " + names.length + " items"
      var deleteCmd = "gio trash -- " + quoted
      runAction(deleteCmd, "", function () {
        // Solo se registra el undo si el borrado a papelera confirmó éxito
        // -- antes se registraba siempre, así que un "gio trash" fallido
        // (permiso denegado, etc.) dejaba un undo que restauraba algo que
        // nunca llegó a borrarse.
        root.pushUndo(label, function () {
          // restore-by-origpath.sh busca en TODAS las papeleras activas
          // (no solo la de casa) el .trashinfo cuya ruta original
          // coincide, así funciona igual borre desde donde borre --
          // root.trashInfo (usado por el botón "Restore" normal) no
          // sirve aquí porque solo se rellena mientras se está VIENDO
          // la Papelera, y el usuario puede deshacer mucho después sin
          // haber entrado nunca en ella.
          var restoreCmds = origPaths.map(function (p) {
            return "bash " + Util.shellQuote(root.pluginDir + "/restore-by-origpath.sh") + " " + Util.shellQuote(p)
          })
          return root.runAction(root.chainCmds(restoreCmds))
        }, function () {
          return root.runAction(deleteCmd)
        })
      })
    }
  }

  function copySelected() {
    if (root.inArchive) return
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    root.clipboardPaths = entries.map(function (e) { return root.joinPath(root.currentPath, e.name) })
    root.clipboardMode = "copy"
    root.syncClipboardToSystem()
  }

  function cutSelected() {
    if (root.inArchive) return
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    root.clipboardPaths = entries.map(function (e) { return root.joinPath(root.currentPath, e.name) })
    root.clipboardMode = "cut"
    root.syncClipboardToSystem()
  }

  // Antes clipboardPaths era solo interno -- copiar en Omafiles y pegar
  // en otra app (o al revés) no funcionaba. text/uri-list es el tipo MIME
  // más ampliamente reconocido (gestores de archivos, navegadores, apps
  // de chat...) -- wl-copy solo puede servir un tipo por invocación, así
  // que se prioriza compatibilidad amplia sobre poder distinguir cut/copy
  // de cara a OTRAS apps (Omafiles sí distingue cut/copy para sus propias
  // acciones vía clipboardMode; esto es solo para interoperar con fuera).
  // Ruta(s) como texto plano al portapapeles -- para pegar en una
  // terminal/chat/otra app, no confundir con copySelected() (que copia
  // los FICHEROS para pegarlos con paste()). Varias seleccionadas ->
  // una ruta por línea.
  function copyPathFor(entries) {
    if (!entries || entries.length === 0) return
    var paths = entries.map(function (e) { return root.joinPath(root.currentPath, e.name) })
    Quickshell.execDetached(["bash", "-c", "printf '%s' " + Util.shellQuote(paths.join("\n")) + " | wl-copy"])
  }

  function syncClipboardToSystem() {
    if (root.clipboardPaths.length === 0) {
      Quickshell.execDetached(["wl-copy", "-c"])
      return
    }
    // \r\n entre URIs (RFC 2483), no \n a secas -- el DnD mimeData de más
    // abajo (dragMimeDataFor) ya lo hacía bien; esto lo iguala para que
    // cualquier app externa que lea el portapapeles reciba el mismo
    // formato spec-correcto sea cual sea el camino (copiar o arrastrar).
    var uris = root.clipboardPaths.map(function (p) {
      return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }).join("\r\n")
    Quickshell.execDetached(["bash", "-c", "printf '%s' " + Util.shellQuote(uris) + " | wl-copy -t text/uri-list"])
  }

  function paste() {
    if (root.inArchive) return
    if (root.clipboardPaths.length === 0) {
      // Nada copiado desde DENTRO de Omafiles -- probar el portapapeles
      // del sistema (copiar en Nautilus/el navegador/un chat/etc. y
      // pegar aquí). Se trata siempre como "copy", nunca "cut": un
      // text/uri-list suelto no lleva esa distinción (a diferencia del
      // x-special/gnome-copied-files propio de GTK, que no todas las
      // apps que copian rutas escriben).
      systemClipboardReadProc.command = ["wl-paste", "-t", "text/uri-list"]
      systemClipboardReadProc.running = true
      return
    }
    var destPaths = root.clipboardPaths.map(function (src) {
      var name = src.substring(src.lastIndexOf("/") + 1)
      return root.joinPath(root.currentPath, name)
    })
    var checkCmd = destPaths.map(function (p) {
      return "test -e " + Util.shellQuote(p) + " && printf '%s\\n' " + Util.shellQuote(p)
    }).join("; ")
    pasteCheckProc.command = ["bash", "-c", checkCmd]
    pasteCheckProc.running = true
  }

  // mode: "all" (sin conflictos, tal cual) | "overwrite" | "skip"
  function runPaste(mode) {
    var conflictSet = {}
    root.pasteConflictNames.forEach(function (n) { conflictSet[n] = true })
    var sources = root.clipboardPaths.filter(function (src) {
      if (mode !== "skip") return true
      var name = src.substring(src.lastIndexOf("/") + 1)
      return !conflictSet[name]
    })
    root.pasteConflictOpen = false
    root.pasteConflictNames = []
    if (sources.length > 0) {
      var noClobber = mode !== "overwrite"
      var isCut = root.clipboardMode === "cut"
      var pairs = sources.map(function (src) {
        var name = src.substring(src.lastIndexOf("/") + 1)
        return { src: src, dest: root.joinPath(root.currentPath, name) }
      })
      var cmds = pairs.map(function (p) {
        var verb = isCut ? ("mv " + (noClobber ? "-n" : "-f") + " --") : ("cp -r " + (noClobber ? "-n" : "-f") + " --")
        return verb + " " + Util.shellQuote(p.src) + " " + Util.shellQuote(p.dest)
      })
      var busyVerb = isCut ? "Moving " : "Copying "
      var busyLabel = pairs.length === 1
        ? busyVerb + "\"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\"…"
        : busyVerb + pairs.length + " items…"
      var pasteMoveCmd = root.chainCmds(cmds)
      root.startCopyProgress(pairs.map(function (p) { return p.src }), pairs.map(function (p) { return p.dest }))
      runAction(pasteMoveCmd, busyLabel, function () {
        if (!isCut) return
        var label = pairs.length === 1
          ? "move \"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\""
          : "move " + pairs.length + " items"
        root.pushUndo(label, function () {
          var undoCmds = pairs.map(function (p) {
            return "mv -n -- " + Util.shellQuote(p.dest) + " " + Util.shellQuote(p.src)
          })
          return root.runAction(root.chainCmds(undoCmds))
        }, function () {
          return root.runAction(pasteMoveCmd)
        })
      })
    }
    if (root.clipboardMode === "cut") {
      root.clipboardPaths = []
      root.clipboardMode = ""
    }
  }

  function cancelPasteConflict() {
    root.pasteConflictOpen = false
    root.pasteConflictNames = []
  }

  // ---------- Arrastrar y soltar ----------
  function urlToPath(url) {
    var s = String(url)
    if (s.indexOf("file://") === 0) s = s.substring(7)
    try { return decodeURIComponent(s) } catch (e) { return s }
  }

  // MimeData del/los ficheros que arranca a arrastrar la fila `index` --
  // si esa fila ya forma parte de una selección múltiple, arrastra toda la
  // selección (igual que Nautilus); si no, solo esa fila.
  function dragMimeDataFor(index) {
    var indices = (root.isSelected(index) && root.selectedIndices.length > 1) ? root.selectedIndices : [index]
    var paths = indices
      .filter(function (i) { return i >= 0 && i < root.visibleEntries.length })
      .map(function (i) { return root.joinPath(root.currentPath, root.visibleEntries[i].name) })
    var data = {}
    data["text/uri-list"] = paths.map(function (p) { return Util.fileUrl(p) }).join("\r\n")
    return data
  }

  // Ficheros soltados sobre `destDir` (una fila de carpeta, un marcador,
  // una unidad, o el fondo de la lista = la carpeta abierta ahora mismo).
  // `isMove` viene de DragEvent.source !== null (arrastre interno) --
  // arrastres que vienen de fuera siempre copian, nunca mueven el origen.
  function startDropInto(destDir, sourcePaths, isMove) {
    if (!destDir) return
    sourcePaths = sourcePaths.filter(function (src) {
      var srcDir = src.substring(0, src.lastIndexOf("/"))
      // Evita soltar sobre la propia carpeta de origen (no-op) o dentro de
      // sí mismo si el fichero arrastrado es en realidad una carpeta.
      return src !== destDir && srcDir !== destDir && (destDir + "/").indexOf(src + "/") !== 0
    })
    if (sourcePaths.length === 0) return
    root.dropPendingSources = sourcePaths
    root.dropTargetDir = destDir
    root.dropIsMove = isMove
    var destPaths = sourcePaths.map(function (src) {
      return root.joinPath(destDir, src.substring(src.lastIndexOf("/") + 1))
    })
    var checkCmd = destPaths.map(function (p) {
      return "test -e " + Util.shellQuote(p) + " && printf '%s\\n' " + Util.shellQuote(p)
    }).join("; ")
    dropCheckProc.command = ["bash", "-c", checkCmd]
    dropCheckProc.running = true
  }

  // mode: "all" (sin conflictos) | "overwrite" | "skip"
  function runDrop(mode) {
    var conflictSet = {}
    root.dropConflictNames.forEach(function (n) { conflictSet[n] = true })
    var sources = root.dropPendingSources.filter(function (src) {
      if (mode !== "skip") return true
      var name = src.substring(src.lastIndexOf("/") + 1)
      return !conflictSet[name]
    })
    root.dropConflictOpen = false
    root.dropConflictNames = []
    if (sources.length > 0) {
      var noClobber = mode !== "overwrite"
      var destDir = root.dropTargetDir
      var isMove = root.dropIsMove
      var pairs = sources.map(function (src) {
        var name = src.substring(src.lastIndexOf("/") + 1)
        return { src: src, dest: root.joinPath(destDir, name) }
      })
      var cmds = pairs.map(function (p) {
        var verb = isMove ? ("mv " + (noClobber ? "-n" : "-f") + " --") : ("cp -r " + (noClobber ? "-n" : "-f") + " --")
        return verb + " " + Util.shellQuote(p.src) + " " + Util.shellQuote(p.dest)
      })
      var busyVerb = isMove ? "Moving " : "Copying "
      var busyLabel = pairs.length === 1
        ? busyVerb + "\"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\"…"
        : busyVerb + pairs.length + " items…"
      var dropMoveCmd = root.chainCmds(cmds)
      root.startCopyProgress(pairs.map(function (p) { return p.src }), pairs.map(function (p) { return p.dest }))
      runAction(dropMoveCmd, busyLabel, function () {
        if (!isMove) return
        var label = pairs.length === 1
          ? "move \"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\""
          : "move " + pairs.length + " items"
        root.pushUndo(label, function () {
          var undoCmds = pairs.map(function (p) {
            return "mv -n -- " + Util.shellQuote(p.dest) + " " + Util.shellQuote(p.src)
          })
          return root.runAction(root.chainCmds(undoCmds))
        }, function () {
          return root.runAction(dropMoveCmd)
        })
      })
    }
    root.dropPendingSources = []
    root.dropTargetDir = ""
  }

  function cancelDropConflict() {
    root.dropConflictOpen = false
    root.dropConflictNames = []
    root.dropPendingSources = []
    root.dropTargetDir = ""
  }

  // Llamado desde cada DropArea (fila de carpeta, marcador, unidad, fondo
  // de la lista) con el DragEvent real y la carpeta destino ya resuelta.
  function handleFilesDropped(drop, destDir) {
    if (root.inArchive) { drop.accepted = false; return }
    if (!drop.hasUrls) { drop.accepted = false; return }
    var paths = drop.urls.map(function (u) { return root.urlToPath(u) }).filter(function (p) { return p.length > 0 })
    if (paths.length === 0) { drop.accepted = false; return }
    var isMove = drop.source !== null && drop.source !== undefined
    drop.accept(isMove ? Qt.MoveAction : Qt.CopyAction)
    root.startDropInto(destDir, paths, isMove)
  }

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

  function openTerminalHere() {
    openProc.command = ["xdg-terminal-exec", "--dir=" + root.currentPath]
    openProc.running = true
  }

  function paletteCommands() {
    var hasSelection = root.selectedIndices.length > 0
    var entry = root.selectedIndices.length === 1 ? root.visibleEntries[root.selectedIndex] : null
    var cmds = [
      { label: "New folder", run: function () { root.startNewFolder() } },
      { label: "New file", run: function () { root.startNewFile() } },
      { label: "Rename", enabled: root.selectedIndices.length === 1, run: function () { root.startRename(root.selectedIndex) } },
      { label: "Copy", enabled: hasSelection, run: function () { root.copySelected() } },
      { label: "Cut", enabled: hasSelection, run: function () { root.cutSelected() } },
      { label: "Copy path", enabled: hasSelection, run: function () { root.copyPathFor(root.selectedEntries()) } },
      { label: "Paste", enabled: root.clipboardPaths.length > 0, run: function () { root.paste() } },
      { label: "Delete", enabled: hasSelection, run: function () { root.requestDelete() } },
      { label: "Select all", run: function () { root.selectedIndices = Array.from({ length: root.visibleEntries.length }, function (_, i) { return i }) } },
      { label: "Select none", enabled: hasSelection, run: function () { root.selectNone() } },
      { label: "Invert selection", run: function () { root.invertSelection() } },
      { label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", run: function () { root.toggleHidden() } },
      { label: "Refresh", run: function () { root.refresh(); root.refreshMounts(); root.refreshNetworkMounts() } },
      { label: "Sort by name", run: function () { root.setSort("name") } },
      { label: "Sort by size", run: function () { root.setSort("size") } },
      { label: "Sort by date", run: function () { root.setSort("mtime") } },
      { label: "Sort by type", run: function () { root.setSort("type") } },
      { label: "Reverse order", run: function () { root.reverseSort() } },
      { label: root.undoStack.length > 0 ? "Undo: " + root.undoStack[root.undoStack.length - 1].label : "Undo",
        enabled: root.undoStack.length > 0, run: function () { root.undoLast() } },
      { label: root.redoStack.length > 0 ? "Redo: " + root.redoStack[root.redoStack.length - 1].label : "Redo",
        enabled: root.redoStack.length > 0, run: function () { root.redoLast() } },
      { label: "Terminal here", run: function () { root.openTerminalHere() } },
      { label: "Go to Home", run: function () { root.navigateTo(root.homeDir) } },
      { label: "Connect to server...", run: function () { root.startConnectToServer() } },
      { label: "New panel", run: function () { root.newTab() } },
      { label: "Close this panel", enabled: root.tabs.length > 1, run: function () { root.closeTab() } },
      { label: "Back", enabled: root.navHistoryIndex > 0, run: function () { root.navBack() } },
      { label: "Forward", enabled: root.navHistoryIndex < root.navHistory.length - 1, run: function () { root.navForward() } },
      { label: "Edit path", run: function () { root.startEditPath() } },
      { label: "Search", run: function () { root.startSearch() } },
      { label: "Compress to .zip", enabled: hasSelection, run: function () { root.compressSelected() } },
      { label: "Bulk rename...", enabled: root.selectedIndices.length > 1, run: function () { root.startBulkRename() } },
      { label: "Permissions...", enabled: hasSelection, run: function () { root.startChmod(root.selectedEntries()) } },
      { label: "Make link", enabled: !!entry, run: function () { if (entry) root.makeLinkFor(entry) } },
      { label: "Properties", enabled: hasSelection, run: function () { root.showPropertiesForSelection() } },
      { label: "Keyboard shortcuts", run: function () { root.shortcutsHelpOpen = true } }
    ]
    if (root.currentPath === root.trashDir) {
      cmds.push({ label: "Empty trash", run: function () { root.emptyTrash() } })
      cmds.push({ label: "Restore", enabled: hasSelection, run: function () { root.restoreFromTrash() } })
    }
    if (entry && entry.type !== "dir" && root.isArchive(entry)) {
      cmds.push({ label: "Extract here", run: function () { root.extractHere(entry) } })
    }
    if (entry && root.isIso(entry)) {
      cmds.push({ label: "Mount ISO", run: function () { root.mountIso(entry) } })
    }
    if (entry) {
      var fullPath = root.joinPath(root.currentPath, entry.name)
      if (!root.isBookmarked(fullPath)) {
        cmds.push({ label: "Add to bookmarks", run: function () { root.addBookmark(fullPath, entry.name, entry.type) } })
      }
      if (entry.type === "dir") {
        cmds.push({ label: "Open in new tab", run: function () { root.openInNewTab(fullPath) } })
      }
    }
    // Bug real corregido aquí: a diferencia de itemActions() (menú
    // contextual), esta lista no tenía NINGÚN filtro para root.inArchive
    // -- "Add to bookmarks"/"Open in new tab" no tienen guard propio (a
    // diferencia de rename/copy/paste/etc., que sí se auto-protegen
    // dentro de su función) y mezclaban la carpeta real con el nombre de
    // un elemento DENTRO del archivo, escribiendo una ruta rota a
    // bookmarks.json sin avisar. El resto de la lista se filtra aquí
    // también, no porque fuera a romper nada (esas funciones ya son
    // no-op dentro de un archivo) sino para no enseñar entradas muertas.
    if (root.inArchive) {
      var archiveBlocked = ["New folder", "New file", "Rename", "Copy", "Cut", "Copy path", "Paste", "Delete",
        "Compress to .zip", "Bulk rename...", "Permissions...", "Make link", "Properties",
        "Search", "Add to bookmarks", "Open in new tab", "Extract here", "Mount ISO", "Empty trash", "Restore"]
      cmds = cmds.filter(function (c) { return archiveBlocked.indexOf(c.label) < 0 })
    }
    return cmds
  }

  function filteredPaletteCommands() {
    var all = root.paletteCommands()
    if (!root.paletteQuery) return all
    var q = root.paletteQuery.toLowerCase()
    return all.filter(function (c) { return c.label.toLowerCase().indexOf(q) >= 0 })
  }

  function openPalette() {
    root.paletteQuery = ""
    root.paletteIndex = 0
    root.paletteOpen = true
  }

  function closePalette() {
    root.paletteOpen = false
  }

  function runPaletteCommand(index) {
    var cmds = root.filteredPaletteCommands()
    if (index < 0 || index >= cmds.length) return
    var cmd = cmds[index]
    if (cmd.enabled === false) return
    root.closePalette()
    cmd.run()
  }

  function togglePreview() {
    if (root.previewOpen) {
      root.previewOpen = false
      return
    }
    if (root.selectedIndex < 0 || root.selectedIndex >= root.visibleEntries.length) return
    root.loadPreview(root.visibleEntries[root.selectedIndex])
  }

  function loadPreview(entry) {
    if (!entry || entry.type === "dir") return
    root.previewRequestId += 1
    var reqId = root.previewRequestId
    root.previewEntry = entry
    root.previewOpen = true
    root.previewText = ""
    root.previewHighlighted = ""
    root.previewPdfImage = ""
    root.previewAudioInfo = []
    var ext = root.extOf(entry.name)
    var path = root.joinPath(root.currentPath, entry.name)
    root.previewIsText = root.codeExt.indexOf(ext) >= 0 || ext === "txt" || ext === "conf" || ext === ""
    if (root.previewIsText && !root.isImage(entry)) {
      root._previewTextOwner = reqId
      previewProc.command = ["head", "-c", "4000", path]
      previewProc.running = true
      // Resaltado de sintaxis SOLO para extensiones de código conocidas
      // (codeExt) -- .txt/.conf/sin extensión se quedan en texto plano,
      // no hay lenguaje real que adivinar ahí. Se lanza en paralelo al
      // texto plano de arriba (no en cadena): si highlight-preview.sh
      // falla o Pygments no reconoce el lenguaje, previewHighlighted se
      // queda vacío y el texto plano ya cargado sigue siendo lo que se
      // ve, sin parpadeo ni hueco en blanco de por medio.
      if (root.codeExt.indexOf(ext) >= 0) {
        root._previewHighlightOwner = reqId
        highlightPreviewProc.command = [root.pluginDir + "/highlight-preview.sh", path, "4000", ext]
        highlightPreviewProc.running = true
      }
    }
    if (root.isVideo(entry)) root.requestVideoThumb(entry)
    if (root.isPdf(entry)) {
      // Cacheado por hash(ruta+mtime), igual que las miniaturas de vídeo
      // -- no vuelve a renderizar la primera página si ya existe de una
      // vista previa anterior del mismo fichero sin cambios.
      var outDir = root.homeDir + "/.cache/omafiles/pdf-preview/" + Utils.simpleHash(path + "|" + entry.mtime)
      var outFile = outDir + "/preview.png"
      pdfPreviewProc.outFile = outFile
      root._previewPdfOwner = reqId
      // "page-*.png" en vez de asumir "page-1.png" -- pdftoppm añade
      // ceros de relleno al número de página según hagan falta para el
      // total de páginas del PDF (de 10 páginas en adelante ya sería
      // "page-01.png"), así que se renombra al único fichero que haya
      // salido en vez de adivinar el nombre exacto.
      pdfPreviewProc.command = ["bash", "-c",
        "test -e " + Util.shellQuote(outFile) + " && exit 0; mkdir -p -- " + Util.shellQuote(outDir)
        + " && pdftoppm -png -f 1 -l 1 -scale-to 1000 -- " + Util.shellQuote(path) + " " + Util.shellQuote(outDir + "/page")
        + " && mv -f -- " + Util.shellQuote(outDir) + "/page-*.png " + Util.shellQuote(outFile)]
      pdfPreviewProc.running = true
    }
    if (root.isAudio(entry)) {
      root._previewAudioOwner = reqId
      audioInfoProc.command = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", "--", path]
      audioInfoProc.running = true
    }
  }

  function showOpenWith(entry) {
    if (!entry || entry.type === "dir") return
    root.openWithEntry = entry
    root.openWithApps = []
    openWithProc.command = [root.pluginDir + "/open-with-list.sh", root.joinPath(root.currentPath, entry.name)]
    openWithProc.running = true
    root.openWithOpen = true
  }

  function launchWith(desktopId) {
    if (root.openWithEntry) {
      var openPath = root.joinPath(root.currentPath, root.openWithEntry.name)
      Quickshell.execDetached(["gtk-launch", desktopId, openPath])
      root.addRecent(openPath, root.openWithEntry.name)
    }
    root.openWithOpen = false
    root.openWithEntry = null
  }

  function parseOpenWithApps(text) {
    var lines = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
    return lines.map(function (l) {
      var parts = l.split("\t")
      return { name: parts[0], id: parts[1] }
    })
  }

  function compressSelected() {
    if (root.inArchive) return
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    var archiveName = entries.length === 1
      ? entries[0].name.replace(/\/$/, "") + ".zip"
      : "selected-files.zip"
    var names = entries.map(function (e) { return Util.shellQuote(e.name) }).join(" ")
    // "rm -f" antes del zip: si el usuario confirma sobrescribir un
    // archiveName ya existente, que sea un reemplazo real -- sin el rm,
    // "zip -r" AÑADE/actualiza entradas dentro del zip existente en vez de
    // sustituirlo, así que confirmar "overwrite" no dejaba en realidad un
    // zip limpio con solo lo seleccionado ahora.
    // "./" delante del nombre del zip + "--" delante de la lista: un
    // archivo real llamado, por ejemplo, "-rf" (nombre válido en Linux)
    // se interpretaría como flags de zip en vez de como nombre de fichero.
    // zip no admite "--" antes del propio nombre del zip (error "can't use
    // -- before archive name"), de ahí el "./" en su lugar.
    var cmd = "cd -- " + Util.shellQuote(root.currentPath) + " && rm -f -- " + Util.shellQuote(archiveName)
      + " && zip -r -q " + Util.shellQuote("./" + archiveName) + " -- " + names
    root.pendingCompress = { archiveName: archiveName, cmd: cmd }
    compressCheckProc.command = ["bash", "-c", "test -e " + Util.shellQuote(root.joinPath(root.currentPath, archiveName)) + " && echo 1 || echo 0"]
    compressCheckProc.running = true
  }

  function runPendingCompress() {
    var p = root.pendingCompress
    root.pendingCompress = null
    root.compressConflictOpen = false
    if (!p) return
    runAction(p.cmd, "Compressing to \"" + p.archiveName + "\"…")
  }

  function cancelPendingCompress() {
    root.pendingCompress = null
    root.compressConflictOpen = false
  }

  function isArchive(entry) {
    if (entry.type === "dir") return false
    var ext = root.extOf(entry.name)
    return ext === "zip" || ext === "7z" || ext === "rar" || root.tarExt.indexOf(ext) >= 0
  }

  function isIso(entry) {
    return entry.type !== "dir" && root.extOf(entry.name) === "iso"
  }

  // A diferencia de isArchive() (enterArchive(), navegación de solo
  // lectura sin montar nada de verdad), un .iso se monta como un
  // dispositivo loop real -- así lo que haya dentro (un instalador, por
  // ejemplo) se puede ejecutar/copiar igual que en cualquier carpeta
  // normal, no solo mirarlo. Aparece en la barra lateral como cualquier
  // otra unidad extraíble en cuanto se monta (list-mounts.sh ya distingue
  // el icono por fstype=iso9660) y se expulsa igual que una.
  function mountIso(entry) {
    if (mountIsoProc.running) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Still mounting an ISO — try again in a moment"])
      return
    }
    mountIsoProc.tabIndex = root.activeTabIndex
    mountIsoProc.command = ["bash", root.pluginDir + "/mount-iso.sh", root.joinPath(root.currentPath, entry.name)]
    mountIsoProc.running = true
  }

  function extractHere(entry) {
    var ext = root.extOf(entry.name)
    var path = Util.shellQuote(root.joinPath(root.currentPath, entry.name))
    var dir = Util.shellQuote(root.currentPath)
    var cmd, listCmd
    // Todas fuerzan sobrescritura (-o/-y/-o+) -- necesario para que
    // runPendingExtract pueda de verdad sobrescribir tras confirmar el
    // aviso de conflicto de abajo. listCmd usa el modo "lista plana" de
    // cada herramienta (nombre por línea, sin cabecera) para saber qué se
    // pisaría, sin necesidad de parsear tablas.
    if (ext === "zip") { cmd = "unzip -o -q " + path + " -d " + dir; listCmd = "unzip -Z1 -- " + path }
    else if (ext === "7z") { cmd = "7z x -y " + path + " -o" + dir; listCmd = "7z l -ba -slt -- " + path + " | grep '^Path = ' | sed 's/^Path = //'" }
    else if (ext === "rar") { cmd = "unrar x -o+ " + path + " " + dir + "/"; listCmd = "unrar lb -- " + path }
    // Sin "--" a propósito, a diferencia de las otras tres -- con "tf"
    // (forma corta agrupada de -t -f) tar toma el token SIGUIENTE como
    // argumento directo de -f, así que un "--" ahí se interpreta como el
    // propio nombre de fichero a abrir y tar falla con "--: No such file
    // or directory". Bug real: esto hacía que la comprobación de
    // conflictos SIEMPRE fallara en silencio para tar/tar.gz/tar.bz2/
    // tar.xz (listCmd no devolvía nada -> 0 conflictos detectados
    // siempre), aunque zip/7z/rar no se vieran afectados.
    else if (root.tarExt.indexOf(ext) >= 0) { cmd = "tar xf " + path + " -C " + dir; listCmd = "tar tf " + path }
    else return
    // Antes esto sobrescribía sin preguntar, a diferencia de pegar/soltar/
    // renombrar (que sí comprueban conflictos). Antes de extraer, se lista
    // el contenido del archivo y se comprueba si algún elemento de primer
    // nivel ya existe en la carpeta actual.
    root.pendingExtract = { entry: entry, cmd: cmd }
    extractListProc.command = ["bash", "-c", listCmd]
    extractListProc.running = true
  }

  function runPendingExtract() {
    var p = root.pendingExtract
    root.pendingExtract = null
    root.extractConflictOpen = false
    root.extractConflictNames = []
    if (!p) return
    runAction(p.cmd, "Extracting \"" + p.entry.name + "\"…")
  }

  function cancelPendingExtract() {
    root.pendingExtract = null
    root.extractConflictOpen = false
    root.extractConflictNames = []
  }

  function startBulkRename() {
    if (root.inArchive) return
    root.bulkRenamePattern = "{name}{ext}"
    root.bulkRenameOpen = true
  }

  function commitBulkRename() {
    var entries = root.selectedEntries()
    root.bulkRenameOpen = false
    if (entries.length === 0) return
    var pattern = root.bulkRenamePattern
    root.addBulkRenameHistory(pattern)
    var pairs = entries.map(function (e, i) {
      var ext = e.type === "dir" ? "" : (root.extOf(e.name) ? "." + root.extOf(e.name) : "")
      var base = ext ? e.name.slice(0, -ext.length) : e.name
      var newName = pattern.replace(/\{name\}/g, base).replace(/\{ext\}/g, ext).replace(/\{n\}/g, String(i + 1))
      return {
        oldName: e.name, newName: newName,
        oldPath: root.joinPath(root.currentPath, e.name),
        newPath: root.joinPath(root.currentPath, newName)
      }
    })
    root.pendingBulkRename = pairs
    // Antes esto usaba "mv -n" a ciegas: un patrón que produce un nombre ya
    // existente (o que dos ítems de la propia selección acaben con el
    // mismo nombre nuevo) hacía que mv -n no tocara ESE ítem en concreto,
    // sin ningún aviso de cuál se había quedado sin renombrar. Ahora se
    // comprueban antes los conflictos con lo que ya existe en disco...
    var targetCounts = {}
    pairs.forEach(function (p) {
      if (p.newName === p.oldName) return
      targetCounts[p.newPath] = (targetCounts[p.newPath] || 0) + 1
    })
    // ...y también los conflictos DENTRO de la propia selección (dos
    // ítems que el patrón deja con el mismo nombre nuevo).
    root.bulkRenameInternalDupes = Object.keys(targetCounts).filter(function (k) { return targetCounts[k] > 1 }).length
    var checkCmd = pairs.map(function (p) {
      if (p.newName === p.oldName) return "true"
      return "test -e " + Util.shellQuote(p.newPath) + " && printf '%s\\n' " + Util.shellQuote(p.newName)
    }).join("; ")
    bulkRenameCheckProc.command = ["bash", "-c", checkCmd]
    bulkRenameCheckProc.running = true
  }

  function runPendingBulkRename() {
    var pairs = root.pendingBulkRename
    root.pendingBulkRename = null
    root.bulkRenameConflictOpen = false
    if (!pairs) return
    // Antes bulk rename era la única operación de riesgo (junto a chmod)
    // sin ningún undo -- un patrón {n}/{name}/{ext} mal escrito podía
    // renombrar decenas de ficheros de golpe sin red de seguridad.
    var toRename = pairs.filter(function (p) { return p.newName !== p.oldName })
    var cmds = toRename.map(function (p) {
      return "mv -n -- " + Util.shellQuote(p.oldPath) + " " + Util.shellQuote(p.newPath)
    })
    if (cmds.length === 0) return
    var bulkRenameCmd = root.chainCmds(cmds)
    runAction(bulkRenameCmd, "Renaming " + cmds.length + " items…", function () {
      var label = toRename.length === 1 ? "rename \"" + toRename[0].oldName + "\"" : "bulk rename " + toRename.length + " items"
      root.pushUndo(label, function () {
        var undoCmds = toRename.map(function (p) {
          return "mv -n -- " + Util.shellQuote(p.newPath) + " " + Util.shellQuote(p.oldPath)
        })
        return root.runAction(root.chainCmds(undoCmds))
      }, function () {
        return root.runAction(bulkRenameCmd)
      })
    })
  }

  function cancelPendingBulkRename() {
    root.pendingBulkRename = null
    root.bulkRenameConflictOpen = false
  }

  function startChmod(entries) {
    if (root.inArchive) return
    if (!entries || entries.length === 0) return
    root.chmodNames = entries.map(function (e) { return e.name })
    root.chmodMode = ""
    root.chmodMixed = false
    root.chmodHasDir = entries.some(function (e) { return e.type === "dir" })
    root.chmodRecursive = false
    var paths = entries.map(function (e) { return Util.shellQuote(root.joinPath(root.currentPath, e.name)) }).join(" ")
    chmodStatProc.command = ["bash", "-c", "stat -c%a -- " + paths]
    chmodStatProc.running = true
    root.chmodOpen = true
  }

  function commitChmod(mode) {
    root.chmodOpen = false
    mode = mode.trim()
    if (!/^[0-7]{3,4}$/.test(mode) || root.chmodNames.length === 0) return
    // -R es inofensivo sobre un fichero suelto (no baja a ningún sitio),
    // así que se puede aplicar al comando entero sin separar ficheros de
    // carpetas -- más simple que dos ramas de chainCmds distintas.
    var flag = root.chmodRecursive ? "-R " : ""
    var cmds = root.chmodNames.map(function (n) {
      return "chmod " + flag + mode + " -- " + Util.shellQuote(root.joinPath(root.currentPath, n))
    })
    var label = root.chmodNames.length === 1
      ? "Setting permissions for \"" + root.chmodNames[0] + "\"…"
      : "Setting permissions for " + root.chmodNames.length + " items…"
    // chmod era, junto a bulk rename, la única acción de riesgo real
    // (más aún con -R) sin ningún undo. Restaura el modo original de
    // cada ítem seleccionado -- NO el de su contenido si se aplicó
    // recursivo, ver el comentario de chmodOriginalModes.
    var names = root.chmodNames
    var originalModes = root.chmodOriginalModes
    var chmodCmd = root.chainCmds(cmds)
    runAction(chmodCmd, label, function () {
      var undoLabel = names.length === 1 ? "permissions on \"" + names[0] + "\"" : "permissions on " + names.length + " items"
      root.pushUndo(undoLabel, function () {
        var undoCmds = names.filter(function (n) { return !!originalModes[n] }).map(function (n) {
          return "chmod " + originalModes[n] + " -- " + Util.shellQuote(root.joinPath(root.currentPath, n))
        })
        if (undoCmds.length === 0) return false
        return root.runAction(root.chainCmds(undoCmds))
      }, function () {
        return root.runAction(chmodCmd)
      })
    })
  }

  // ownerIdx: 0=owner (tú) 1=group 2=other. bit: 4=read 2=write 1=execute.
  function chmodDigit(ownerIdx) {
    var mode = String(root.chmodMode || "0")
    while (mode.length < 3) mode = "0" + mode
    return parseInt(mode.substring(mode.length - 3).charAt(ownerIdx) || "0", 10)
  }

  function chmodBitSet(ownerIdx, bit) {
    return (root.chmodDigit(ownerIdx) & bit) !== 0
  }

  function toggleChmodBit(ownerIdx, bit) {
    var mode = String(root.chmodMode || "0")
    while (mode.length < 3) mode = "0" + mode
    var digits = mode.substring(mode.length - 3)
    var arr = [digits.charCodeAt(0) - 48, digits.charCodeAt(1) - 48, digits.charCodeAt(2) - 48]
    arr[ownerIdx] = arr[ownerIdx] ^ bit
    root.chmodMode = "" + arr[0] + arr[1] + arr[2]
  }

  function showPropertiesForSelection() {
    // root.currentPath sigue siendo la carpeta real que contiene el
    // archivo mientras se navega dentro de él -- sin este guard,
    // Properties intentaría hacer stat/du de "carpeta-real/nombre-dentro-
    // del-zip", que no existe (o, peor, podría coincidir por casualidad
    // con un fichero real de ese nombre en la carpeta contenedora y
    // enseñar datos de OTRO fichero sin que se note el error).
    if (root.inArchive) return
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    if (entries.length === 1) { root.showProperties(entries[0]); return }
    root.propertiesRequestId += 1
    root.propertiesMulti = true
    root.propertiesEntry = null
    root.propertiesCount = entries.length
    root.propertiesSize = ""
    root.propertiesSizeLoading = true
    root.propertiesPerms = ""
    root.propertiesOwner = ""
    root.propertiesMtime = ""
    root.propertiesOpen = true
    var quoted = entries.map(function (e) {
      return Util.shellQuote(root.joinPath(root.currentPath, e.name))
    }).join(" ")
    root._propertiesDuOwner = root.propertiesRequestId
    propertiesDuProc.command = ["bash", "-c", "du -shc -- " + quoted + " | tail -n1"]
    propertiesDuProc.running = true
  }

  function makeLinkFor(entry) {
    if (root.inArchive) return
    if (!entry) return
    var target = root.joinPath(root.currentPath, entry.name)
    var linkName = "Link to " + entry.name
    var linkPath = root.joinPath(root.currentPath, linkName)
    // El undo solo se registra si "ln -s" confirmó éxito -- antes se
    // registraba a ciegas, así que si ya existía un archivo con el nombre
    // "Link to X" (ln sin -f falla en silencio en ese caso), un Ctrl+Z
    // posterior lo borraba igualmente aunque no tuviera nada que ver con
    // el enlace que se intentó crear.
    var makeLinkCmd = "ln -s -- " + Util.shellQuote(target) + " " + Util.shellQuote(linkPath)
    runAction(makeLinkCmd, undefined, function () {
      root.pushUndo("make link \"" + linkName + "\"", function () {
        return root.runAction("rm -- " + Util.shellQuote(linkPath))
      }, function () {
        return root.runAction(makeLinkCmd)
      })
    })
  }

  function showProperties(entry) {
    if (!entry) return
    root.propertiesRequestId += 1
    root.propertiesMulti = false
    var path = root.joinPath(root.currentPath, entry.name)
    root.propertiesEntry = entry
    root.propertiesSize = entry.type === "dir" ? "" : Utils.formatSize(entry.size)
    root.propertiesSizeLoading = entry.type === "dir"
    root.propertiesPerms = ""
    root.propertiesOwner = ""
    root.propertiesMtime = ""
    root.propertiesOpen = true
    root._propertiesStatOwner = root.propertiesRequestId
    propertiesStatProc.command = ["stat", "-c", "%A %a\t%U:%G\t%y", "--", path]
    propertiesStatProc.running = true
    // Deliberadamente NO se toca propertiesDuProc si entry no es carpeta
    // (el tamaño ya se conoce sin proceso). Un "du" anterior de una
    // carpeta puede seguir corriendo en ese caso -- por eso el guard de
    // _propertiesDuOwner de más abajo es imprescindible, no solo para
    // cuando SÍ se relanza.
    if (entry.type === "dir") {
      root._propertiesDuOwner = root.propertiesRequestId
      propertiesDuProc.command = ["du", "-sh", "--", path]
      propertiesDuProc.running = true
    }
  }

  function restoreFromTrash() {
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    // root.trashInfo (ver trash-info.sh) ya sabe la ruta original
    // absoluta de cada ítem, resuelta correctamente incluso para la
    // papelera de otro disco (donde Path= es relativo al punto de
    // montaje, no a casa) -- restore-by-origpath.sh la usa para
    // localizar el .trashinfo correcto sin asumir una única papelera.
    var cmds = entries
      .filter(function (e) { return !!root.trashInfo[e.name] })
      .map(function (e) {
        return "bash " + Util.shellQuote(root.pluginDir + "/restore-by-origpath.sh") + " " + Util.shellQuote(root.trashInfo[e.name].origPath)
      })
    if (cmds.length === 0) return
    runAction(root.chainCmds(cmds), entries.length === 1 ? "Restoring \"" + entries[0].name + "\"…" : "Restoring " + entries.length + " items…")
  }

  function openContextMenu(x, y, actions) {
    root.contextMenuActions = actions
    root.contextMenuX = Math.min(x, 680)
    root.contextMenuY = y
    root.contextMenuOpen = true
  }

  function itemActions() {
    var entries = root.selectedEntries()
    if (entries.length === 0) return []
    // Dentro de un comprimido solo se navega/abre -- nada de lo demás
    // (renombrar/borrar/chmod/comprimir/copiar/enlazar/marcador) tiene
    // sentido sobre una ruta que no existe de verdad en disco.
    if (root.inArchive) {
      if (entries.length !== 1) return []
      return [{ label: entries[0].type === "dir" ? "Open" : "Open (extracts a temp copy)", action: function () { root.enter(entries[0]) } }]
    }
    var multi = entries.length > 1
    var suffix = multi ? " (" + entries.length + ")" : ""
    var inTrash = root.currentPath === root.trashDir
    var actions = []

    if (inTrash) {
      actions.push({ label: "Restore" + suffix, action: function () { root.restoreFromTrash() } })
      actions.push({ label: "Delete permanently" + suffix, destructive: true, action: function () { root.requestDelete() } })
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
          root.openInNewTab(dirFullPath)
        } })
      } else {
        actions.push({ label: "Open with...", action: function () { root.showOpenWith(entries[0]) } })
      }
    }

    actions.push({ label: "Copy" + suffix, action: function () { root.copySelected() } })
    actions.push({ label: "Cut" + suffix, action: function () { root.cutSelected() } })
    actions.push({ label: "Copy path" + suffix, action: function () { root.copyPathFor(entries) } })
    if (root.clipboardPaths.length > 0) actions.push({ label: "Paste here", action: function () { root.paste() } })

    if (!multi) {
      actions.push({ label: "Rename", action: function () { root.startRename(root.selectedIndex) } })
      actions.push({ label: "Make link", action: function () { root.makeLinkFor(entries[0]) } })
      var fullPath = root.joinPath(root.currentPath, entries[0].name)
      if (!root.isBookmarked(fullPath)) {
        actions.push({ label: "Add to bookmarks", action: function () { root.addBookmark(fullPath, entries[0].name, entries[0].type) } })
      }
      actions.push({ label: "Compress to .zip", action: function () { root.compressSelected() } })
      if (root.isArchive(entries[0])) {
        actions.push({ label: "Extract here", action: function () { root.extractHere(entries[0]) } })
      }
      if (root.isIso(entries[0])) {
        actions.push({ label: "Mount", action: function () { root.mountIso(entries[0]) } })
      }
    } else {
      actions.push({ label: "Bulk rename...", action: function () { root.startBulkRename() } })
      actions.push({ label: "Compress to .zip", action: function () { root.compressSelected() } })
    }

    actions.push({ label: "Permissions...", action: function () { root.startChmod(entries) } })
    actions.push({ label: "Delete" + suffix, destructive: true, action: function () { root.requestDelete() } })
    actions.push({ label: "Properties" + suffix, action: function () { root.showPropertiesForSelection() } })
    actions.push({ label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { root.toggleHidden() } })
    return actions
  }

  function emptyAreaActions() {
    var actions = []
    if (root.currentPath === root.trashDir) {
      actions.push({ label: "Empty trash", destructive: true, action: function () { root.emptyTrash() } })
    } else if (!root.inArchive) {
      // Dentro de un archivo estas ya son no-op (cada función se
      // protege sola), pero se quitan de aquí para no enseñar entradas
      // muertas en el menú de hueco vacío.
      actions.push({ label: "New folder", action: function () { root.startNewFolder() } })
      actions.push({ label: "New file", action: function () { root.startNewFile() } })
      actions.push({ label: "Paste", enabled: root.clipboardPaths.length > 0, action: function () { root.paste() } })
    }
    actions.push({ label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { root.toggleHidden() } })
    actions.push({ label: "Refresh", action: function () { root.refresh(); root.refreshMounts(); root.refreshNetworkMounts() } })
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

  function bookmarkActions(bookmark) {
    var actions = [
      { label: "Open", action: function () { root.openBookmark(bookmark) } }
    ]
    if (bookmark.type !== "file") {
      actions.push({ label: "Open in new tab", action: function () { root.openInNewTab(bookmark.path) } })
    }
    if (bookmark.path === root.trashDir) {
      actions.push({ label: "Empty trash", destructive: true, action: function () { root.emptyTrash() } })
    }
    actions.push({ label: "Remove bookmark", destructive: true, action: function () { root.removeBookmark(bookmark.path) } })
    return actions
  }

  function mountActions(mount) {
    if (!mount.mounted) {
      return [{ label: "Mount", action: function () { root.mountDevice(mount) } }]
    }
    var actions = [
      { label: "Open", action: function () { root.navigateTo(mount.path) } },
      { label: "Open in new tab", action: function () { root.openInNewTab(mount.path) } }
    ]
    if (!root.isBookmarked(mount.path)) {
      actions.push({ label: "Add to bookmarks", action: function () { root.addBookmark(mount.path, mount.label, "dir") } })
    }
    if (mount.removable) {
      actions.push({ label: "Eject", destructive: true, action: function () { root.ejectMount(mount) } })
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
    if (!root.inArchive) return root.pathSegmentsFor(root.currentPath)
    var segs = root.pathSegmentsFor(root.currentPath)
    var archiveName = root.archivePath.substring(root.archivePath.lastIndexOf("/") + 1)
    var parts = root.archiveSubPath ? root.archiveSubPath.split("/") : []
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
    onTriggered: { root.refreshMounts(); root.refreshNetworkMounts() }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.entries = root.sortEntries(Utils.parseEntries(text))
        // Refresca la info de la papelera junto con el listado -- entrar
        // en Trash/files o borrar/restaurar algo estando ya dentro debe
        // mantener origen/fecha al día. Se limpia al salir para no dejar
        // datos obsoletos si se vuelve a entrar más tarde con contenido
        // distinto.
        if (root.currentPath === root.trashDir) {
          trashInfoProc.command = [root.pluginDir + "/trash-info.sh"]
          trashInfoProc.running = true
        } else if (Object.keys(root.trashInfo).length > 0) {
          root.trashInfo = ({})
        }
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
          // selectOnly() ya cubría el caso de 1 (el de siempre: marcador
          // de fichero, reciente, la mayoría de ShowItems reales). Varios
          // a la vez (ShowItems con multi-selección real en el llamador,
          // ver dbus-filemanager1.py) no tenían forma de aplicarse antes
          // -- se resaltaban todos, con el primero como "principal".
          root.selectedIndex = foundIndices[0]
          root.anchorIndex = foundIndices[0]
          root.selectedIndices = foundIndices
          if (root.previewOpen && foundIndices.length > 1) root.previewOpen = false
        } else if (root.selectedIndex >= root.visibleEntries.length) {
          root.selectedIndex = root.visibleEntries.length - 1
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

  Process {
    id: archiveListProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var s = String(text || "")
        var fields = s.length === 0 ? [] : s.split(String.fromCharCode(0))
        if (fields.length > 0 && fields[fields.length - 1] === "") fields.pop()
        var parsed = []
        for (var i = 0; i + 1 < fields.length; i += 2) {
          parsed.push({ type: fields[i + 1] === "1" ? "dir" : "file", name: fields[i], size: 0, mtime: 0, link: "" })
        }
        root.entries = root.sortEntries(parsed)
        list.positionViewAtBeginning()
        root.selectOnly(root.visibleEntries.length > 0 ? 0 : -1)
      }
    }
  }

  Process {
    id: archiveOpenProc
    property string outPath: ""
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: archiveOpenProc.errorText = text
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Quickshell.execDetached(["notify-send", "Omafiles", "Couldn't open file from archive: " + (archiveOpenProc.errorText.trim() || "unknown error")])
        return
      }
      openProc.command = ["xdg-open", archiveOpenProc.outPath]
      openProc.running = true
    }
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
        root.trashInfo = info
      }
    }
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

  Process {
    id: openProc
  }

  Process {
    id: mountsProc
    command: [root.pluginDir + "/list-mounts.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.mounts = Utils.parseMounts(text)
    }
  }

  Process {
    id: ejectProc
    property string mountPath: ""
    property bool wasInside: false
    property int tabIndex: -1
    property string errorText: ""
    property string device: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: ejectProc.errorText = text
    }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        if (ejectProc.wasInside) root.navigateTabTo(ejectProc.tabIndex, root.homeDir)
        // Un .iso montado con mountIso() deja el /dev/loopN asociado al
        // fichero aunque ya esté desmontado -- sin esto, el .iso se queda
        // "en uso" (no se puede mover/borrar) y cada uno gastaría un loop
        // device para siempre hasta reiniciar.
        if (ejectProc.device.indexOf("/dev/loop") === 0) {
          Quickshell.execDetached(["udisksctl", "loop-delete", "-b", ejectProc.device])
        }
        root.refreshMounts()
      } else {
        Quickshell.execDetached(["notify-send", "Omafiles", "Could not eject: " + (ejectProc.errorText || "device busy")])
      }
    }
  }

  Process {
    id: mountProc
    property string outputText: ""
    property string errorText: ""
    property int tabIndex: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: mountProc.outputText = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: mountProc.errorText = text
    }
    onExited: function (exitCode) {
      root.refreshMounts()
      if (exitCode === 0) {
        var match = mountProc.outputText.match(/ at (\/[^\s.]+)/)
        if (match) root.navigateTabTo(mountProc.tabIndex, match[1])
      } else {
        Quickshell.execDetached(["notify-send", "Omafiles", "Could not mount: " + (mountProc.errorText || "unknown error")])
      }
    }
  }

  Process {
    id: mountIsoProc
    property string outputText: ""
    property string errorText: ""
    property int tabIndex: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: mountIsoProc.outputText = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: mountIsoProc.errorText = text
    }
    onExited: function (exitCode) {
      root.refreshMounts()
      if (exitCode === 0) {
        var match = mountIsoProc.outputText.match(/ at (\/[^\s.]+)/)
        if (match) root.navigateTabTo(mountIsoProc.tabIndex, match[1])
      } else {
        Quickshell.execDetached(["notify-send", "Omafiles", "Could not mount ISO: " + (mountIsoProc.errorText || "unknown error")])
      }
    }
  }

  Process {
    id: networkMountsProc
    command: [root.pluginDir + "/list-network-mounts.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.networkMounts = Utils.parseNetworkMounts(text)
    }
  }

  Process {
    id: networkUnmountProc
    property bool wasInside: false
    property int tabIndex: -1
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: networkUnmountProc.errorText = text
    }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        if (networkUnmountProc.wasInside) root.navigateTabTo(networkUnmountProc.tabIndex, root.homeDir)
        root.refreshNetworkMounts()
      } else {
        Quickshell.execDetached(["notify-send", "Omafiles", "Could not disconnect: " + (networkUnmountProc.errorText || "unknown error")])
      }
    }
  }

  // Sin -a/--anonymous ni forma de pasar contraseña: si el servidor pide
  // credenciales, gio necesita un GMountOperation interactivo que esta
  // app no implementa (sería un sub-proyecto en sí mismo, tipo el diálogo
  // "Conectar a servidor" + llavero de Nautilus). Funciona bien para SFTP
  // con clave SSH ya configurada, o cualquier servidor con credenciales
  // ya guardadas en el llavero de una conexión anterior (con Nautilus,
  // por ejemplo) -- si se queda colgado esperando una contraseña que
  // nunca llega, el usuario tiene el botón Cancelar del diálogo
  // (cancelNetworkConnect/setsid, mismo mecanismo que cancelAction()).
  Process {
    id: networkMountProc
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: networkMountProc.errorText = text
    }
    onExited: function (exitCode) {
      root.networkConnecting = false
      if (exitCode === 0) {
        root.connectServerOpen = false
        // gio no imprime la ruta local igual que udisksctl -- se relista
        // y se entra al mount que no estaba antes (el que acaba de
        // aparecer) en vez de parsear la salida de "gio mount".
        networkMountsAfterConnectProc.beforePaths = root.networkMounts.map(function (m) { return m.path })
        networkMountsAfterConnectProc.running = true
      } else {
        root.connectServerError = networkMountProc.errorText.trim() || "Could not connect"
      }
    }
  }

  // Segunda pasada de list-network-mounts.sh tras un connect con éxito,
  // solo para encontrar CUÁL de los mounts es el nuevo (comparando contra
  // los que ya había antes) y navegar directamente a él -- refreshNetworkMounts()
  // normal no distingue cuál acaba de aparecer.
  Process {
    id: networkMountsAfterConnectProc
    property var beforePaths: []
    command: [root.pluginDir + "/list-network-mounts.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Utils.parseNetworkMounts(text)
        root.networkMounts = parsed
        var before = networkMountsAfterConnectProc.beforePaths
        var fresh = parsed.filter(function (m) { return before.indexOf(m.path) < 0 })
        if (fresh.length > 0) root.navigateTo(fresh[0].path)
      }
    }
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
          root.saveBookmarks()
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

  Process {
    id: actionProc
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: actionProc.errorText = text
    }
    onExited: function (exitCode) {
      root.actionBusy = false
      root.actionLabel = ""
      root.actionProgressPct = -1
      root.actionTotalBytes = 0
      root.actionProgressDestPaths = []
      root.refresh()
      // Una acción (borrar, mover, pegar...) puede afectar a cualquier
      // panel, no solo al activo -- refreshTick es la señal para que los
      // paneles no activos (cada uno con su propio Process de listado, ver
      // el Repeater de paneles) se refresquen también.
      root.refreshTick += 1
      var cb = root._actionOnSuccess
      root._actionOnSuccess = null
      var wasCancelled = root._actionCancelled
      root._actionCancelled = false
      if (exitCode === 0) {
        if (cb) cb()
      } else if (!wasCancelled) {
        // Antes esto se tragaba en silencio -- un mv/cp/chmod/zip/unzip que
        // fallara (permisos, disco lleno, archivo corrupto...) se veía
        // exactamente igual que uno que había ido bien.
        Quickshell.execDetached(["notify-send", "Omafiles", "Action failed: " + (actionProc.errorText.trim() || "unknown error")])
      }
    }
  }

  // Tamaño total del origen, UNA vez al principio de una copia/movimiento
  // -- ver startCopyProgress().
  Process {
    id: actionProgressTotalProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(text.trim(), 10)
        root.actionTotalBytes = isNaN(n) ? 0 : n
      }
    }
  }

  // Sondeo periódico de cuánto hay ya en el destino mientras
  // actionBusy+actionTotalBytes>0 -- ver el Timer de abajo, que es quien
  // decide CUÁNDO relanzar esto (no tiene sentido más de un sondeo a la
  // vez si el anterior tarda más que el intervalo).
  Process {
    id: actionProgressPollProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.actionTotalBytes <= 0) return
        var n = parseInt(text.trim(), 10)
        if (isNaN(n)) return
        root.actionProgressPct = Math.min(100, n / root.actionTotalBytes * 100)
      }
    }
  }

  Timer {
    // Un sondeo "du" sobre destinos grandes no es instantáneo -- esta
    // guardia (en vez de solo "repeat: true") evita amontonar sondeos si
    // uno tarda más que el intervalo.
    id: actionProgressPollTimer
    interval: 600
    repeat: true
    running: root.actionBusy && root.actionTotalBytes > 0 && root.actionProgressDestPaths.length > 0
    onTriggered: {
      if (actionProgressPollProc.running) return
      var quoted = root.actionProgressDestPaths.map(function (p) { return Util.shellQuote(p) }).join(" ")
      actionProgressPollProc.command = ["bash", "-c", "du -sbc -- " + quoted + " 2>/dev/null | tail -n1 | cut -f1"]
      actionProgressPollProc.running = true
    }
  }

  Process {
    id: renameCheckProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() === "1") root.renameConflictOpen = true
        else root.runPendingRename(false)
      }
    }
  }

  Process {
    id: systemClipboardReadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Bug real: RFC 2483 exige CRLF entre URIs de un text/uri-list,
        // y las apps GTK reales (Nautilus, selectores de fichero,
        // Firefox...) lo escriben así -- sin quitar el "\r" que queda
        // pegado al final de cada línea, decodeURIComponent lo dejaba
        // colado en el path, pasteCheckProc.test -e nunca lo encontraba,
        // y pegar desde fuera de Omafiles fallaba en silencio sin ningún
        // aviso.
        var uris = String(text || "").split("\n").map(function (l) { return l.replace(/\r$/, "") }).filter(function (l) { return l.length > 0 })
        var paths = uris.map(function (u) {
          return u.indexOf("file://") === 0 ? decodeURIComponent(u.substring(7)) : ""
        }).filter(function (p) { return p.length > 0 })
        // Vacío = portapapeles del sistema sin uris (o sin nada) -- no
        // hay nada que avisar, paste() ya no hacía nada tampoco antes en
        // este caso.
        if (paths.length === 0) return
        root.clipboardPaths = paths
        root.clipboardMode = "copy"
        root.paste()
      }
    }
  }

  Process {
    id: pasteCheckProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var conflicts = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
        if (conflicts.length === 0) {
          root.runPaste("all")
        } else {
          root.pasteConflictNames = conflicts.map(function (p) { return p.substring(p.lastIndexOf("/") + 1) })
          root.pasteConflictOpen = true
        }
      }
    }
  }

  Process {
    id: dropCheckProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var conflicts = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
        if (conflicts.length === 0) {
          root.runDrop("all")
        } else {
          root.dropConflictNames = conflicts.map(function (p) { return p.substring(p.lastIndexOf("/") + 1) })
          root.dropConflictOpen = true
        }
      }
    }
  }

  Process {
    id: compressCheckProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() === "1") root.compressConflictOpen = true
        else root.runPendingCompress()
      }
    }
  }

  Process {
    id: bulkRenameCheckProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var conflicts = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
        var total = conflicts.length + root.bulkRenameInternalDupes
        if (total === 0) {
          root.runPendingBulkRename()
        } else {
          root.bulkRenameConflictCount = total
          root.bulkRenameConflictOpen = true
        }
      }
    }
  }

  // Lista el contenido del archivo antes de extraer (nombre por línea vía
  // el modo "lista plana" de cada herramienta) para poder comprobar
  // conflictos -- ver extractHere().
  Process {
    id: extractListProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var top = {}
        String(text || "").split("\n").forEach(function (line) {
          var name = line.replace(/\/+$/, "")
          if (!name) return
          var slash = name.indexOf("/")
          top[slash >= 0 ? name.substring(0, slash) : name] = true
        })
        var names = Object.keys(top)
        if (names.length === 0) { root.runPendingExtract(); return }
        var checkCmd = names.map(function (n) {
          return "test -e " + Util.shellQuote(root.joinPath(root.currentPath, n)) + " && printf '%s\\n' " + Util.shellQuote(n)
        }).join("; ")
        extractConflictCheckProc.command = ["bash", "-c", checkCmd]
        extractConflictCheckProc.running = true
      }
    }
  }

  Process {
    id: extractConflictCheckProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var conflicts = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
        if (conflicts.length === 0) {
          root.runPendingExtract()
        } else {
          root.extractConflictNames = conflicts
          root.extractConflictOpen = true
        }
      }
    }
  }

  Process {
    id: previewProc
    stdout: StdioCollector {
      waitForEnd: true
      // Descarta si el usuario ya pasó a otro ítem mientras "head"
      // estaba en vuelo -- mismo guard que propertiesDuProc, ver
      // previewRequestId.
      onStreamFinished: if (root._previewTextOwner === root.previewRequestId) root.previewText = text
    }
  }

  Process {
    id: highlightPreviewProc
    stdout: StdioCollector {
      waitForEnd: true
      // Vacío/fallido -> previewHighlighted se queda "" y la UI cae al
      // Text plano (previewText) sin más -- ver el "visible:" de cada
      // bloque en el panel de previsualización.
      onStreamFinished: if (root._previewHighlightOwner === root.previewRequestId) root.previewHighlighted = text
    }
  }

  Process {
    id: pdfPreviewProc
    property string outFile: ""
    onExited: function (exitCode) {
      if (exitCode === 0 && root._previewPdfOwner === root.previewRequestId) root.previewPdfImage = pdfPreviewProc.outFile
    }
  }

  Process {
    id: audioInfoProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root._previewAudioOwner === root.previewRequestId) root.previewAudioInfo = root.parseAudioInfo(text)
    }
  }

  Process {
    id: openWithProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.openWithApps = root.parseOpenWithApps(text)
    }
  }

  Process {
    id: chmodStatProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n").filter(function (l) { return l.length > 0 })
        if (lines.length === 0) return
        var allSame = lines.every(function (l) { return l === lines[0] })
        root.chmodMixed = !allSame
        root.chmodMode = allSame ? lines[0] : ""
        // stat conserva el orden de los argumentos -- lines[i] es el modo
        // de root.chmodNames[i]. Guardado para poder deshacer (ver
        // commitChmod/chmodOriginalModes).
        var orig = {}
        for (var i = 0; i < root.chmodNames.length && i < lines.length; i++) orig[root.chmodNames[i]] = lines[i]
        root.chmodOriginalModes = orig
      }
    }
  }

  Process {
    id: thumbProc
    property string currentKey: ""
    property string currentDest: ""
    onExited: function (exitCode) {
      // Bug real: antes se marcaba "lista" pase lo que pase, aunque
      // ffmpegthumbnailer fallara (formato raro, fichero corrupto, sin
      // memoria un instante) -- requestVideoThumb() nunca reintentaba
      // porque videoThumbReady[key] ya era verdadero (con una ruta que
      // en realidad no existe), así que ese vídeo se quedaba sin
      // miniatura real el resto de la sesión. Ahora solo se marca lista
      // si el proceso terminó bien, así una próxima visita a la carpeta
      // (nueva key por mtime, o simplemente request() de nuevo) puede
      // reintentar.
      if (exitCode === 0) {
        var ready = Object.assign({}, root.videoThumbReady)
        ready[thumbProc.currentKey] = thumbProc.currentDest
        root.videoThumbReady = ready
      }
      root.thumbBusy = false
      root.processThumbQueue()
    }
  }

  Process {
    id: propertiesStatProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Descarta la respuesta si el usuario ya cambió a otro ítem
        // mientras este "stat" estaba en vuelo (ver propertiesRequestId).
        if (root._propertiesStatOwner !== root.propertiesRequestId) return
        var parts = String(text || "").trim().split("\t")
        root.propertiesPerms = parts[0] || ""
        root.propertiesOwner = parts[1] || ""
        root.propertiesMtime = parts[2] || ""
      }
    }
  }

  Process {
    id: propertiesDuProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Mismo guard que propertiesStatProc -- este es el que de verdad
        // importa: un "du" de una carpeta grande puede tardar segundos, y
        // sin esto su resultado tardío pisaba el tamaño del ítem que el
        // usuario esté mirando ahora, aunque ya no tenga nada que ver con
        // la carpeta que se estaba midiendo.
        if (root._propertiesDuOwner !== root.propertiesRequestId) return
        root.propertiesSize = String(text || "").split("\t")[0] || ""
        root.propertiesSizeLoading = false
      }
    }
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
          bookmarks: root.bookmarks
          recentFiles: root.recentFiles
          mounts: root.mounts
          networkMounts: root.networkMounts
          currentPath: root.currentPath
          dropHoverPath: root.dropHoverPath
          positionRelativeTo: card
          iconForBookmark: root.iconForBookmark
          iconFor: root.iconFor
          iconForMount: root.iconForMount
          iconForNetworkMount: root.iconForNetworkMount
          openContextMenu: root.openContextMenu
          bookmarkActionsFor: root.bookmarkActions
          mountActionsFor: root.mountActions
          networkMountActionsFor: root.networkMountActions
          onBookmarkOpened: function (bookmark) { root.openBookmark(bookmark) }
          onRecentOpened: function (item) { root.openRecent(item) }
          onRecentRemoveRequested: function (path) { root.removeRecent(path) }
          onRecentClearRequested: root.clearRecent()
          onMountActivated: function (mount) {
            if (!mount.mounted) root.mountDevice(mount)
            else root.navigateTo(mount.path)
          }
          onNetworkMountOpened: function (mount) { root.navigateTo(mount.path) }
          onConnectRequested: root.startConnectToServer()
          onFilesDropped: function (drop, destPath) { root.handleFilesDropped(drop, destPath) }
          onDropHoverChanged: function (path) { root.dropHoverPath = path }
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
            readonly property int panelCount: root.tabs.length
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
              model: Math.max(0, root.tabs.length - 1)
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
              model: root.tabs

              Item {
                id: bgPanel
                required property var modelData
                required property int index
                visible: index !== root.activeTabIndex
                x: panelsRow.slotX(index)
                y: 0
                width: panelsRow.slotWidth
                height: panelsRow.height
                // Atenuado respecto al panel activo -- con "el panel activo
                // es el que tiene el ratón encima" (ver HoverHandler más
                // abajo), sin ninguna señal visual era fácil no darse
                // cuenta de a qué panel le estaban llegando los atajos de
                // teclado y actuar sobre el equivocado sin querer. Solo
                // opacidad, sin tocar colores del tema.
                opacity: 0.72

                property var entries: []
                property string pathError: ""
                property bool loaded: false

                // Pasar el ratón por encima hace que este panel se vuelva
                // el activo (el que tiene lazo de selección, menú
                // contextual, y responde a los atajos de teclado j/k/F2/
                // Supr/etc.) -- sin esto solo se podía "activar" un panel
                // haciendo clic dentro, y josema quería que baste con
                // colocar el cursor encima. HoverHandler en vez de
                // MouseArea: no roba el evento a los MouseArea de las
                // filas/botones de debajo, solo observa.
                HoverHandler {
                  // No cambiar de panel activo mientras el usuario tiene un
                  // nombre a medio escribir (rename/nueva carpeta/nuevo
                  // fichero/ruta editable) -- switchToTab -> _goToPath
                  // resetea esos campos, y con hover-to-activate bastaba con
                  // cruzar el ratón por el divisor para perder el texto sin
                  // ningún clic de por medio. Tampoco con el menú
                  // contextual abierto -- bug real: el menú se abre sobre
                  // el panel activo de ESE momento, pero si el cursor
                  // pasaba por otro panel de fondo de camino a una entrada
                  // del menú (nada bloqueaba el hover solo por haber un
                  // menú encima), la pestaña activa cambiaba a mitad de
                  // acción y "Open in new tab"/Copy/etc. acababan actuando
                  // sobre la carpeta equivocada.
                  // El guard real vive ahora en switchToTab() (hasBlockingOverlay),
                  // así cubre TODOS los diálogos, no solo estos dos.
                  onHoveredChanged: if (hovered) root.switchToTab(bgPanel.index)
                }

                function refreshMe() {
                  if (!bgPanel.visible) return
                  bgPanel.pathError = ""
                  // Papelera: igual que root.refresh() con el panel activo
                  // -- no es una carpeta real, agrega la de casa más la de
                  // cualquier otro disco montado (list-trash.sh), así que
                  // list-dir.sh a secas contra trashDir solo ve la de casa
                  // y con eso vacía se veía como "papelera vacía" hasta
                  // que este panel pasaba a ser el activo.
                  if (bgPanel.modelData.path === root.trashDir) {
                    bgListProc.command = [root.pluginDir + "/list-trash.sh", root.showHidden ? "1" : "0"]
                  } else {
                    bgListProc.command = [root.pluginDir + "/list-dir.sh", bgPanel.modelData.path, root.showHidden ? "1" : "0"]
                  }
                  bgListProc.running = true
                }

                onVisibleChanged: if (visible) bgPanel.refreshMe()
                onModelDataChanged: bgPanel.refreshMe()
                Connections {
                  target: root
                  function onRefreshTickChanged() { bgPanel.refreshMe() }
                }
                Component.onCompleted: bgPanel.refreshMe()

                Process {
                  id: bgListProc
                  stdout: StdioCollector {
                    waitForEnd: true
                    onStreamFinished: {
                      bgPanel.entries = root.sortEntries(Utils.parseEntries(text))
                      bgPanel.loaded = true
                      root.tabEntriesCache[bgPanel.modelData.path] = bgPanel.entries
                    }
                  }
                  onExited: function (exitCode, exitStatus) {
                    if (exitCode === 2) bgPanel.pathError = "Permission denied"
                    else if (exitCode === 3) bgPanel.pathError = "This folder no longer exists"
                    else if (exitCode === 4) bgPanel.pathError = "Not a folder"
                    else if (exitCode !== 0) bgPanel.pathError = "Couldn't open this folder"
                  }
                }

                DropArea {
                  anchors.fill: parent
                  keys: ["text/uri-list"]
                  onEntered: function (drag) { if (!drag.hasUrls) drag.accepted = false }
                  onDropped: function (drop) { root.handleFilesDropped(drop, bgPanel.modelData.path) }
                }

                Row {
                  id: bgHeaderRow
                  anchors.top: parent.top
                  width: parent.width
                  height: Style.spacing.controlHeight
                  spacing: Style.spacing.controlGap

                  // Misma cabecera que el panel activo (atrás/adelante/casa/
                  // subir) -- josema pidió que las dos se vean iguales, no
                  // solo el panel activo con navegación completa.
                  PanelNavButtons {
                    canGoBack: (bgPanel.modelData.historyIndex || 0) > 0
                    canGoForward: (bgPanel.modelData.historyIndex || 0) < (bgPanel.modelData.history || [bgPanel.modelData.path]).length - 1
                    canGoUp: bgPanel.modelData.path !== "/"
                    onBackRequested: root.navTabBack(bgPanel.index)
                    onForwardRequested: root.navTabForward(bgPanel.index)
                    onUpRequested: {
                      var p = bgPanel.modelData.path
                      var idx = p.lastIndexOf("/")
                      root.navigateTabTo(bgPanel.index, idx > 0 ? p.substring(0, idx) : "/")
                    }
                  }

                  // Migas de pan completas, igual que en el panel activo --
                  // antes solo se veía el nombre de la carpeta actual, sin
                  // el resto de la ruta.
                  BreadcrumbSegments {
                    id: bgBreadcrumbRow
                    width: parent.width - 3 * Style.spacing.controlHeight - 3 * Style.spacing.controlGap
                    height: parent.height
                    segments: root.pathSegmentsFor(bgPanel.modelData.path)
                    activePath: bgPanel.modelData.path
                  }
                }

                PanelSeparator {
                  id: bgHeaderSep
                  anchors.top: bgHeaderRow.bottom
                  // Mismo hueco que separa navRow de listContainer en el
                  // panel activo (mainColumn.spacing, no Style.spacing.sm)
                  // -- con sm quedaba visiblemente más alto que la línea
                  // del panel activo.
                  anchors.topMargin: mainColumn.spacing
                  width: parent.width
                  foreground: Color.menu.text
                  strength: 0.15
                }

                Text {
                  id: bgErrorText
                  visible: bgPanel.pathError !== ""
                  anchors.top: bgHeaderSep.bottom
                  anchors.topMargin: Style.spacing.sm
                  width: parent.width
                  text: bgPanel.pathError
                  font.pixelSize: Style.font.subtitle
                  font.family: Style.font.family
                  color: Color.urgent
                }

                ListView {
                  id: bgList
                  anchors.top: bgErrorText.visible ? bgErrorText.bottom : bgHeaderSep.bottom
                  anchors.topMargin: Style.spacing.md
                  anchors.bottom: bgStatusText.top
                  anchors.bottomMargin: mainColumn.spacing
                  anchors.left: parent.left
                  anchors.right: parent.right
                  clip: true
                  model: bgPanel.entries
                  boundsBehavior: Flickable.StopAtBounds

                  delegate: CursorSurface {
                    id: bgRowSurface
                    required property var modelData
                    required property int index
                    width: bgList.width
                    implicitHeight: bgRowContent.implicitHeight + Style.spacing.md * 2
                    foreground: Color.menu.text
                    accent: Color.accent
                    hasCursor: bgRowMouse.containsMouse
                    // El fill/borde de hover ya es semitransparente de por
                    // sí (Style.hoverFillFor) -- bgPanel entero va a
                    // opacity:0.72 para marcarse como "no es el panel
                    // activo", y sin esto esa opacidad se multiplica TAMBIÉN
                    // sobre el hover, quedando doblemente débil/desvaído en
                    // vez del mismo aspecto que tiene en el panel activo.
                    // 1/0.72 cancela justo la opacidad del padre solo
                    // mientras esta fila concreta tiene el cursor encima.
                    opacity: hasCursor ? 1 / 0.72 : 1

                    DropArea {
                      visible: modelData.type === "dir"
                      anchors.fill: parent
                      keys: ["text/uri-list"]
                      onEntered: function (drag) { if (!drag.hasUrls) drag.accepted = false }
                      onDropped: function (drop) {
                        root.handleFilesDropped(drop, root.joinPath(bgPanel.modelData.path, modelData.name))
                      }
                    }

                    Item {
                      id: bgRowContent
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: 0
                      anchors.rightMargin: Style.spacing.rowPaddingX
                      implicitHeight: bgFileRow.implicitHeight

                      readonly property bool isVid: root.isVideo(modelData)
                      readonly property string vidKey: isVid ? Utils.thumbKeyFor(modelData, bgPanel.modelData.path) : ""
                      readonly property string vidThumb: vidKey ? (root.videoThumbReady[vidKey] || "") : ""

                      Component.onCompleted: if (isVid) root.requestVideoThumb(modelData, bgPanel.modelData.path)

                      FileRowVisual {
                        id: bgFileRow
                        anchors.fill: parent
                        name: modelData.name
                        isDir: modelData.type === "dir"
                        isBroken: modelData.link === "broken"
                        fileIconGlyph: root.iconFor(modelData)
                        // La ruta es la de ESTE panel (bgPanel.modelData.path),
                        // no root.currentPath -- ese es del panel activo, y
                        // era justo lo que hacía fallar la miniatura aquí
                        // cuando este panel no era el activo.
                        thumbSource: root.isImage(modelData) ? Util.fileUrl(root.joinPath(bgPanel.modelData.path, modelData.name))
                          : (parent.vidThumb ? Util.fileUrl(parent.vidThumb) : "")
                        metaText: root.metaFor(modelData, bgPanel.modelData.path)
                      }
                    }

                    MouseArea {
                      id: bgRowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      drag.target: bgDragProxy
                      drag.axis: Drag.XAndYAxis
                      onDoubleClicked: {
                        if (modelData.type === "dir") {
                          root.navigateTabTo(bgPanel.index, root.joinPath(bgPanel.modelData.path, modelData.name))
                        } else {
                          openProc.command = ["xdg-open", root.joinPath(bgPanel.modelData.path, modelData.name)]
                          openProc.running = true
                        }
                      }
                    }

                    Item {
                      id: bgDragProxy
                      width: 1
                      height: 1
                      Drag.active: bgRowMouse.drag.active
                      Drag.dragType: Drag.Automatic
                      Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                      Drag.proposedAction: Qt.MoveAction
                      Drag.mimeData: {
                        var data = {}
                        data["text/uri-list"] = Util.fileUrl(root.joinPath(bgPanel.modelData.path, modelData.name))
                        return data
                      }
                    }
                  }
                }

                EmptyState {
                  visible: bgPanel.pathError === "" && bgPanel.entries.length === 0
                  centerOn: bgList
                  message: bgPanel.modelData.path === root.trashDir ? "Trash is empty" : "Nothing here yet"
                }

                Text {
                  id: bgStatusText
                  anchors.bottom: parent.bottom
                  anchors.left: parent.left
                  anchors.right: parent.right
                  text: bgPanel.entries.length + (bgPanel.entries.length === 1 ? " item" : " items")
                  font.pixelSize: Style.font.subtitle
                  font.family: Style.font.family
                  color: Color.menu.text
                  opacity: 0.55
                }
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
              x: panelsRow.slotX(root.activeTabIndex)
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
              canGoBack: root.navHistoryIndex > 0
              canGoForward: root.navHistoryIndex < root.navHistory.length - 1
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
                visible: !root.editingPath
                cursorShape: Qt.IBeamCursor
                onClicked: root.startEditPath()
              }

              BreadcrumbSegments {
                id: breadcrumbRow
                visible: !root.editingPath
                anchors.fill: parent
                segments: root.pathSegments()
                activePath: root.currentPath
              }

              TextField {
                id: pathField
                visible: root.editingPath
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
                    root.editingPath = false
                    event.accepted = true
                  }
                }
              }
            }
          }

          Row {
            id: newFolderRow
            visible: root.creatingFolder
            width: parent.width
            height: Style.spacing.controlHeight
            spacing: Style.spacing.controlGap

            TextField {
              id: newFolderField
              width: parent.width - 160
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: "New folder name…"
              Accessible.role: Accessible.EditableText
              Accessible.name: "New folder name"
              onVisibleChanged: if (visible) { text = ""; forceActiveFocus() } else list.forceActiveFocus()
              Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitNewFolder(text)
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  root.creatingFolder = false
                  event.accepted = true
                }
              }
            }

            Button {
              text: "Create"
              bordered: true
              anchors.verticalCenter: parent.verticalCenter
              Accessible.role: Accessible.Button
              Accessible.name: "Create folder"
              onClicked: root.commitNewFolder(newFolderField.text)
            }
          }

          Row {
            id: newFileRow
            visible: root.creatingFile
            width: parent.width
            height: Style.spacing.controlHeight
            spacing: Style.spacing.controlGap

            TextField {
              id: newFileField
              width: parent.width - 160
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: "New file name…"
              Accessible.role: Accessible.EditableText
              Accessible.name: "New file name"
              onVisibleChanged: if (visible) { text = ""; forceActiveFocus() } else list.forceActiveFocus()
              Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitNewFile(text)
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  root.creatingFile = false
                  event.accepted = true
                }
              }
            }

            Button {
              text: "Create"
              bordered: true
              anchors.verticalCenter: parent.verticalCenter
              Accessible.role: Accessible.Button
              Accessible.name: "Create file"
              onClicked: root.commitNewFile(newFileField.text)
            }
          }

          Row {
            id: searchRow
            visible: root.searching
            width: parent.width
            height: Style.spacing.controlHeight
            spacing: Style.spacing.controlGap

            // Mismo sangrado que pathArea en navRow (dos botones cuadrados +
            // sus huecos), para que el campo de búsqueda quede alineado bajo
            // la ruta en vez de arrancar en el borde izquierdo.
            Item {
              width: 2 * Style.spacing.controlHeight + Style.spacing.controlGap
              height: 1
            }

            Text {
              text: "/"
              anchors.verticalCenter: parent.verticalCenter
              font.pixelSize: Style.font.title
              font.family: Style.font.family
              color: Color.menu.text
              opacity: 0.6
            }

            TextField {
              id: searchField
              width: parent.width - 30
              anchors.verticalCenter: parent.verticalCenter
              verticalPadding: 2
              placeholderText: "Search here… (Ctrl+Enter searches subfolders)"
              Accessible.role: Accessible.EditableText
              Accessible.name: "Search"
              text: root.searchQuery
              onTextChanged: root.searchQuery = text
              onVisibleChanged: if (visible) forceActiveFocus(); else list.forceActiveFocus()
              Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) {
                  root.exitSearch()
                  event.accepted = true
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                  root.runDeepSearch()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.searching = false
                  root.selectOnly(root.visibleEntries.length > 0 ? 0 : -1)
                  event.accepted = true
                }
              }
            }
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
            height: activePanel.height - navRow.height
              - (root.creatingFolder ? newFolderRow.height + mainColumn.spacing : 0)
              - (root.creatingFile ? newFileRow.height + mainColumn.spacing : 0)
              - (root.searching ? searchRow.height + mainColumn.spacing : 0)
              - statusText.height - mainColumn.spacing * (2 + (root.creatingFolder || root.creatingFile || root.searching ? 1 : 0))

            // Misma línea que separa cabecera y lista en los paneles de
            // fondo (bgHeaderSep) -- va aquí dentro, no como hermana en la
            // Column, para que el hueco entre separador y lista sea el
            // mismo Style.spacing.sm de allí y no el mainColumn.spacing
            // (más ancho) que la Column mete entre CUALQUIER par de hijos.
            PanelSeparator {
              id: listSep
              anchors.top: parent.top
              foreground: Color.menu.text
              strength: 0.15
            }

            MouseArea {
              // Detrás de la lista: clic derecho en hueco vacío -> menú contextual general.
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: root.previewOpen ? parent.width * 0.55 : parent.width
              acceptedButtons: Qt.RightButton
              onClicked: function (mouse) {
                var pos = mapToItem(card, mouse.x, mouse.y)
                root.openContextMenu(pos.x, pos.y, root.emptyAreaActions())
              }
            }

            // Detrás de la lista: soltar aquí (desde otra app, o un arrastre
            // interno sobre hueco vacío en vez de encima de una fila) mete
            // los ficheros en la carpeta abierta ahora mismo. Al ir ANTES
            // que la ListView en el fichero, queda por debajo en el orden de
            // pintado -- el DropArea de cada fila de carpeta, por encima,
            // gana cuando el cursor está sobre ella.
            DropArea {
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: root.previewOpen ? parent.width * 0.55 : parent.width
              keys: ["text/uri-list"]
              onEntered: function (drag) { if (!drag.hasUrls) drag.accepted = false }
              onDropped: function (drop) {
                root.handleFilesDropped(drop, root.currentPath)
              }
            }

            // Rueda del ratón: con `list.interactive` a false (para que
            // arrastrar nunca haga scroll, solo dibuje el lazo), Flickable
            // deja de procesar también la rueda -- se reimplementa aquí a
            // mano. Sin onPressed/onClicked, así que un MouseArea sin
            // control de wheel (ninguno de filas/footer/marqueeArea lo
            // implementa) deja pasar el evento hasta este, detrás de todo;
            // por eso uno solo, cubriendo toda la zona, basta para filas y
            // huecos vacíos por igual.
            MouseArea {
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: root.previewOpen ? parent.width * 0.55 : parent.width
              property real wheelAccumulator: 0
              onWheel: function (wheel) {
                var step = Util.wheelSteps(wheelAccumulator, wheel.angleDelta.y)
                wheelAccumulator = step.remainder
                if (step.steps === 0) return
                // El suelo es list.originY, NO 0 -- ListView puede desplazar
                // su origen con el reciclado de delegados (visto en vivo:
                // originY llegó a valer cientos de píxeles tras scrollear
                // mucho), y forzar contentY a 0 en ese caso deja justo el
                // hueco vacío arriba del todo que reportaba el usuario.
                var minY = list.originY
                var maxY = minY + Math.max(0, list.contentHeight - list.height)
                list.contentY = Math.max(minY, Math.min(maxY, list.contentY - step.steps * 60))
              }
            }

            // Detrás de la ListView, solo el hueco de arriba (fuera de sus
            // bounds, por el topMargin de `list` -- lo de abajo lo cubre el
            // footer, dentro de la propia ListView, ver más abajo). Pulsar y
            // arrastrar aquí dibuja un lazo de selección (como Nautilus/
            // cualquier gestor de iconos) -- Ctrl mantenido pulsado suma a
            // la selección previa en vez de reemplazarla.
            MouseArea {
              id: marqueeArea
              anchors.top: parent.top
              height: list.y
              anchors.left: parent.left
              width: root.previewOpen ? parent.width * 0.55 : parent.width
              acceptedButtons: Qt.LeftButton
              onPressed: function (mouse) {
                var p = mapToItem(list.contentItem, mouse.x, mouse.y)
                var vp = mapToItem(list, mouse.x, mouse.y)
                root.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
              }
              onPositionChanged: function (mouse) {
                var p = mapToItem(list.contentItem, mouse.x, mouse.y)
                var vp = mapToItem(list, mouse.x, mouse.y)
                root.moveMarquee(p.x, p.y, vp.y)
              }
              onReleased: root.endMarquee()
              onCanceled: root.endMarquee()
            }

            ListView {
              id: list
              anchors.top: listSep.bottom
              // Hueco reservado encima de la primera fila -- sin esto no hay
              // ningún píxel "vacío" por encima donde arrancar el lazo, la
              // fila 0 empezaría justo en el borde. Solo desplaza la
              // ListView, marqueeArea/DropArea de detrás siguen llegando
              // hasta el borde real, así que ese hueco cae en ellos. Subido
              // de sm a md (josema: poco aire entre la cabecera y la
              // lista) -- mismo valor en bgList para que las dos alturas
              // seguán coincidiendo exactas (ver el bug del -1px anterior).
              anchors.topMargin: Style.spacing.md
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: root.previewOpen ? parent.width * 0.55 : parent.width
              clip: true
              model: root.visibleEntries
              focus: root.opened
              // Sin esto, arrastrar con el click (botón izquierdo pulsado)
              // hace scroll de la lista -- el mismo gesto que queremos
              // libre por completo para el lazo de selección. Solo debe
              // poder hacer scroll la rueda, nunca el arrastre. Como
              // Flickable ata la rueda a esta misma propiedad, hay que
              // reimplementarla a mano (ver wheelArea más abajo).
              interactive: false
              // Sin esto (default DragAndOvershootBounds), cualquier cambio
              // en contentHeight mientras contentY está en el borde (el
              // footer se recalcula constantemente a partir de
              // measuredRowHeight) dispara una animación de rebote propia de
              // Flickable que puede pasar a negativo antes de asentarse. Si
              // el siguiente evento de rueda llega a mitad de esa animación,
              // el contentY que se lee ya no es el real y el rebote se
              // reinicia sobre un punto erróneo -- eso es lo que hacía crecer
              // el hueco de arriba en cada ciclo de scroll. Con esto, el
              // límite es duro e inmediato, sin animación que interrumpir.
              boundsBehavior: Flickable.StopAtBounds

              // Hueco de abajo para el lazo. Un MouseArea suelto detrás de
              // la ListView (como el de arriba) NO sirve aquí: al ser
              // Flickable, ListView se queda con cualquier press+arrastre en
              // TODO su rectángulo -- incluido el hueco bajo la última fila,
              // aunque ahí no haya ningún delegado -- antes de que le llegue
              // a nada por detrás (y si se desactiva `interactive` para
              // evitarlo, se pierde también el scroll con la rueda, que
              // depende de la misma propiedad). La solución real es un
              // footer: al ser contenido propio de la ListView (como las
              // filas), gana el press igual que ellas.
              footer: Item {
                id: listFooter
                width: list.width
                // Altura FIJA a propósito -- nada que dependa de
                // measuredRowHeight/contentHeight/visibleEntries.length, ni
                // de ninguna otra propiedad que cambie durante el scroll. El
                // footer es contenido propio de la ListView (participa en su
                // recolocación/reciclado de delegados); atarlo a algo que se
                // recalcula mientras se hace scroll es lo que dejaba
                // `list.originY` desincronizado de 0 -- confirmado con un
                // lector de depuración (originY llegó a valer 210 tras
                // scrollear arriba/abajo varias veces), y eso es exactamente
                // el hueco que aparecía arriba del todo. Con un número fijo
                // el footer nunca se recalcula, así que no hay nada que
                // pueda perturbar el origen.
                height: 400

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  onPressed: function (mouse) {
                    var p = mapToItem(list.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(list, mouse.x, mouse.y)
                    root.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
                  }
                  onPositionChanged: function (mouse) {
                    var p = mapToItem(list.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(list, mouse.x, mouse.y)
                    root.moveMarquee(p.x, p.y, vp.y)
                  }
                  onReleased: root.endMarquee()
                  onCanceled: root.endMarquee()
                }
              }

              // Auto-scroll del lazo: si el cursor se queda pegado a un
              // borde de la lista mientras se arrastra y hay más filas de
              // las que caben en el viewport, hace scroll solo para poder
              // seguir seleccionando más allá de lo visible -- como
              // Nautilus/cualquier gestor con lazo. marqueeViewportY llega
              // ya actualizado (vía mapToItem(list, ...)) desde cualquier
              // catcher del lazo, así que esto no depende de dónde arrancó
              // el arrastre.
              Timer {
                interval: 16
                repeat: true
                running: root.marqueeActive && list.contentHeight > list.height
                  && (root.marqueeViewportY < 32 || root.marqueeViewportY > list.height - 32)
                onTriggered: {
                  var minY = list.originY
                  var maxY = minY + Math.max(0, list.contentHeight - list.height)
                  var step = 18
                  if (root.marqueeViewportY < 32) {
                    list.contentY = Math.max(minY, list.contentY - step)
                    root.marqueeCurrentY = list.contentY
                  } else {
                    list.contentY = Math.min(maxY, list.contentY + step)
                    root.marqueeCurrentY = list.contentY + list.height
                  }
                  root.updateMarqueeSelection(root.marqueeAdditive, root.marqueeBaseSelection)
                }
              }

              Keys.onPressed: function (event) {
                if (root.paletteOpen) return
                if (root.openWithOpen) {
                  if (event.key === Qt.Key_Escape) { root.openWithOpen = false; event.accepted = true }
                  return
                }
                if (root.chmodOpen) {
                  if (event.key === Qt.Key_Escape) { root.chmodOpen = false; event.accepted = true }
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitChmod(root.chmodMode); event.accepted = true }
                  return
                }
                if (root.contextMenuOpen) {
                  if (event.key === Qt.Key_Escape) { root.contextMenuOpen = false; event.accepted = true }
                  return
                }
                if (root.pendingDeleteNames.length > 0) {
                  if (deleteConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.renameConflictOpen) {
                  if (renameConflictConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.extractConflictOpen) {
                  if (extractConflictConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.compressConflictOpen) {
                  if (compressConflictConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.bulkRenameConflictOpen) {
                  if (bulkRenameConflictConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.pasteConflictOpen) {
                  if (event.key === Qt.Key_Escape) { root.cancelPasteConflict(); event.accepted = true }
                  return
                }
                if (root.dropConflictOpen) {
                  if (event.key === Qt.Key_Escape) { root.cancelDropConflict(); event.accepted = true }
                  return
                }
                if (root.propertiesOpen) {
                  if (event.key === Qt.Key_Escape) { root.propertiesOpen = false; event.accepted = true }
                  return
                }
                if (root.shortcutsHelpOpen) {
                  if (event.key === Qt.Key_Escape || event.key === Qt.Key_Question) { root.shortcutsHelpOpen = false; event.accepted = true }
                  return
                }
                // Red de seguridad -- bulkRenameField normalmente tiene el
                // foco y gestiona Escape/Enter él solo, pero si alguna vez
                // no lo tiene, esto evita que j/k/Supr caigan en la lista de
                // detrás con el diálogo todavía abierto encima.
                if (root.bulkRenameOpen) {
                  if (event.key === Qt.Key_Escape) { root.bulkRenameOpen = false; event.accepted = true }
                  return
                }
                // Misma red de seguridad que bulkRenameOpen -- connectServerField
                // gestiona Escape/Enter él solo mientras tiene el foco.
                if (root.connectServerOpen) {
                  if (event.key === Qt.Key_Escape) {
                    if (root.networkConnecting) root.cancelNetworkConnect()
                    else root.cancelConnectToServer()
                    event.accepted = true
                  }
                  return
                }
                if (root.creatingFolder || root.creatingFile || root.renamingIndex >= 0 || root.editingPath || root.searching) return

                var extend = (event.modifiers & Qt.ShiftModifier) !== 0

                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) {
                  root.openTerminalHere()
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  // Con 2+ pestañas, Escape cierra el panel activo (el que
                  // tiene el cursor encima, gracias al HoverHandler de cada
                  // panel) en vez de la ventana entera -- sustituye a la ×
                  // que había antes en cada cabecera. closeTab() ya cae en
                  // requestClose() si solo queda 1, así que el comportamiento
                  // de siempre (Escape cierra la ventana) no cambia con una
                  // sola pestaña abierta.
                  if (root.previewOpen) root.previewOpen = false
                  else root.closeTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_Backspace || (event.key === Qt.Key_H && event.modifiers === Qt.NoModifier)) {
                  root.goUp()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (event.key === Qt.Key_L && event.modifiers === Qt.NoModifier)) {
                  if (root.selectedIndex >= 0) root.enter(root.visibleEntries[root.selectedIndex])
                  event.accepted = true
                } else if (event.key === Qt.Key_Space) {
                  root.togglePreview()
                  event.accepted = true
                } else if (event.key === Qt.Key_Slash) {
                  root.startSearch()
                  event.accepted = true
                } else if (event.key === Qt.Key_Colon || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
                  root.openPalette()
                  event.accepted = true
                } else if (event.key === Qt.Key_Question) {
                  root.shortcutsHelpOpen = true
                  event.accepted = true
                } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                  root.goBottom()
                  event.accepted = true
                } else if (event.key === Qt.Key_G && event.modifiers === Qt.NoModifier) {
                  if (root.gPending) { root.goTop(); root.gPending = false }
                  else { root.gPending = true; gTimer.restart() }
                  event.accepted = true
                } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers === Qt.NoModifier)) {
                  var down = Math.min(root.visibleEntries.length - 1, root.selectedIndex + 1)
                  if (extend) root.selectRange(down); else root.selectOnly(down)
                  event.accepted = true
                } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers === Qt.NoModifier)) {
                  var up = Math.max(0, root.selectedIndex - 1)
                  if (extend) root.selectRange(up); else root.selectOnly(up)
                  event.accepted = true
                } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
                  root.selectNone()
                  event.accepted = true
                } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                  root.selectedIndices = Array.from({ length: root.visibleEntries.length }, function (_, i) { return i })
                  event.accepted = true
                } else if (event.key === Qt.Key_I && (event.modifiers & Qt.ControlModifier)) {
                  root.invertSelection()
                  event.accepted = true
                } else if (event.key === Qt.Key_F2) {
                  root.startRename(root.selectedIndex)
                  event.accepted = true
                } else if (event.key === Qt.Key_Delete) {
                  root.requestDelete()
                  event.accepted = true
                } else if (event.key === Qt.Key_F5) {
                  root.refresh()
                  event.accepted = true
                } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ShiftModifier)) {
                  root.reverseSort()
                  event.accepted = true
                } else if (event.key === Qt.Key_S && event.modifiers === Qt.NoModifier) {
                  root.cycleSort()
                  event.accepted = true
                } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                  root.startEditPath()
                  event.accepted = true
                } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
                  root.startNewFolder()
                  event.accepted = true
                } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
                  // "New file" no tenía atajo propio, a diferencia de
                  // "New folder" (Ctrl+Shift+N, arriba) -- solo estaba en
                  // paleta/menú contextual.
                  root.startNewFile()
                  event.accepted = true
                } else if (event.key === Qt.Key_Backslash && (event.modifiers & Qt.ControlModifier)) {
                  // Antes alternaba la vista dividida; ahora cada pestaña ES
                  // ya un panel visible, así que este atajo simplemente abre
                  // uno nuevo (igual que Ctrl+T).
                  root.newTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) {
                  root.navBack()
                  event.accepted = true
                } else if (event.key === Qt.Key_Right && (event.modifiers & Qt.AltModifier)) {
                  root.navForward()
                  event.accepted = true
                } else if (event.key === Qt.Key_T && (event.modifiers & Qt.ControlModifier)) {
                  root.newTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
                  root.closeTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
                  root.nextTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_H && (event.modifiers & Qt.ControlModifier)) {
                  root.toggleHidden()
                  event.accepted = true
                } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                  root.copySelected()
                  event.accepted = true
                } else if (event.key === Qt.Key_X && (event.modifiers & Qt.ControlModifier)) {
                  root.cutSelected()
                  event.accepted = true
                } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                  root.paste()
                  event.accepted = true
                } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
                  root.redoLast()
                  event.accepted = true
                } else if (event.key === Qt.Key_Y && (event.modifiers & Qt.ControlModifier)) {
                  root.redoLast()
                  event.accepted = true
                } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
                  root.undoLast()
                  event.accepted = true
                }
              }

              delegate: CursorSurface {
                id: rowSurface
                required property var modelData
                required property int index
                width: list.width
                implicitHeight: rowContent.implicitHeight + Style.spacing.md * 2
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name + (modelData.type === "dir" ? ", folder" : ", file")
                Accessible.selected: root.isSelected(index)
                // Al reciclar delegados (recrea filas al hacer scroll),
                // implicitHeight puede pasar por 0 durante un frame antes de
                // que el layout del texto se asiente -- si se acepta ese
                // valor de paso, measuredRowHeight (compartido por todas las
                // filas) queda mal un instante, el footer recalcula su
                // altura, contentHeight cambia en pleno scroll y eso es justo
                // lo que hacía crecer el hueco de arriba en cada ciclo. Todas
                // las filas miden lo mismo, así que quedarse con el máximo
                // visto es seguro y nunca acepta un valor transitorio menor.
                onHeightChanged: {
                  if (height > root.measuredRowHeight) root.measuredRowHeight = height
                }
                foreground: Color.menu.text
                accent: Color.accent
                hasCursor: mouseArea.containsMouse
                current: root.isSelected(index) || root.dropHoverIndex === index

                DropArea {
                  // Solo las carpetas son destino válido de un drop --
                  // soltar sobre un fichero suelto no tiene sentido.
                  anchors.fill: parent
                  enabled: modelData.type === "dir"
                  keys: ["text/uri-list"]
                  onEntered: function (drag) {
                    if (!drag.hasUrls) { drag.accepted = false; return }
                    root.dropHoverIndex = index
                  }
                  onExited: if (root.dropHoverIndex === index) root.dropHoverIndex = -1
                  onDropped: function (drop) {
                    root.dropHoverIndex = -1
                    root.handleFilesDropped(drop, root.joinPath(root.currentPath, modelData.name))
                  }
                }

                Item {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: 0
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  implicitHeight: activeFileRow.implicitHeight

                  readonly property bool isVid: root.isVideo(modelData)
                  readonly property string vidKey: isVid ? Utils.thumbKeyFor(modelData, root.currentPath) : ""
                  readonly property string vidThumb: vidKey ? (root.videoThumbReady[vidKey] || "") : ""

                  Component.onCompleted: if (isVid) root.requestVideoThumb(modelData)

                  FileRowVisual {
                    id: activeFileRow
                    anchors.fill: parent
                    name: modelData.name
                    isDir: modelData.type === "dir"
                    isBroken: modelData.link === "broken"
                    highlighted: rowSurface.current
                    dimmed: root.clipboardMode === "cut" && root.clipboardPaths.indexOf(root.joinPath(root.currentPath, modelData.name)) >= 0
                    fileIconGlyph: root.iconFor(modelData)
                    thumbSource: root.isImage(modelData) ? Util.fileUrl(root.joinPath(root.currentPath, modelData.name))
                      : (parent.vidThumb ? Util.fileUrl(parent.vidThumb) : "")
                    metaText: root.metaFor(modelData)
                    showNameText: root.renamingIndex !== index
                  }

                  TextField {
                    id: renameField
                    visible: root.renamingIndex === index
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Rename"
                    // Misma X que nameCol dentro de FileRowVisual
                    // (thumbSlot.right + rowGap) -- ese id ya no es
                    // visible desde aquí, así que se repite con la
                    // misma constante conocida (Style.spacing.controlHeight,
                    // el ancho fijo del icono) en vez de perseguir el id.
                    anchors.left: parent.left
                    anchors.leftMargin: Style.spacing.controlHeight + Style.spacing.rowGap
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    verticalPadding: 2
                    onVisibleChanged: if (visible) { text = modelData.name; forceActiveFocus(); selectAll() } else list.forceActiveFocus()
                    Keys.onPressed: function (event) {
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.commitRename(text)
                        event.accepted = true
                      } else if (event.key === Qt.Key_Escape) {
                        root.renamingIndex = -1
                        event.accepted = true
                      }
                    }
                  }
                }

                MouseArea {
                  id: mouseArea
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.left: parent.left
                  // Huecos sin cubrir a los dos lados (el contenido visual --
                  // icono, texto -- no se mueve, solo se reduce el área
                  // interactiva) para que los MouseArea de gutter de abajo
                  // puedan quedarse con el press ahí en vez de competir por
                  // hover con este. Izquierda subida de 14 a 24 -- josema
                  // probándolo en vivo dijo que sobraba distancia sin usar
                  // entre el icono y la barra separadora. Derecha iguala
                  // rowContent.anchors.rightMargin (rowPaddingX), que ya
                  // deja ese hueco sin contenido visual.
                  anchors.leftMargin: 24
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  hoverEnabled: true
                  visible: root.renamingIndex !== index
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  drag.target: dragProxy
                  drag.axis: Drag.XAndYAxis
                  onPressed: function (mouse) {
                    // Empezar a arrastrar un fichero que no formaba parte de
                    // la selección debe arrastrar solo ese fichero (como
                    // Nautilus) -- pero solo en clic simple: Ctrl/Shift+clic
                    // siguen decidiendo la selección en onClicked, sin tocar
                    // aquí el ancla de rango (selectRange).
                    if (mouse.button === Qt.LeftButton && mouse.modifiers === Qt.NoModifier && !root.isSelected(index)) {
                      root.selectOnly(index)
                    }
                    // Miniatura del arrastre: capturada aquí (no en
                    // Drag.onActiveChanged) para que le dé tiempo a
                    // completarse -- grabToImage es async (un frame) y para
                    // cuando el movimiento supera el umbral de drag ya casi
                    // siempre está lista.
                    if (mouse.button === Qt.LeftButton) {
                      rowContent.grabToImage(function (result) { dragProxy.Drag.imageSource = result.url })
                    }
                  }
                  onClicked: function (mouse) {
                    if (mouse.button === Qt.RightButton) {
                      if (!root.isSelected(index)) root.selectOnly(index)
                      var pos = mapToItem(card, mouse.x, mouse.y)
                      root.openContextMenu(pos.x, pos.y, root.itemActions())
                      return
                    }
                    if (mouse.modifiers & Qt.ControlModifier) root.toggleSelect(index)
                    else if (mouse.modifiers & Qt.ShiftModifier) root.selectRange(index)
                    else root.selectOnly(index)
                  }
                  // hasPendingEdit: no entrar (y sobre todo no entrar en
                  // un archivo comprimido) mientras hay un renombrado/
                  // nueva-carpeta/nuevo-fichero sin confirmar en esta
                  // misma fila u otra -- ver commitRename() para el bug
                  // real que esto evita.
                  onDoubleClicked: if (!root.hasPendingEdit) root.enter(modelData)
                }

                // Proxy invisible que MouseArea.drag mueve -- lo único que
                // importa de verdad es su Drag.active, que arranca el drag
                // real (interno o hacia otra app) en cuanto se supera el
                // umbral de movimiento.
                Item {
                  id: dragProxy
                  width: 1
                  height: 1
                  Drag.active: mouseArea.drag.active
                  Drag.dragType: Drag.Automatic
                  Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                  Drag.proposedAction: Qt.MoveAction
                  Drag.mimeData: root.dragMimeDataFor(index)
                }

                // Gutters del lazo a los dos lados de la fila -- implementan
                // el arranque/arrastre directamente (no confían en que el
                // press "caiga" a algo detrás: en la franja izquierda, antes
                // de este cambio, no había nada detrás salvo el MouseArea de
                // la rueda, que se queda con cualquier click de todos modos
                // aunque solo tenga onWheel). anchors.leftMargin de
                // `mouseArea` (24) y anchors.rightMargin de `rowContent`
                // (Style.spacing.rowPaddingX) dejan estos huecos libres de
                // contenido visual, así que no roban nada al icono/texto.
                MouseArea {
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.left: parent.left
                  width: 24
                  acceptedButtons: Qt.LeftButton
                  onPressed: function (mouse) {
                    var p = mapToItem(list.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(list, mouse.x, mouse.y)
                    root.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
                  }
                  onPositionChanged: function (mouse) {
                    var p = mapToItem(list.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(list, mouse.x, mouse.y)
                    root.moveMarquee(p.x, p.y, vp.y)
                  }
                  onReleased: root.endMarquee()
                  onCanceled: root.endMarquee()
                }

                MouseArea {
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  width: Style.spacing.rowPaddingX
                  acceptedButtons: Qt.LeftButton
                  onPressed: function (mouse) {
                    var p = mapToItem(list.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(list, mouse.x, mouse.y)
                    root.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
                  }
                  onPositionChanged: function (mouse) {
                    var p = mapToItem(list.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(list, mouse.x, mouse.y)
                    root.moveMarquee(p.x, p.y, vp.y)
                  }
                  onReleased: root.endMarquee()
                  onCanceled: root.endMarquee()
                }
              }
            }

            // Aviso cuando list-dir.sh no ha podido listar currentPath --
            // antes esto se veía igual que una carpeta vacía de verdad, sin
            // ningún indicio de que el problema era de permisos.
            Text {
              visible: root.currentPathError !== ""
              anchors.top: parent.top
              anchors.topMargin: Style.spacing.lg
              anchors.left: parent.left
              text: root.currentPathError
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              color: Color.urgent
            }

            EmptyState {
              visible: root.currentPathError === "" && root.visibleEntries.length === 0
              centerOn: list
              message: root.searchQuery
                ? "No results for “" + root.searchQuery + "”"
                : (root.currentPath === root.trashDir ? "Trash is empty" : "Nothing here yet")
            }

            // Rectángulo visual del lazo -- después de la ListView en el
            // fichero para quedar por encima al pintar (visible incluso
            // cuando el lazo crece sobre filas ya dibujadas).
            Rectangle {
              visible: root.marqueeActive
              x: Math.min(root.marqueeStartX, root.marqueeCurrentX)
              y: Math.min(root.marqueeStartY, root.marqueeCurrentY) - list.contentY + list.y
              width: Math.abs(root.marqueeCurrentX - root.marqueeStartX)
              height: Math.abs(root.marqueeCurrentY - root.marqueeStartY)
              color: Util.alpha(Color.accent, 0.12)
              border.color: Color.accent
              border.width: 1
              z: 5
            }

            // ---------- Vista previa (Espacio) ----------
            PreviewPanel {
              anchors.fill: parent
              open: root.previewOpen
              entryName: root.previewEntry ? root.previewEntry.name : ""
              hasEntry: !!root.previewEntry
              isImageEntry: root.previewEntry ? root.isImage(root.previewEntry) : false
              isVideoEntry: root.previewEntry ? root.isVideo(root.previewEntry) : false
              isTextEntry: !!root.previewEntry && !root.isImage(root.previewEntry) && root.previewIsText
              isPdfEntry: root.previewEntry ? root.isPdf(root.previewEntry) : false
              isAudioEntry: root.previewEntry ? root.isAudio(root.previewEntry) : false
              imageSource: (root.previewEntry && root.isImage(root.previewEntry))
                ? Util.fileUrl(root.joinPath(root.currentPath, root.previewEntry.name)) : ""
              videoThumbSource: {
                if (!root.previewEntry || !root.isVideo(root.previewEntry)) return ""
                var p = root.videoThumbReady[Utils.thumbKeyFor(root.previewEntry, root.currentPath)] || ""
                return p ? Util.fileUrl(p) : ""
              }
              highlightedText: root.previewHighlighted
              plainText: root.previewText
              pdfImageSource: root.previewPdfImage ? Util.fileUrl(root.previewPdfImage) : ""
              audioInfo: root.previewAudioInfo
              fallbackSizeText: root.previewEntry ? Utils.formatSize(root.previewEntry.size) : ""
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
                  + (root.selectedIndices.length > 1 ? " · " + root.selectedIndices.length + " selected" : "")
                  + (root.clipboardPaths.length > 0 ? " · clipboard: " + root.clipboardPaths.length + (root.clipboardPaths.length === 1 ? " item" : " items") + (root.clipboardMode === "cut" ? " (cut)" : " (copied)") : "")
                  + " · sort: " + root.sortLabel()
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
          root.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
        }
        onPositionChanged: function (mouse) {
          var p = mapToItem(list.contentItem, mouse.x, mouse.y)
          var vp = mapToItem(list, mouse.x, mouse.y)
          root.moveMarquee(p.x, p.y, vp.y)
        }
        onReleased: root.endMarquee()
        onCanceled: root.endMarquee()
      }

      // ---------- Renombrar en lote ----------
      BulkRenamePanel {
        anchors.fill: parent
        open: root.bulkRenameOpen
        selectedCount: root.selectedIndices.length
        pattern: root.bulkRenamePattern
        history: root.bulkRenameHistory
        onCloseRequested: root.bulkRenameOpen = false
        onRenameRequested: function (pattern) { root.bulkRenamePattern = pattern; root.commitBulkRename() }
        onFocusReturnRequested: list.forceActiveFocus()
      }

      // ---------- Conectar a servidor ----------
      ConnectServer {
        anchors.fill: parent
        open: root.connectServerOpen
        connecting: root.networkConnecting
        uri: root.connectServerUri
        errorText: root.connectServerError
        onConnectRequested: function (uri) { root.connectServerUri = uri; root.commitConnectToServer() }
        onCancelConnectingRequested: root.cancelNetworkConnect()
        onCloseRequested: root.cancelConnectToServer()
        onFocusReturnRequested: list.forceActiveFocus()
      }

      // ---------- Permisos (chmod) ----------
      ChmodPanel {
        anchors.fill: parent
        open: root.chmodOpen
        names: root.chmodNames
        mixed: root.chmodMixed
        mode: root.chmodMode
        hasDir: root.chmodHasDir
        recursive: root.chmodRecursive
        onCloseRequested: root.chmodOpen = false
        onBitToggled: function (ownerIdx, bit) { root.toggleChmodBit(ownerIdx, bit) }
        onRecursiveToggled: root.chmodRecursive = !root.chmodRecursive
        onApplyRequested: function (mode) { root.commitChmod(mode) }
      }

      // ---------- Propiedades ----------
      PropertiesPanel {
        anchors.fill: parent
        open: root.propertiesOpen
        multi: root.propertiesMulti
        count: root.propertiesCount
        entry: root.propertiesEntry
        sizeLoading: root.propertiesSizeLoading
        size: root.propertiesSize
        perms: root.propertiesPerms
        owner: root.propertiesOwner
        mtime: root.propertiesMtime
        onCloseRequested: root.propertiesOpen = false
      }

      // ---------- Ayuda de atajos de teclado ----------
      // Primer componente extraído a su propio fichero (ShortcutsHelp.qml)
      // -- ver comentario ahí sobre por qué se eligió este trozo primero.
      ShortcutsHelp {
        anchors.fill: parent
        open: root.shortcutsHelpOpen
        onRequestClose: root.shortcutsHelpOpen = false
      }

      // ---------- Copiar/mover en curso ----------
      // No bloquea el resto de la ventana (sin MouseArea de fondo a pantalla
      // completa) -- cp/mv no reportan progreso real, así que esto es solo
      // "sigue vivo" (puntos animados) + Cancel, no una barra de porcentaje.
      BorderSurface {
        id: actionBusyCard
        visible: root.actionBusy
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
              text: root.actionLabel + (root.actionProgressPct >= 0 ? " " + Math.round(root.actionProgressPct) + "%" : root.actionBusyDots)
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
            visible: root.actionProgressPct >= 0
            width: parent.width
            height: 3
            radius: height / 2
            color: Qt.darker(Color.menu.text, 2.5)

            Rectangle {
              width: parent.width * (root.actionProgressPct / 100)
              height: parent.height
              radius: height / 2
              color: Color.accent

              Behavior on width { NumberAnimation { duration: 200 } }
            }
          }
        }
      }

      Timer {
        running: root.actionBusy
        repeat: true
        interval: 400
        onTriggered: root.actionBusyDots = root.actionBusyDots.length >= 3 ? "" : root.actionBusyDots + "."
      }

      // ---------- Abrir con... ----------
      OpenWithPanel {
        anchors.fill: parent
        open: root.openWithOpen
        entry: root.openWithEntry
        apps: root.openWithApps
        onCloseRequested: root.openWithOpen = false
        onAppSelected: function (appId) { root.launchWith(appId) }
      }

      // ---------- Menú contextual ----------
      ContextMenuPanel {
        anchors.fill: parent
        open: root.contextMenuOpen
        menuX: root.contextMenuX
        menuY: root.contextMenuY
        actions: root.contextMenuActions
        onCloseRequested: root.contextMenuOpen = false
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
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: root.pendingDeleteNames = []
        onConfirmed: root.confirmDelete()
      }

      ConfirmDialog {
        id: renameConflictConfirm
        anchors.fill: parent
        z: 10
        opened: root.renameConflictOpen
        message: root.pendingRename
          ? "\"" + root.pendingRename.newPath.substring(root.pendingRename.newPath.lastIndexOf("/") + 1) + "\" already exists here. Overwrite?"
          : ""
        confirmText: "Overwrite"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: root.cancelPendingRename()
        onConfirmed: root.runPendingRename(true)
      }

      ConfirmDialog {
        id: extractConflictConfirm
        anchors.fill: parent
        z: 10
        opened: root.extractConflictOpen
        message: root.extractConflictNames.length === 1
          ? "\"" + root.extractConflictNames[0] + "\" already exists here and will be overwritten."
          : root.extractConflictNames.length + " items already exist here and will be overwritten."
        confirmText: "Overwrite"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: root.cancelPendingExtract()
        onConfirmed: root.runPendingExtract()
      }

      ConfirmDialog {
        id: compressConflictConfirm
        anchors.fill: parent
        z: 10
        opened: root.compressConflictOpen
        message: root.pendingCompress ? "\"" + root.pendingCompress.archiveName + "\" already exists. Overwrite it?" : ""
        confirmText: "Overwrite"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: root.cancelPendingCompress()
        onConfirmed: root.runPendingCompress()
      }

      ConfirmDialog {
        id: bulkRenameConflictConfirm
        anchors.fill: parent
        z: 10
        opened: root.bulkRenameConflictOpen
        message: root.bulkRenameConflictCount === 1
          ? "1 rename would collide with an existing name and will be skipped. Rename the rest?"
          : root.bulkRenameConflictCount + " renames would collide with existing or duplicate names and will be skipped. Rename the rest?"
        confirmText: "Continue"
        background: Color.menu.background
        foreground: Color.menu.text
        onCanceled: root.cancelPendingBulkRename()
        onConfirmed: root.runPendingBulkRename()
      }

      // ---------- Conflicto al pegar ----------
      ConflictResolveDialog {
        anchors.fill: parent
        open: root.pasteConflictOpen
        names: root.pasteConflictNames
        onOverwriteRequested: root.runPaste("overwrite")
        onSkipRequested: root.runPaste("skip")
        onCancelRequested: root.cancelPasteConflict()
      }

      // ---------- Conflicto al soltar (drag & drop) ----------
      ConflictResolveDialog {
        anchors.fill: parent
        open: root.dropConflictOpen
        names: root.dropConflictNames
        onOverwriteRequested: root.runDrop("overwrite")
        onSkipRequested: root.runDrop("skip")
        onCancelRequested: root.cancelDropConflict()
      }

      // ---------- Paleta de comandos (: o Ctrl+P) ----------
      CommandPalettePanel {
        anchors.fill: parent
        open: root.paletteOpen
        query: root.paletteQuery
        index: root.paletteIndex
        commands: root.paletteOpen ? root.filteredPaletteCommands() : []
        onQueryEdited: function (text) { root.paletteQuery = text; root.paletteIndex = 0 }
        onCloseRequested: root.closePalette()
        onIndexRequested: function (idx) { root.paletteIndex = idx }
        onCommandActivated: function (idx) { root.runPaletteCommand(idx) }
        onFocusReturnRequested: list.forceActiveFocus()
      }
    }
  }
}

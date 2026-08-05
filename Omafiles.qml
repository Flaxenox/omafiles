import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "dialogs"
import "panels"
import "logic"
import "shared"
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
  // { "<nombre>": "<modo octal previo>" }, capturado por PropertiesLoader al
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
  // siempre con previewText. Ver PreviewLoader.loadPreview().
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

  // ---------- Tipo de fichero (extensión/icono) ----------
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

  // ---------- Selección (individual + lazo) ----------
  function isSelected(index) {
    return root.selectedIndices.indexOf(index) >= 0
  }

  function selectOnly(index) {
    root.selectedIndex = index
    root.anchorIndex = index
    root.selectedIndices = index >= 0 ? [index] : []
    if (root.previewOpen) {
      if (index >= 0 && index < root.visibleEntries.length && root.visibleEntries[index].type !== "dir") {
        previewLoader.loadPreview(root.visibleEntries[index])
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

  // ---------- Refresco / vigilancia de directorio ----------
  function refresh() {
    // Centralizado aquí para que TODO lo que ya llama a refresh() (toggle
    // de ocultos, el "Refresh" de la paleta, el onExited de las acciones
    // de fichero...) recargue lo correcto sin tener que acordarse de
    // comprobar inArchive en cada sitio.
    if (root.inArchive) { archiveActions.refreshArchiveListing(); return }
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
      root.selectedIndex = foundIndices[0]
      root.anchorIndex = foundIndices[0]
      root.selectedIndices = foundIndices
      if (root.previewOpen && foundIndices.length > 1) root.previewOpen = false
    } else if (root.selectedIndex >= root.visibleEntries.length) {
      root.selectedIndex = root.visibleEntries.length - 1
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


  // ---------- Recientes / historial ----------
  // Llamado al abrir un fichero de verdad (enter()/launchWith(), NO al
  // navegar por carpetas -- para eso ya están el historial y las
  // pestañas). Mueve al principio si ya estaba, tope 20 entradas.
  function addRecent(path, name) {
    var next = root.recentFiles.filter(function (r) { return r.path !== path })
    next.unshift({ path: path, name: name })
    if (next.length > 20) next = next.slice(0, 20)
    root.recentFiles = next
    persistence.saveRecent()
  }

  function removeRecent(path) {
    root.recentFiles = root.recentFiles.filter(function (r) { return r.path !== path })
    persistence.saveRecent()
  }

  function clearRecent() {
    root.recentFiles = []
    persistence.saveRecent()
  }

  function addBulkRenameHistory(pattern) {
    pattern = pattern.trim()
    if (!pattern) return
    var next = root.bulkRenameHistory.filter(function (p) { return p !== pattern })
    next.unshift(pattern)
    if (next.length > 8) next = next.slice(0, 8)
    root.bulkRenameHistory = next
    persistence.saveBulkRenameHistory()
  }

  // ---------- Marcadores / iconos de unidades ----------
  function removeBookmark(path) {
    root.bookmarks = root.bookmarks.filter(function (b) { return b.path !== path })
    persistence.saveBookmarks()
  }

  // type: "dir" (por defecto, compatible con marcadores guardados antes
  // de que existiera este campo -- todos eran de carpeta) o "file".
  function addBookmark(path, label, type) {
    if (root.bookmarks.some(function (b) { return b.path === path })) return
    root.bookmarks = root.bookmarks.concat([{ label: label, path: path, type: type || "dir" }])
    persistence.saveBookmarks()
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
      { label: "Open in new tab", action: function () { tabOps.openInNewTab(mount.path) } },
      { label: "Disconnect", destructive: true, action: function () { mountOps.disconnectNetworkMount(mount) } }
    ]
  }


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
    if (root.inArchive) {
      if (entry.type === "dir") {
        root.archiveSubPath = root.archiveSubPath ? root.archiveSubPath + "/" + entry.name : entry.name
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
      root.addRecent(openPath, entry.name)
    }
  }


  function goUp() {
    if (root.inArchive) {
      if (root.archiveSubPath === "") { archiveActions.exitArchive(); return }
      var slash = root.archiveSubPath.lastIndexOf("/")
      root.archiveSubPath = slash > 0 ? root.archiveSubPath.substring(0, slash) : ""
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
        persistence.loadSession()
      }
    } else if (targetPath) {
      // Ya estaba cargado antes (uso normal previo): abre en pestaña
      // nueva para no perder la ubicación en la que ya estaba el usuario.
      tabOps.newTab()
      root.navigateTo(targetPath)
      tabOps.saveActiveTab()
    }

    if (!root.bookmarksLoaded) persistence.loadBookmarks()
    if (!root.recentLoaded) persistence.loadRecent()
    if (!root.bulkRenameHistoryLoaded) persistence.loadBulkRenameHistory()
    mountOps.refreshMounts()
    mountOps.refreshNetworkMounts()
    // Cubre los dos casos restantes: primera carga con target (currentPath
    // recién puesto, arriba) y reabrir apuntando a un target (navigateTo ya
    // lo arrancó dentro de _goToPath, esto solo lo reafirma sobre la misma
    // ruta final) o reabrir SIN target (la ventana estaba cerrada -> close()
    // paró el watcher -> sin esto se reabriría mostrando una carpeta sin
    // vigilar). El caso restante (restoringSession) ya lo cubre
    // Persistence.loadSession() por su cuenta.
    if (!restoringSession && !root.inArchive) root.startDirWatch(root.currentPath)
  }

  function close() {
    persistence.saveSession()
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

  // onSuccess (opcional) se llama SOLO si el comando termina con exit 0 --
  // úsalo para todo lo que no deba pasar si la acción en realidad falló
  // (sobre todo pushUndo: un undo registrado para algo que nunca ocurrió en
  // disco es peor que no tener undo). Devuelve true si el comando se lanzó,
  // false si se descartó porque ya había otra acción en marcha (el llamador
  // decide si eso merece avisar al usuario).
  function runAction(cmd, busyLabel, onSuccess) {
    return actionEngine.runAction(cmd, busyLabel, onSuccess)
  }

  // Callback pendiente del runAction en curso -- ver actionProc.onExited.
  property var _actionOnSuccess: null
  // true mientras se procesa un cancelAction() explícito -- así
  // actionProc.onExited no muestra "Action failed" por un proceso que el
  // propio usuario mandó parar (sale con código != 0 por la señal, pero
  // eso no es un fallo real).
  property bool _actionCancelled: false

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
    var hasSelection = root.selectedIndices.length > 0
    var entry = root.selectedIndices.length === 1 ? root.visibleEntries[root.selectedIndex] : null
    var cmds = [
      { label: "New folder", run: function () { renameOps.startNewFolder() } },
      { label: "New file", run: function () { renameOps.startNewFile() } },
      { label: "Rename", enabled: root.selectedIndices.length === 1, run: function () { renameOps.startRename(root.selectedIndex) } },
      { label: "Copy", enabled: hasSelection, run: function () { clipboardOps.copySelected() } },
      { label: "Cut", enabled: hasSelection, run: function () { clipboardOps.cutSelected() } },
      { label: "Copy path", enabled: hasSelection, run: function () { clipboardOps.copyPathFor(root.selectedEntries()) } },
      { label: "Paste", enabled: root.clipboardPaths.length > 0, run: function () { conflictActions.paste() } },
      { label: "Delete", enabled: hasSelection, run: function () { deleteOps.requestDelete() } },
      { label: "Select all", run: function () { root.selectedIndices = Array.from({ length: root.visibleEntries.length }, function (_, i) { return i }) } },
      { label: "Select none", enabled: hasSelection, run: function () { root.selectNone() } },
      { label: "Invert selection", run: function () { root.invertSelection() } },
      { label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", run: function () { searchOps.toggleHidden() } },
      { label: "Refresh", run: function () { root.refresh(); mountOps.refreshMounts(); mountOps.refreshNetworkMounts() } },
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
      { label: "Connect to server...", run: function () { mountOps.startConnectToServer() } },
      { label: "New panel", run: function () { tabOps.newTab() } },
      { label: "Close this panel", enabled: root.tabs.length > 1, run: function () { tabOps.closeTab() } },
      { label: "Back", enabled: root.navHistoryIndex > 0, run: function () { root.navBack() } },
      { label: "Forward", enabled: root.navHistoryIndex < root.navHistory.length - 1, run: function () { root.navForward() } },
      { label: "Edit path", run: function () { searchOps.startEditPath() } },
      { label: "Search", run: function () { searchOps.startSearch() } },
      { label: "Compress to .zip", enabled: hasSelection, run: function () { conflictActions.compressSelected() } },
      { label: "Bulk rename...", enabled: root.selectedIndices.length > 1, run: function () { fileOps.startBulkRename() } },
      { label: "Permissions...", enabled: hasSelection, run: function () { propertiesLoader.startChmod(root.selectedEntries()) } },
      { label: "Make link", enabled: !!entry, run: function () { if (entry) fileOps.makeLinkFor(entry) } },
      { label: "Properties", enabled: hasSelection, run: function () { propertiesLoader.showPropertiesForSelection() } },
      { label: "Keyboard shortcuts", run: function () { root.shortcutsHelpOpen = true } }
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
      if (!root.isBookmarked(fullPath)) {
        cmds.push({ label: "Add to bookmarks", run: function () { root.addBookmark(fullPath, entry.name, entry.type) } })
      }
      if (entry.type === "dir") {
        cmds.push({ label: "Open in new tab", run: function () { tabOps.openInNewTab(fullPath) } })
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
    if (root.clipboardPaths.length > 0) actions.push({ label: "Paste here", action: function () { conflictActions.paste() } })

    if (!multi) {
      actions.push({ label: "Rename", action: function () { renameOps.startRename(root.selectedIndex) } })
      actions.push({ label: "Make link", action: function () { fileOps.makeLinkFor(entries[0]) } })
      var fullPath = root.joinPath(root.currentPath, entries[0].name)
      if (!root.isBookmarked(fullPath)) {
        actions.push({ label: "Add to bookmarks", action: function () { root.addBookmark(fullPath, entries[0].name, entries[0].type) } })
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
    } else if (!root.inArchive) {
      // Dentro de un archivo estas ya son no-op (cada función se
      // protege sola), pero se quitan de aquí para no enseñar entradas
      // muertas en el menú de hueco vacío.
      actions.push({ label: "New folder", action: function () { renameOps.startNewFolder() } })
      actions.push({ label: "New file", action: function () { renameOps.startNewFile() } })
      actions.push({ label: "Paste", enabled: root.clipboardPaths.length > 0, action: function () { conflictActions.paste() } })
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

  function bookmarkActions(bookmark) {
    var actions = [
      { label: "Open", action: function () { root.openBookmark(bookmark) } }
    ]
    if (bookmark.type !== "file") {
      actions.push({ label: "Open in new tab", action: function () { tabOps.openInNewTab(bookmark.path) } })
    }
    if (bookmark.path === root.trashDir) {
      actions.push({ label: "Empty trash", destructive: true, action: function () { root.emptyTrash() } })
    }
    actions.push({ label: "Remove bookmark", destructive: true, action: function () { root.removeBookmark(bookmark.path) } })
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
    if (!root.isBookmarked(mount.path)) {
      actions.push({ label: "Add to bookmarks", action: function () { root.addBookmark(mount.path, mount.label, "dir") } })
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
    onTriggered: { mountOps.refreshMounts(); mountOps.refreshNetworkMounts() }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.sortEntries(Utils.parseEntries(text))
        if (root.currentPath === root.trashDir) {
          if (Object.keys(root.trashInfo).length > 0) {
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
          // NO se limpia root.trashInfo al salir de la papelera -- es
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
  }

  FileOps {
    id: fileOps
    root: root
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
  }

  DragDropOps {
    id: dragDropOps
    root: root
    conflictActions: conflictActions
  }

  SearchOps {
    id: searchOps
    root: root
    list: list
  }

  OpenWithOps {
    id: openWithOps
    root: root
  }

  FileMeta {
    id: fileMeta
    root: root
  }

  DeleteOps {
    id: deleteOps
    root: root
  }

  TabOps {
    id: tabOps
    root: root
    list: list
    archiveActions: archiveActions
    previewLoader: previewLoader
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
    dragDropOps: dragDropOps
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
            if (!mount.mounted) mountOps.mountDevice(mount)
            else root.navigateTo(mount.path)
          }
          onNetworkMountOpened: function (mount) { root.navigateTo(mount.path) }
          onConnectRequested: mountOps.startConnectToServer()
          onFilesDropped: function (drop, destPath) { dragDropOps.handleFilesDropped(drop, destPath) }
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

              BackgroundPanel {
                hostRoot: root
                hostPanelsRow: panelsRow
                hostVideoThumbs: videoThumbs
                hostDragDropOps: dragDropOps
                hostFileMeta: fileMeta
                hostTabOps: tabOps
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
                onClicked: searchOps.startEditPath()
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

          ActivePanelInputRows {
            id: activeInputRows
            root: root
            list: list
            renameOps: renameOps
            searchOps: searchOps
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
              - (root.creatingFolder || root.creatingFile || root.searching ? activeInputRows.height + mainColumn.spacing : 0)
              - statusText.height - mainColumn.spacing * (2 + (root.creatingFolder || root.creatingFile || root.searching ? 1 : 0))

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
              deleteConfirm: deleteConfirm
              renameConflictConfirm: renameConflictConfirm
              extractConflictConfirm: extractConflictConfirm
              compressConflictConfirm: compressConflictConfirm
              bulkRenameConflictConfirm: bulkRenameConflictConfirm
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
        onRenameRequested: function (pattern) { root.bulkRenamePattern = pattern; conflictActions.commitBulkRename() }
        onFocusReturnRequested: list.forceActiveFocus()
      }

      // ---------- Conectar a servidor ----------
      ConnectServer {
        anchors.fill: parent
        open: root.connectServerOpen
        connecting: root.networkConnecting
        uri: root.connectServerUri
        errorText: root.connectServerError
        onConnectRequested: function (uri) { root.connectServerUri = uri; mountOps.commitConnectToServer() }
        onCancelConnectingRequested: mountOps.cancelNetworkConnect()
        onCloseRequested: mountOps.cancelConnectToServer()
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
        onBitToggled: function (ownerIdx, bit) { fileOps.toggleChmodBit(ownerIdx, bit) }
        onRecursiveToggled: root.chmodRecursive = !root.chmodRecursive
        onApplyRequested: function (mode) { fileOps.commitChmod(mode) }
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
        onAppSelected: function (appId) { openWithOps.launchWith(appId) }
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
        onConfirmed: deleteOps.confirmDelete()
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
        onCanceled: renameOps.cancelPendingRename()
        onConfirmed: renameOps.runPendingRename(true)
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
        onCanceled: archiveActions.cancelPendingExtract()
        onConfirmed: archiveActions.runPendingExtract()
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
        onCanceled: archiveActions.cancelPendingCompress()
        onConfirmed: archiveActions.runPendingCompress()
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
        onCanceled: fileOps.cancelPendingBulkRename()
        onConfirmed: fileOps.runPendingBulkRename()
      }

      // ---------- Conflicto al pegar ----------
      ConflictResolveDialog {
        anchors.fill: parent
        open: root.pasteConflictOpen
        names: root.pasteConflictNames
        onOverwriteRequested: clipboardOps.runPaste("overwrite")
        onSkipRequested: clipboardOps.runPaste("skip")
        onCancelRequested: clipboardOps.cancelPasteConflict()
      }

      // ---------- Conflicto al soltar (drag & drop) ----------
      ConflictResolveDialog {
        anchors.fill: parent
        open: root.dropConflictOpen
        names: root.dropConflictNames
        onOverwriteRequested: dragDropOps.runDrop("overwrite")
        onSkipRequested: dragDropOps.runDrop("skip")
        onCancelRequested: dragDropOps.cancelDropConflict()
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

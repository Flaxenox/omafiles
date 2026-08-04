import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

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
  // Nombre de entrada a resaltar en cuanto termine el próximo listado --
  // lo usa open() cuando el payload pide "abre esta carpeta y selecciona
  // este fichero" (caso ShowItems de org.freedesktop.FileManager1).
  property string pendingSelectName: ""

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

  // ---------- Deshacer (Ctrl+Z) ----------
  // Pila simple de acciones reversibles: renombrar, nueva carpeta, borrar
  // (a la papelera) y mover (cortar+pegar). Copiar/comprimir/chmod/renombrado
  // en lote se quedan fuera a propósito -- deshacerlos es más ambiguo o
  // menos crítico que perder por error un fichero renombrado/movido/borrado.
  property var undoStack: []

  function pushUndo(label, undoFn) {
    root.undoStack = root.undoStack.concat([{ label: label, undo: undoFn }]).slice(-20)
  }

  function undoLast() {
    if (root.undoStack.length === 0) return
    var entry = root.undoStack[root.undoStack.length - 1]
    root.undoStack = root.undoStack.slice(0, -1)
    // entry.undo() devuelve lo que runAction() devuelve: false si se
    // descartó por haber otra acción en curso (esa entrada del historial ya
    // se ha perdido igual, al haberla sacado del stack arriba). Antes esto
    // decía "Undone" pase lo que pase, incluso cuando el undo ni siquiera
    // llegó a lanzarse. Ahora solo se anuncia como "en marcha" -- si el
    // comando termina fallando de verdad, actionProc ya avisa por su cuenta
    // (ver runAction/actionProc).
    var started = entry.undo()
    if (started === false) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Couldn't undo \"" + entry.label + "\": still busy with another action"])
      return
    }
    Quickshell.execDetached(["notify-send", "Omafiles", "Undoing: " + entry.label])
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

  // Feedback de "en curso" para copiar/mover -- no hay porcentaje real (cp/mv
  // no lo reportan), pero al menos se ve que algo está pasando en vez de que
  // la ventana parezca congelada con ficheros grandes.
  property bool actionBusy: false
  property string actionLabel: ""
  property string actionBusyDots: ""

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

  // ---------- Miniaturas de vídeo (ffmpegthumbnailer, en cola de 1 a la vez) ----------
  property string thumbCacheDir: root.homeDir + "/.cache/omafiles/thumbnails"
  property var videoThumbReady: ({}) // "ruta|mtime" -> fichero .jpg local
  property var thumbQueue: []
  property bool thumbBusy: false

  // Hash simple y estable solo para nombrar el fichero de caché -- no hace
  // falta criptográfico, solo evitar colisiones razonables sin depender de
  // md5sum externo.
  function simpleHash(str) {
    var h = 0
    for (var i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) | 0
    return (h >>> 0).toString(36)
  }

  // `basePath` es opcional (por defecto root.currentPath, la carpeta del
  // panel activo) -- los paneles de fondo pasan la suya propia
  // (bgPanel.modelData.path), que NO tiene por qué ser la misma. Sin esto,
  // pedir la miniatura de un vídeo desde un panel de fondo generaba el
  // thumbnail a partir de un fichero de la carpeta EQUIVOCADA (la del panel
  // activo en ese momento).
  function thumbKeyFor(entry, basePath) {
    return root.joinPath(basePath || root.currentPath, entry.name) + "|" + entry.mtime
  }

  function videoThumbPath(entry, basePath) {
    return root.thumbCacheDir + "/" + root.simpleHash(root.thumbKeyFor(entry, basePath)) + ".jpg"
  }

  function requestVideoThumb(entry, basePath) {
    var key = root.thumbKeyFor(entry, basePath)
    if (root.videoThumbReady[key]) return
    if (root.thumbQueue.some(function (q) { return root.thumbKeyFor(q.entry, q.basePath) === key })) return
    root.thumbQueue = root.thumbQueue.concat([{ entry: entry, basePath: basePath || root.currentPath }])
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
    var dest = root.videoThumbPath(entry, basePath)
    thumbProc.currentKey = root.thumbKeyFor(entry, basePath)
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
    listProc.command = [root.pluginDir + "/list-dir.sh", root.currentPath, root.showHidden ? "1" : "0"]
    listProc.running = true
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

  function removeBookmark(path) {
    root.bookmarks = root.bookmarks.filter(function (b) { return b.path !== path })
    root.saveBookmarks()
  }

  function addBookmark(path, label) {
    if (root.bookmarks.some(function (b) { return b.path === path })) return
    root.bookmarks = root.bookmarks.concat([{ label: label, path: path }])
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
    var label = modelData.label.toLowerCase()
    if (label.indexOf("picture") >= 0 || label.indexOf("imagen") >= 0) return root.iconFor({ name: "x.jpg" })
    if (label.indexOf("video") >= 0) return root.iconFor({ name: "x.mp4" })
    if (label.indexOf("music") >= 0 || label.indexOf("música") >= 0) return root.iconFor({ name: "x.mp3" })
    return "\u{F024B}"
  }

  function isBookmarked(path) {
    return root.bookmarks.some(function (b) { return b.path === path })
  }

  function parseMounts(text) {
    var lines = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
    return lines.map(function (l) {
      var parts = l.split("\t")
      return { label: parts[0], path: parts[1], device: parts[2] || "", removable: parts[3] === "1", mounted: parts[4] !== "0", fstype: parts[5] || "" }
    })
  }

  function iconForMount(mount) {
    if (mount.fstype === "iso9660") return root.iconFor({ type: "file", name: "x.iso" })
    return mount.removable ? "\u{F0553}" : "\u{F02CA}"
  }

  // list-network-mounts.sh separa por NUL, no por TSV -- ver
  // parseEntries()/list-dir.sh para el motivo (un dato con tab/salto de
  // línea real no debe poder desalinear campos). Aquí el dato es una
  // etiqueta que el propio script construye, nunca texto arbitrario del
  // usuario, pero se mantiene el mismo protocolo para no tener dos
  // convenciones de parseo distintas en el fichero.
  function parseNetworkMounts(text) {
    var s = String(text || "")
    if (s.length === 0) return []
    var fields = s.split(String.fromCharCode(0))
    if (fields.length > 0 && fields[fields.length - 1] === "") fields.pop()
    var out = []
    for (var i = 0; i + 2 < fields.length; i += 3) {
      out.push({ label: fields[i], path: fields[i + 1], scheme: fields[i + 2] })
    }
    return out
  }

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
    mountProc.command = ["udisksctl", "mount", "-b", mount.device]
    mountProc.running = true
  }

  function emptyTrash() {
    runAction("gio trash --empty --force", "Emptying trash…")
  }

  // list-dir.sh/search-recursive.sh separan TODO por NUL (\0) -- campos Y
  // entradas -- en vez de TAB/newline: un nombre de fichero real puede
  // contener un tab o un salto de línea (son bytes válidos en un nombre de
  // Linux, solo "/" y NUL están prohibidos), así que un TSV de toda la
  // vida se podía desalinear con un nombre así y hacer que una operación
  // destructiva actuara sobre el fichero equivocado. NUL es el único byte
  // que nunca puede aparecer dentro de un campo, así que separar por NUL
  // es inequívoco pase lo que pase en el nombre.
  function parseEntries(text) {
    var s = String(text || "")
    if (s.length === 0) return []
    var fields = s.split("\u0000")
    // Cada campo, incluido el último de la última entrada, termina en
    // NUL -- split() deja un elemento vacío colgando al final. Se quita
    // solo ese, no con un filtro genérico: un campo "enlace" vacío en
    // medio (fichero normal, sin symlink) es válido y no hay que perderlo.
    if (fields.length > 0 && fields[fields.length - 1] === "") fields.pop()
    var out = []
    for (var i = 0; i + 4 < fields.length; i += 5) {
      out.push({
        type: fields[i], name: fields[i + 1],
        size: Number(fields[i + 2] || 0), mtime: Number(fields[i + 3] || 0),
        link: fields[i + 4] || ""
      })
    }
    return out
  }

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
      var na = a.name.toLowerCase(), nb = b.name.toLowerCase()
      result = na < nb ? -1 : (na > nb ? 1 : 0)
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
      previewOpen: root.previewOpen, previewEntry: root.previewEntry
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
  function _restoreTabPreview(tab) {
    if (tab.previewOpen && tab.previewEntry) {
      root.loadPreview(tab.previewEntry)
    } else {
      root.previewOpen = false
    }
  }

  function switchToTab(index) {
    if (index < 0 || index >= root.tabs.length || index === root.activeTabIndex) return
    root.saveActiveTab()
    root.activeTabIndex = index
    root._restoreTabHistory(root.tabs[index])
    root._goToPath(root.tabs[index].path)
    root._restoreTabPreview(root.tabs[index])
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
    root._restoreTabPreview(root.tabs[newIndex])
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
    } else {
      openProc.command = ["xdg-open", root.joinPath(root.currentPath, entry.name)]
      openProc.running = true
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
    var out = root.homeDir + "/.cache/omafiles/archive-open/" + root.simpleHash(root.archivePath + "|" + full) + "/" + entry.name
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
    var selectName = nlIdx >= 0 ? payload.substring(nlIdx + 1) : ""
    var targetPath = (folderPart && folderPart.charAt(0) === "/") ? folderPart : ""

    if (targetPath) root.pendingSelectName = selectName

    if (!root.loaded) {
      if (targetPath) {
        root.currentPath = targetPath
        root.tabs = [{ path: targetPath, history: [targetPath], historyIndex: 0 }]
        root.navHistory = [targetPath]
        root.navHistoryIndex = 0
      }
      root.refresh()
    } else if (targetPath) {
      // Ya estaba cargado antes (uso normal previo): abre en pestaña
      // nueva para no perder la ubicación en la que ya estaba el usuario.
      root.newTab()
      root.navigateTo(targetPath)
      root.saveActiveTab()
    }

    if (!root.bookmarksLoaded) root.loadBookmarks()
    root.refreshMounts()
    root.refreshNetworkMounts()
  }

  function close() {
    root.closingFromHost = true
    root.opened = false
    panel.visible = false
    root.closingFromHost = false
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

  function formatSize(bytes) {
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " K"
    if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " M"
    return (bytes / 1024 / 1024 / 1024).toFixed(1) + " G"
  }

  function relativeTime(epochSeconds) {
    if (!epochSeconds) return ""
    var diff = Math.floor(Date.now() / 1000) - epochSeconds
    if (diff < 60) return "just now"
    if (diff < 3600) return Math.floor(diff / 60) + " min ago"
    if (diff < 86400) return Math.floor(diff / 3600) + " h ago"
    if (diff < 86400 * 30) return Math.floor(diff / 86400) + " d ago"
    if (diff < 86400 * 365) return Math.floor(diff / (86400 * 30)) + " mo ago"
    return Math.floor(diff / (86400 * 365)) + " yr ago"
  }

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
      if (entry.type !== "dir") parts.push(root.formatSize(entry.size))
      // root.trashInfo solo se rellena para la papelera del panel ACTIVO
      // (ver listProc) -- si este es un panel de fondo mostrando la
      // papelera, simplemente no hay info extra que añadir todavía; se
      // degrada a solo el tamaño en vez de mostrar algo incorrecto.
      var info = root.trashInfo[entry.name]
      if (info) {
        var rel = root.relativeTime(info.epoch)
        parts.push(rel ? "Deleted " + rel : "Deleted")
        if (info.origPath) {
          var slash = info.origPath.lastIndexOf("/")
          parts.push("from " + (slash > 0 ? info.origPath.substring(0, slash) : "/"))
        }
      }
      return parts.join(" · ")
    }
    var parts = []
    if (entry.type !== "dir") parts.push(root.formatSize(entry.size))
    var rel = root.relativeTime(entry.mtime)
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
    root.refresh()
    root.refreshTick += 1
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
    runAction("mv " + (overwrite ? "-f" : "-n") + " -- " + Util.shellQuote(r.oldPath) + " " + Util.shellQuote(r.newPath), undefined, function () {
      root.pushUndo("rename to \"" + oldName + "\"", function () {
        return root.runAction("mv -n -- " + Util.shellQuote(r.newPath) + " " + Util.shellQuote(r.oldPath))
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
    // Mismo criterio que makeLinkFor/runPendingRename: undo solo si "touch"
    // confirmó éxito.
    runAction("touch -- " + Util.shellQuote(path), undefined, function () {
      // gio trash en vez de rm: si el usuario ya escribió algo antes de
      // deshacer, va a la papelera en vez de perderse sin recuperación.
      root.pushUndo("new file \"" + name + "\"", function () {
        return root.runAction("gio trash -- " + Util.shellQuote(path))
      })
    })
  }

  function commitNewFolder(name) {
    root.creatingFolder = false
    root.creatingFile = false
    name = name.trim()
    if (!name) return
    var path = root.joinPath(root.currentPath, name)
    runAction("mkdir -p -- " + Util.shellQuote(path), undefined, function () {
      // rmdir en vez de rm -rf: si el usuario ya metió algo dentro antes de
      // deshacer, falla en vez de borrar contenido a lo tonto.
      root.pushUndo("new folder \"" + name + "\"", function () {
        return root.runAction("rmdir -- " + Util.shellQuote(path))
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
    var quoted = names.map(function (n) { return Util.shellQuote(root.joinPath(root.currentPath, n)) }).join(" ")
    if (root.currentPath === root.trashDir) {
      // Borrado permanente -- no hay undo posible.
      runAction("rm -rf -- " + quoted)
    } else {
      var label = names.length === 1 ? "delete \"" + names[0] + "\"" : "delete " + names.length + " items"
      runAction("gio trash -- " + quoted, "", function () {
        // Solo se registra el undo si el borrado a papelera confirmó éxito
        // -- antes se registraba siempre, así que un "gio trash" fallido
        // (permiso denegado, etc.) dejaba un undo que restauraba algo que
        // nunca llegó a borrarse.
        root.pushUndo(label, function () {
          var cmds = names.map(function (n) {
            var uri = "trash:///" + n.split("/").map(encodeURIComponent).join("/")
            return "gio trash --restore -- " + Util.shellQuote(uri)
          })
          return root.runAction(root.chainCmds(cmds))
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
  }

  function cutSelected() {
    if (root.inArchive) return
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    root.clipboardPaths = entries.map(function (e) { return root.joinPath(root.currentPath, e.name) })
    root.clipboardMode = "cut"
  }

  function paste() {
    if (root.inArchive) return
    if (root.clipboardPaths.length === 0) return
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
      runAction(root.chainCmds(cmds), busyLabel, function () {
        if (!isCut) return
        var label = pairs.length === 1
          ? "move \"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\""
          : "move " + pairs.length + " items"
        root.pushUndo(label, function () {
          var undoCmds = pairs.map(function (p) {
            return "mv -n -- " + Util.shellQuote(p.dest) + " " + Util.shellQuote(p.src)
          })
          return root.runAction(root.chainCmds(undoCmds))
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
      runAction(root.chainCmds(cmds), busyLabel, function () {
        if (!isMove) return
        var label = pairs.length === 1
          ? "move \"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\""
          : "move " + pairs.length + " items"
        root.pushUndo(label, function () {
          var undoCmds = pairs.map(function (p) {
            return "mv -n -- " + Util.shellQuote(p.dest) + " " + Util.shellQuote(p.src)
          })
          return root.runAction(root.chainCmds(undoCmds))
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
      { label: "Paste", enabled: root.clipboardPaths.length > 0, run: function () { root.paste() } },
      { label: "Delete", enabled: hasSelection, run: function () { root.requestDelete() } },
      { label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", run: function () { root.toggleHidden() } },
      { label: "Refresh", run: function () { root.refresh(); root.refreshMounts(); root.refreshNetworkMounts() } },
      { label: "Sort by name", run: function () { root.setSort("name") } },
      { label: "Sort by size", run: function () { root.setSort("size") } },
      { label: "Sort by date", run: function () { root.setSort("mtime") } },
      { label: "Sort by type", run: function () { root.setSort("type") } },
      { label: "Reverse order", run: function () { root.reverseSort() } },
      { label: root.undoStack.length > 0 ? "Undo: " + root.undoStack[root.undoStack.length - 1].label : "Undo",
        enabled: root.undoStack.length > 0, run: function () { root.undoLast() } },
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
      { label: "Properties", enabled: hasSelection, run: function () { root.showPropertiesForSelection() } }
    ]
    if (root.currentPath === root.trashDir) {
      cmds.push({ label: "Empty trash", run: function () { root.emptyTrash() } })
      cmds.push({ label: "Restore", enabled: hasSelection, run: function () { root.restoreFromTrash() } })
    }
    if (entry && entry.type !== "dir" && root.isArchive(entry)) {
      cmds.push({ label: "Extract here", run: function () { root.extractHere(entry) } })
    }
    if (entry && entry.type === "dir") {
      var fullPath = root.joinPath(root.currentPath, entry.name)
      if (!root.isBookmarked(fullPath)) {
        cmds.push({ label: "Add to bookmarks", run: function () { root.addBookmark(fullPath, entry.name) } })
      }
      cmds.push({ label: "Open in new tab", run: function () { root.openInNewTab(fullPath) } })
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
    root.previewEntry = entry
    root.previewOpen = true
    root.previewText = ""
    var ext = root.extOf(entry.name)
    root.previewIsText = root.codeExt.indexOf(ext) >= 0 || ext === "txt" || ext === "conf" || ext === ""
    if (root.previewIsText && !root.isImage(entry)) {
      previewProc.command = ["head", "-c", "4000", root.joinPath(root.currentPath, entry.name)]
      previewProc.running = true
    }
    if (root.isVideo(entry)) root.requestVideoThumb(entry)
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
      Quickshell.execDetached(["gtk-launch", desktopId, root.joinPath(root.currentPath, root.openWithEntry.name)])
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
    var cmds = pairs.filter(function (p) { return p.newName !== p.oldName }).map(function (p) {
      return "mv -n -- " + Util.shellQuote(p.oldPath) + " " + Util.shellQuote(p.newPath)
    })
    if (cmds.length === 0) return
    runAction(root.chainCmds(cmds), "Renaming " + cmds.length + " items…")
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
    var paths = entries.map(function (e) { return Util.shellQuote(root.joinPath(root.currentPath, e.name)) }).join(" ")
    chmodStatProc.command = ["bash", "-c", "stat -c%a -- " + paths]
    chmodStatProc.running = true
    root.chmodOpen = true
  }

  function commitChmod(mode) {
    root.chmodOpen = false
    mode = mode.trim()
    if (!/^[0-7]{3,4}$/.test(mode) || root.chmodNames.length === 0) return
    var cmds = root.chmodNames.map(function (n) {
      return "chmod " + mode + " -- " + Util.shellQuote(root.joinPath(root.currentPath, n))
    })
    var label = root.chmodNames.length === 1
      ? "Setting permissions for \"" + root.chmodNames[0] + "\"…"
      : "Setting permissions for " + root.chmodNames.length + " items…"
    runAction(root.chainCmds(cmds), label)
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
    runAction("ln -s -- " + Util.shellQuote(target) + " " + Util.shellQuote(linkPath), undefined, function () {
      root.pushUndo("make link \"" + linkName + "\"", function () {
        return root.runAction("rm -- " + Util.shellQuote(linkPath))
      })
    })
  }

  function showProperties(entry) {
    if (!entry) return
    root.propertiesRequestId += 1
    root.propertiesMulti = false
    var path = root.joinPath(root.currentPath, entry.name)
    root.propertiesEntry = entry
    root.propertiesSize = entry.type === "dir" ? "" : root.formatSize(entry.size)
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
    var cmds = entries.map(function (e) {
      var uri = "trash:///" + e.name.split("/").map(encodeURIComponent).join("/")
      return "gio trash --restore -- " + Util.shellQuote(uri)
    })
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

    if (!multi) {
      actions.push({ label: "Open", action: function () { root.enter(entries[0]) } })
      if (entries[0].type === "dir") {
        actions.push({ label: "Open in new tab", action: function () {
          root.openInNewTab(root.joinPath(root.currentPath, entries[0].name))
        } })
      } else {
        actions.push({ label: "Open with...", action: function () { root.showOpenWith(entries[0]) } })
      }
      actions.push({ label: "Rename", action: function () { root.startRename(root.selectedIndex) } })
      if (entries[0].type === "dir") {
        var fullPath = root.joinPath(root.currentPath, entries[0].name)
        if (!root.isBookmarked(fullPath)) {
          actions.push({ label: "Add to bookmarks", action: function () { root.addBookmark(fullPath, entries[0].name) } })
        }
      }
      if (root.isArchive(entries[0])) {
        actions.push({ label: "Extract here", action: function () { root.extractHere(entries[0]) } })
      }
      actions.push({ label: "Make link", action: function () { root.makeLinkFor(entries[0]) } })
      actions.push({ label: "Permissions...", action: function () { root.startChmod(entries) } })
    } else {
      actions.push({ label: "Bulk rename...", action: function () { root.startBulkRename() } })
      actions.push({ label: "Permissions...", action: function () { root.startChmod(entries) } })
    }
    actions.push({ label: "Copy" + suffix, action: function () { root.copySelected() } })
    actions.push({ label: "Cut" + suffix, action: function () { root.cutSelected() } })
    if (root.clipboardPaths.length > 0) actions.push({ label: "Paste here", action: function () { root.paste() } })
    actions.push({ label: "Compress to .zip", action: function () { root.compressSelected() } })
    actions.push({ label: "Delete" + suffix, destructive: true, action: function () { root.requestDelete() } })
    actions.push({ label: "Properties" + suffix, action: function () { root.showPropertiesForSelection() } })
    actions.push({ label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { root.toggleHidden() } })
    return actions
  }

  function emptyAreaActions() {
    var actions = []
    if (root.currentPath === root.trashDir) {
      actions.push({ label: "Empty trash", destructive: true, action: function () { root.emptyTrash() } })
    } else {
      actions.push({ label: "New folder", action: function () { root.startNewFolder() } })
      actions.push({ label: "New file", action: function () { root.startNewFile() } })
      actions.push({ label: "Paste", enabled: root.clipboardPaths.length > 0, action: function () { root.paste() } })
    }
    actions.push({ label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { root.toggleHidden() } })
    actions.push({ label: "Refresh", action: function () { root.refresh(); root.refreshMounts(); root.refreshNetworkMounts() } })
    return actions
  }

  function bookmarkActions(bookmark) {
    var actions = [
      { label: "Open", action: function () { root.navigateTo(bookmark.path) } },
      { label: "Open in new tab", action: function () { root.openInNewTab(bookmark.path) } }
    ]
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
      actions.push({ label: "Add to bookmarks", action: function () { root.addBookmark(mount.path, mount.label) } })
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

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.entries = root.sortEntries(root.parseEntries(text))
        // Refresca la info de la papelera junto con el listado -- entrar
        // en Trash/files o borrar/restaurar algo estando ya dentro debe
        // mantener origen/fecha al día. Se limpia al salir para no dejar
        // datos obsoletos si se vuelve a entrar más tarde con contenido
        // distinto.
        if (root.currentPath === root.trashDir) {
          trashInfoProc.command = [root.pluginDir + "/trash-info.sh", root.homeDir + "/.local/share/Trash/info"]
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
        var selectName = root.pendingSelectName
        root.pendingSelectName = ""
        var foundIndex = -1
        if (selectName) {
          for (var i = 0; i < root.visibleEntries.length; i++) {
            if (root.visibleEntries[i].name === selectName) { foundIndex = i; break }
          }
        }
        if (foundIndex >= 0) root.selectOnly(foundIndex)
        else if (root.selectedIndex >= root.visibleEntries.length) root.selectedIndex = root.visibleEntries.length - 1
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
        for (var i = 0; i + 2 < fields.length; i += 3) {
          info[fields[i]] = { origPath: fields[i + 1], epoch: Number(fields[i + 2] || 0) }
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
        var parsed = root.parseEntries(text)
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
      onStreamFinished: root.mounts = root.parseMounts(text)
    }
  }

  Process {
    id: ejectProc
    property string mountPath: ""
    property bool wasInside: false
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: ejectProc.errorText = text
    }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        if (ejectProc.wasInside) root.navigateTo(root.homeDir)
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
        if (match) root.navigateTo(match[1])
      } else {
        Quickshell.execDetached(["notify-send", "Omafiles", "Could not mount: " + (mountProc.errorText || "unknown error")])
      }
    }
  }

  Process {
    id: networkMountsProc
    command: [root.pluginDir + "/list-network-mounts.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.networkMounts = root.parseNetworkMounts(text)
    }
  }

  Process {
    id: networkUnmountProc
    property bool wasInside: false
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: networkUnmountProc.errorText = text
    }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        if (networkUnmountProc.wasInside) root.navigateTo(root.homeDir)
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
        var parsed = root.parseNetworkMounts(text)
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
    id: actionProc
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: actionProc.errorText = text
    }
    onExited: function (exitCode) {
      root.actionBusy = false
      root.actionLabel = ""
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
      onStreamFinished: root.previewText = text
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
      }
    }
  }

  Process {
    id: thumbProc
    property string currentKey: ""
    property string currentDest: ""
    onExited: {
      var ready = Object.assign({}, root.videoThumbReady)
      ready[thumbProc.currentKey] = thumbProc.currentDest
      root.videoThumbReady = ready
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
        Column {
          id: sidebar
          width: 160
          height: parent.height
          spacing: Style.spacing.sm

          Repeater {
            model: root.bookmarks

            CursorSurface {
              required property var modelData
              readonly property bool isCurrent: root.currentPath === modelData.path
              width: sidebar.width
              implicitHeight: Style.spacing.controlHeight
              foreground: Color.menu.text
              accent: Color.accent
              hasCursor: bookmarkMouse.containsMouse
              current: isCurrent || root.dropHoverPath === modelData.path

              DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: function (drag) {
                  if (!drag.hasUrls) { drag.accepted = false; return }
                  root.dropHoverPath = modelData.path
                }
                onExited: if (root.dropHoverPath === modelData.path) root.dropHoverPath = ""
                onDropped: function (drop) {
                  root.dropHoverPath = ""
                  root.handleFilesDropped(drop, modelData.path)
                }
              }

              OpticalGlyph {
                id: bookmarkIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                width: Style.font.title
                height: Style.font.title
                text: root.iconForBookmark(parent.modelData)
                fontFamily: Style.font.family
                fontSize: Style.font.icon
                color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: bookmarkIcon.right
                anchors.leftMargin: Style.spacing.xs
                text: parent.modelData.label
                font.pixelSize: Style.font.title
                font.family: Style.font.family
                color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
                elide: Text.ElideRight
                width: sidebar.width - Style.spacing.sm * 2 - bookmarkIcon.width - Style.spacing.xs
              }

              MouseArea {
                id: bookmarkMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function (mouse) {
                  if (mouse.button === Qt.RightButton) {
                    var pos = mapToItem(card, mouse.x, mouse.y)
                    root.openContextMenu(pos.x, pos.y, root.bookmarkActions(modelData))
                    return
                  }
                  root.navigateTo(modelData.path)
                }
              }
            }
          }

          Item {
            visible: root.mounts.length > 0
            width: 1
            height: Style.spacing.sm
          }

          PanelSeparator {
            visible: root.mounts.length > 0
            foreground: Color.menu.text
            strength: 0.15
          }

          Item {
            visible: root.mounts.length > 0
            width: 1
            height: Style.spacing.xs
          }

          PanelSectionHeader {
            visible: root.mounts.length > 0
            text: "DEVICES"
            foreground: Color.menu.text
            fontFamily: Style.font.family
            fontSize: Style.font.subtitle
          }

          Repeater {
            model: root.mounts

            CursorSurface {
              required property var modelData
              readonly property bool isCurrent: root.currentPath === modelData.path
              width: sidebar.width
              implicitHeight: Style.spacing.controlHeight
              foreground: Color.menu.text
              accent: Color.accent
              hasCursor: mountMouse.containsMouse
              current: isCurrent || root.dropHoverPath === modelData.path

              DropArea {
                // Solo unidades ya montadas -- soltar en una sin montar no
                // tiene destino real todavía.
                anchors.fill: parent
                enabled: modelData.mounted
                keys: ["text/uri-list"]
                onEntered: function (drag) {
                  if (!drag.hasUrls) { drag.accepted = false; return }
                  root.dropHoverPath = modelData.path
                }
                onExited: if (root.dropHoverPath === modelData.path) root.dropHoverPath = ""
                onDropped: function (drop) {
                  root.dropHoverPath = ""
                  root.handleFilesDropped(drop, modelData.path)
                }
              }

              OpticalGlyph {
                id: mountIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                width: Style.font.title
                height: Style.font.title
                opacity: parent.modelData.mounted ? 1.0 : 0.5
                text: root.iconForMount(parent.modelData)
                fontFamily: Style.font.family
                fontSize: Style.font.icon
                color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: mountIcon.right
                anchors.leftMargin: Style.spacing.xs
                opacity: parent.modelData.mounted ? 1.0 : 0.5
                text: parent.modelData.label
                font.pixelSize: Style.font.title
                font.family: Style.font.family
                color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
                elide: Text.ElideRight
                width: sidebar.width - Style.spacing.sm * 2 - mountIcon.width - Style.spacing.xs
              }

              PanelToolTip {
                visible: mountMouse.containsMouse && !parent.modelData.mounted
                text: "Not mounted -- click to mount"
              }

              MouseArea {
                id: mountMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function (mouse) {
                  if (mouse.button === Qt.RightButton) {
                    var pos = mapToItem(card, mouse.x, mouse.y)
                    root.openContextMenu(pos.x, pos.y, root.mountActions(modelData))
                    return
                  }
                  if (!modelData.mounted) root.mountDevice(modelData)
                  else root.navigateTo(modelData.path)
                }
              }
            }
          }

          Item {
            width: 1
            height: Style.spacing.sm
          }

          PanelSeparator {
            foreground: Color.menu.text
            strength: 0.15
          }

          Item {
            width: 1
            height: Style.spacing.xs
          }

          // A diferencia de DEVICES/marcadores, esta cabecera y la fila de
          // "Connect to server..." se ven siempre, con mounts activos o
          // sin ellos -- si dependieran de root.networkMounts.length > 0
          // nadie podría descubrir la función la primera vez, cuando por
          // definición todavía no hay ninguna conexión de red activa.
          PanelSectionHeader {
            text: "NETWORK"
            foreground: Color.menu.text
            fontFamily: Style.font.family
            fontSize: Style.font.subtitle
          }

          Repeater {
            model: root.networkMounts

            CursorSurface {
              required property var modelData
              readonly property bool isCurrent: root.currentPath === modelData.path
              width: sidebar.width
              implicitHeight: Style.spacing.controlHeight
              foreground: Color.menu.text
              accent: Color.accent
              hasCursor: networkMountMouse.containsMouse
              current: isCurrent

              OpticalGlyph {
                id: networkMountIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                width: Style.font.title
                height: Style.font.title
                text: root.iconForNetworkMount(parent.modelData)
                fontFamily: Style.font.family
                fontSize: Style.font.icon
                color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: networkMountIcon.right
                anchors.leftMargin: Style.spacing.xs
                text: parent.modelData.label
                font.pixelSize: Style.font.title
                font.family: Style.font.family
                color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
                elide: Text.ElideRight
                width: sidebar.width - Style.spacing.sm * 2 - networkMountIcon.width - Style.spacing.xs
              }

              MouseArea {
                id: networkMountMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function (mouse) {
                  if (mouse.button === Qt.RightButton) {
                    var pos = mapToItem(card, mouse.x, mouse.y)
                    root.openContextMenu(pos.x, pos.y, root.networkMountActions(modelData))
                    return
                  }
                  root.navigateTo(modelData.path)
                }
              }
            }
          }

          CursorSurface {
            width: sidebar.width
            implicitHeight: Style.spacing.controlHeight
            foreground: Color.menu.text
            accent: Color.accent
            hasCursor: connectServerMouse.containsMouse

            OpticalGlyph {
              id: connectServerIcon
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.sm
              width: Style.font.title
              height: Style.font.title
              text: "\u{F0490}"
              fontFamily: Style.font.family
              fontSize: Style.font.icon
              color: Color.menu.text
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: connectServerIcon.right
              anchors.leftMargin: Style.spacing.xs
              text: "Connect…"
              font.pixelSize: Style.font.title
              font.family: Style.font.family
              color: Color.menu.text
              elide: Text.ElideRight
              width: sidebar.width - Style.spacing.sm * 2 - connectServerIcon.width - Style.spacing.xs
            }

            MouseArea {
              id: connectServerMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.startConnectToServer()
            }
          }
        }

        Rectangle {
          width: Style.spacing.hairline
          height: parent.height
          color: Color.menu.border
          opacity: 0.3
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
            // contenido (Color.menu.border, opacity 0.3, Style.spacing.hairline).
            Repeater {
              model: Math.max(0, root.tabs.length - 1)
              delegate: Rectangle {
                required property int index
                x: panelsRow.slotX(index) + panelsRow.slotWidth + Style.spacing.panelGap
                y: 0
                width: Style.spacing.hairline
                height: panelsRow.height
                color: Color.menu.border
                opacity: 0.3
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
                opacity: 0.8

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
                  // ningún clic de por medio.
                  onHoveredChanged: if (hovered && !root.hasPendingEdit) root.switchToTab(bgPanel.index)
                }

                function refreshMe() {
                  if (!bgPanel.visible) return
                  bgPanel.pathError = ""
                  bgListProc.command = [root.pluginDir + "/list-dir.sh", bgPanel.modelData.path, root.showHidden ? "1" : "0"]
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
                      bgPanel.entries = root.sortEntries(root.parseEntries(text))
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
                  Button {
                    width: Style.spacing.controlHeight
                    height: Style.spacing.controlHeight
                    foreground: (bgPanel.modelData.historyIndex || 0) <= 0 ? Qt.darker(Color.menu.text, 1.6) : Color.menu.text
                    onClicked: root.navTabBack(bgPanel.index)

                    OpticalGlyph {
                      anchors.centerIn: parent
                      // md-arrow_left, mismo glyph que el panel activo.
                      text: "\u{F004D}"
                      fontFamily: Style.font.family
                      fontSize: Style.font.icon
                      color: parent.foreground
                    }
                  }

                  Button {
                    width: Style.spacing.controlHeight
                    height: Style.spacing.controlHeight
                    readonly property var hist: bgPanel.modelData.history || [bgPanel.modelData.path]
                    foreground: (bgPanel.modelData.historyIndex || 0) >= hist.length - 1 ? Qt.darker(Color.menu.text, 1.6) : Color.menu.text
                    onClicked: root.navTabForward(bgPanel.index)

                    OpticalGlyph {
                      anchors.centerIn: parent
                      // md-arrow_right, mismo glyph que el panel activo.
                      text: "\u{F0054}"
                      fontFamily: Style.font.family
                      fontSize: Style.font.icon
                      color: parent.foreground
                    }
                  }

                  Button {
                    width: Style.spacing.controlHeight
                    height: Style.spacing.controlHeight
                    foreground: bgPanel.modelData.path === "/" ? Qt.darker(Color.menu.text, 1.6) : Color.menu.text
                    onClicked: {
                      var p = bgPanel.modelData.path
                      var idx = p.lastIndexOf("/")
                      root.navigateTabTo(bgPanel.index, idx > 0 ? p.substring(0, idx) : "/")
                    }

                    OpticalGlyph {
                      anchors.centerIn: parent
                      text: "󰅃"
                      fontFamily: Style.font.family
                      fontSize: Style.font.icon
                      color: parent.foreground
                    }
                  }

                  // Migas de pan completas, igual que en el panel activo --
                  // antes solo se veía el nombre de la carpeta actual, sin
                  // el resto de la ruta.
                  Row {
                    id: bgBreadcrumbRow
                    width: parent.width - 3 * Style.spacing.controlHeight - 3 * Style.spacing.controlGap
                    height: parent.height
                    spacing: Style.spacing.xs
                    clip: true

                    Repeater {
                      model: root.pathSegmentsFor(bgPanel.modelData.path)

                      Row {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.spacing.xs

                        Text {
                          text: modelData.label
                          font.pixelSize: Style.font.title
                          font.family: Style.font.family
                          font.bold: modelData.path === bgPanel.modelData.path
                          color: Color.menu.text
                          opacity: modelData.path === bgPanel.modelData.path ? 1.0 : 0.65
                        }

                        Text {
                          visible: modelData.path !== bgPanel.modelData.path
                          text: "›"
                          font.pixelSize: Style.font.title
                          font.family: Style.font.family
                          color: Color.menu.text
                          opacity: 0.4
                        }
                      }
                    }
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
                  anchors.topMargin: Style.spacing.sm
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
                    implicitHeight: bgRowContent.implicitHeight + Style.spacing.sm * 2
                    foreground: Color.menu.text
                    accent: Color.accent
                    hasCursor: bgRowMouse.containsMouse

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
                      // Sin margen a la izquierda -- igual que rowContent del
                      // panel activo, para que el icono quede en la misma
                      // columna que los botones de atrás/adelante/subir de
                      // bgHeaderRow, justo encima.
                      anchors.leftMargin: 0
                      anchors.rightMargin: Style.spacing.rowPaddingX
                      implicitHeight: Math.max(bgThumbSlot.height, bgNameCol.implicitHeight)

                      Item {
                        id: bgThumbSlot
                        // Misma miniatura real que el panel activo -- antes
                        // solo tenía los iconos genéricos de tipo, así que
                        // las imágenes/vídeos se veían sin previsualizar
                        // hasta que el cursor pasaba a ser el panel activo.
                        readonly property bool isVid: root.isVideo(modelData)
                        readonly property string vidKey: isVid ? root.thumbKeyFor(modelData, bgPanel.modelData.path) : ""
                        readonly property string vidThumb: vidKey ? (root.videoThumbReady[vidKey] || "") : ""
                        readonly property bool isDir: modelData.type === "dir"
                        readonly property bool hasThumb: root.isImage(modelData) || (isVid && vidThumb !== "")
                        readonly property bool isBroken: modelData.link === "broken"
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.spacing.controlHeight
                        height: Style.spacing.controlHeight

                        Component.onCompleted: if (isVid) root.requestVideoThumb(modelData, bgPanel.modelData.path)

                        Image {
                          anchors.fill: parent
                          visible: status === Image.Ready
                          // La ruta es la de ESTE panel (bgPanel.modelData.path),
                          // no root.currentPath -- ese es del panel activo,
                          // y era justo lo que hacía fallar la miniatura
                          // aquí cuando este panel no era el activo.
                          source: root.isImage(modelData) ? Util.fileUrl(root.joinPath(bgPanel.modelData.path, modelData.name))
                            : (bgThumbSlot.vidThumb ? Util.fileUrl(bgThumbSlot.vidThumb) : "")
                          fillMode: Image.PreserveAspectCrop
                          asynchronous: true
                          sourceSize.width: 32
                          sourceSize.height: 32
                        }

                        OpticalGlyph {
                          anchors.fill: parent
                          visible: bgThumbSlot.isDir && !bgThumbSlot.isBroken
                          text: "󰉋"
                          fontFamily: Style.font.family
                          fontSize: Style.font.iconLarge
                          color: Color.menu.text
                        }

                        OpticalGlyph {
                          anchors.fill: parent
                          visible: !bgThumbSlot.isDir && !bgThumbSlot.hasThumb && !bgThumbSlot.isBroken
                          text: root.iconFor(modelData)
                          fontFamily: Style.font.family
                          fontSize: Style.font.iconLarge
                          color: Color.menu.text
                        }

                        OpticalGlyph {
                          anchors.fill: parent
                          visible: bgThumbSlot.isBroken
                          text: "\u{F033A}"
                          fontFamily: Style.font.family
                          fontSize: Style.font.iconLarge
                          color: Color.urgent
                        }
                      }

                      Column {
                        id: bgNameCol
                        anchors.left: bgThumbSlot.right
                        anchors.leftMargin: Style.spacing.rowGap
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.spacing.hairline

                        Text {
                          width: parent.width
                          text: modelData.name + (modelData.type === "dir" ? "/" : "")
                          font.pixelSize: Style.font.title
                          font.family: Style.font.family
                          color: modelData.link === "broken" ? Color.urgent : Color.menu.text
                          elide: Text.ElideRight
                        }

                        Text {
                          readonly property string meta: root.metaFor(modelData, bgPanel.modelData.path)
                          visible: meta.length > 0
                          width: parent.width
                          text: meta
                          font.pixelSize: Style.font.bodySmall
                          font.family: Style.font.family
                          color: Color.menu.text
                          opacity: 0.6
                          elide: Text.ElideRight
                        }
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

              // Tinte de fondo muy sutil detrás de TODO el panel, solo
              // cuando hay más de uno a la vista -- con un único panel no
              // hay nada que desambiguar y sería decoración de más.
              // Declarado antes que el resto de hijos (queda debajo, no
              // tapa nada) y sin anchors.margins, así que no roba espacio
              // ni desplaza la fila de navegación/lista un solo píxel --
              // a diferencia de un borde o una línea, que sí necesitarían
              // hueco propio y podrían desalinear el panel activo respecto
              // a los de fondo (ver la nota sobre alineado a píxel más
              // abajo en el fichero). Complementa el atenuado de bgPanel:
              // color (no solo brillo), para notarse sin comparar los dos
              // paneles a la vez.
              Rectangle {
                visible: root.tabs.length > 1
                anchors.fill: parent
                color: Util.alpha(Color.accent, 0.08)
              }

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

            Button {
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.navHistoryIndex <= 0 ? Qt.darker(Color.menu.text, 1.6) : Color.menu.text
              onClicked: root.navBack()

              OpticalGlyph {
                anchors.centerIn: parent
                // md-arrow_left, verificado contra el cmap real de la fuente.
                text: "\u{F004D}"
                fontFamily: Style.font.family
                fontSize: Style.font.icon
                color: parent.foreground
              }
            }

            Button {
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.navHistoryIndex >= root.navHistory.length - 1 ? Qt.darker(Color.menu.text, 1.6) : Color.menu.text
              onClicked: root.navForward()

              OpticalGlyph {
                anchors.centerIn: parent
                // md-arrow_right, verificado contra el cmap real de la fuente.
                text: "\u{F0054}"
                fontFamily: Style.font.family
                fontSize: Style.font.icon
                color: parent.foreground
              }
            }

            Button {
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.currentPath === "/" ? Qt.darker(Color.menu.text, 1.6) : Color.menu.text
              onClicked: root.goUp()

              OpticalGlyph {
                anchors.centerIn: parent
                text: "󰅃"
                fontFamily: Style.font.family
                fontSize: Style.font.icon
                color: parent.foreground
              }
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

              Row {
                id: breadcrumbRow
                visible: !root.editingPath
                anchors.fill: parent
                spacing: Style.spacing.xs
                clip: true

                Repeater {
                  model: root.pathSegments()

                  Row {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xs

                    // Sin MouseArea propio a propósito -- josema no quería
                    // navegación por segmento (ya están los botones de
                    // atrás/subir para eso), solo texto que deje pasar el
                    // clic al MouseArea de detrás (editar ruta a mano).
                    Text {
                      text: modelData.label
                      font.pixelSize: Style.font.title
                      font.family: Style.font.family
                      font.bold: modelData.path === root.currentPath
                      color: Color.menu.text
                      opacity: modelData.path === root.currentPath ? 1.0 : 0.65
                    }

                    Text {
                      visible: modelData.path !== root.currentPath
                      text: "›"
                      font.pixelSize: Style.font.title
                      font.family: Style.font.family
                      color: Color.menu.text
                      opacity: 0.4
                    }
                  }
                }
              }

              TextField {
                id: pathField
                visible: root.editingPath
                anchors.fill: parent
                verticalPadding: 2
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
            height: activePanel.height - navRow.height - Style.spacing.hairline
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
              // hasta el borde real, así que ese hueco cae en ellos.
              anchors.topMargin: Style.spacing.sm
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
                } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                  root.selectedIndices = Array.from({ length: root.visibleEntries.length }, function (_, i) { return i })
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
                implicitHeight: rowContent.implicitHeight + Style.spacing.sm * 2
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
                  enabled: thumbSlot.isDir
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
                  implicitHeight: Math.max(thumbSlot.height, nameCol.implicitHeight)

                  Item {
                    id: thumbSlot
                    // Miniatura real si la hay (imagen/vídeo); si no, icono
                    // de carpeta o de tipo de fichero -- mismo glyph/fuente
                    // que usa el menú de Omarchy.
                    readonly property bool isVid: root.isVideo(modelData)
                    readonly property string vidKey: isVid ? root.thumbKeyFor(modelData) : ""
                    readonly property string vidThumb: vidKey ? (root.videoThumbReady[vidKey] || "") : ""
                    readonly property bool isDir: modelData.type === "dir"
                    readonly property bool hasThumb: root.isImage(modelData) || (isVid && vidThumb !== "")
                    readonly property bool isBroken: modelData.link === "broken"
                    // Mismo ancho que los botones de casita/subir de navRow
                    // (Style.spacing.controlHeight), para que el icono quede
                    // centrado en la misma columna que ellos.
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.spacing.controlHeight
                    height: Style.spacing.controlHeight

                    Component.onCompleted: if (isVid) root.requestVideoThumb(modelData)

                    Image {
                      anchors.fill: parent
                      visible: status === Image.Ready
                      source: root.isImage(modelData) ? Util.fileUrl(root.joinPath(root.currentPath, modelData.name))
                        : (thumbSlot.vidThumb ? Util.fileUrl(thumbSlot.vidThumb) : "")
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      sourceSize.width: 32
                      sourceSize.height: 32
                    }

                    OpticalGlyph {
                      anchors.fill: parent
                      visible: thumbSlot.isDir && !thumbSlot.isBroken
                      text: "󰉋"
                      fontFamily: Style.font.family
                      fontSize: Style.font.iconLarge
                      color: rowSurface.current ? Color.menu.selectedText : Color.menu.text
                    }

                    OpticalGlyph {
                      anchors.fill: parent
                      visible: !thumbSlot.isDir && !thumbSlot.hasThumb && !thumbSlot.isBroken
                      text: root.iconFor(modelData)
                      fontFamily: Style.font.family
                      fontSize: Style.font.iconLarge
                      color: rowSurface.current ? Color.menu.selectedText : Color.menu.text
                    }

                    // Enlace simbólico roto (md-link_variant_off, verificado
                    // contra el cmap real de la fuente) -- antes se veía como
                    // un fichero normal de 0 bytes fechado en 1970, sin
                    // ningún indicio de que el destino ya no existe.
                    OpticalGlyph {
                      anchors.fill: parent
                      visible: thumbSlot.isBroken
                      text: "\u{F033A}"
                      fontFamily: Style.font.family
                      fontSize: Style.font.iconLarge
                      color: Color.urgent
                    }
                  }

                  TextField {
                    id: renameField
                    visible: root.renamingIndex === index
                    anchors.left: thumbSlot.right
                    anchors.leftMargin: Style.spacing.rowGap
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

                  // Fila de dos líneas (nombre + tamaño/fecha relativa) --
                  // mismo patrón que el ejemplo real de fila compuesta de
                  // Omarchy (icono + Column de título/subtítulo).
                  Column {
                    id: nameCol
                    visible: root.renamingIndex !== index
                    anchors.left: thumbSlot.right
                    anchors.leftMargin: Style.spacing.rowGap
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.hairline

                    Text {
                      width: parent.width
                      text: modelData.name + (modelData.type === "dir" ? "/" : "")
                      font.pixelSize: Style.font.title
                      font.family: Style.font.family
                      color: modelData.link === "broken" ? Color.urgent
                        : root.clipboardMode === "cut" && root.clipboardPaths.indexOf(root.joinPath(root.currentPath, modelData.name)) >= 0
                        ? Qt.darker(Color.menu.text, 1.6)
                        : (rowSurface.current ? Color.menu.selectedText : Color.menu.text)
                      elide: Text.ElideRight
                    }

                    Text {
                      readonly property string meta: root.metaFor(modelData)
                      visible: meta.length > 0
                      width: parent.width
                      text: meta
                      font.pixelSize: Style.font.bodySmall
                      font.family: Style.font.family
                      color: rowSurface.current ? Color.menu.selectedText : Color.menu.text
                      opacity: 0.6
                      elide: Text.ElideRight
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
                  onDoubleClicked: root.enter(modelData)
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
            BorderSurface {
              id: previewPanel
              visible: root.previewOpen
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.right: parent.right
              width: parent.width * 0.45 - Style.spacing.rowGap
              radius: Style.cornerRadius
              color: Color.menu.selectedBackground
              borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
              padding: Style.spacing.sm

              MouseArea { anchors.fill: parent; onClicked: {} }

              Column {
                anchors.fill: parent
                anchors.topMargin: previewPanel.contentTopInset
                anchors.rightMargin: previewPanel.contentRightInset
                anchors.bottomMargin: previewPanel.contentBottomInset
                anchors.leftMargin: previewPanel.contentLeftInset
                spacing: Style.spacing.sm

                Text {
                  width: parent.width
                  text: root.previewEntry ? root.previewEntry.name : ""
                  font.pixelSize: Style.font.title
                  font.family: Style.font.family
                  font.bold: true
                  color: Color.menu.text
                  elide: Text.ElideMiddle
                }

                PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

                Image {
                  visible: root.previewEntry && root.isImage(root.previewEntry)
                  width: parent.width
                  height: parent.height - 60
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  source: root.previewEntry && root.isImage(root.previewEntry)
                    ? Util.fileUrl(root.joinPath(root.currentPath, root.previewEntry.name)) : ""
                }

                readonly property string previewVideoThumb: root.previewEntry && root.isVideo(root.previewEntry)
                  ? (root.videoThumbReady[root.thumbKeyFor(root.previewEntry)] || "") : ""

                Image {
                  visible: root.previewEntry && root.isVideo(root.previewEntry) && parent.previewVideoThumb !== ""
                  width: parent.width
                  height: parent.height - 60
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  source: parent.previewVideoThumb ? Util.fileUrl(parent.previewVideoThumb) : ""
                }

                Flickable {
                  visible: root.previewEntry && !root.isImage(root.previewEntry) && root.previewIsText
                  width: parent.width
                  height: parent.height - 60
                  clip: true
                  contentWidth: width
                  contentHeight: previewTextItem.implicitHeight

                  Text {
                    id: previewTextItem
                    width: parent.width
                    text: root.previewText || "(empty)"
                    font.pixelSize: Style.font.subtitle
                    font.family: "monospace"
                    color: Color.menu.text
                    wrapMode: Text.Wrap
                  }
                }

                Column {
                  visible: root.previewEntry && !root.isImage(root.previewEntry) && !root.previewIsText
                    && !(root.isVideo(root.previewEntry) && root.videoThumbReady[root.thumbKeyFor(root.previewEntry)])
                  width: parent.width
                  spacing: Style.spacing.sm

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "No preview"
                    font.pixelSize: Style.font.title
                    font.family: Style.font.family
                    color: Color.menu.text
                    opacity: 0.5
                  }

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.previewEntry ? root.formatSize(root.previewEntry.size) : ""
                    font.pixelSize: Style.font.title
                    font.family: Style.font.family
                    color: Color.menu.text
                    opacity: 0.6
                  }
                }
              }
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
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        visible: root.bulkRenameOpen
        z: 15
        onClicked: root.bulkRenameOpen = false
      }

      BorderSurface {
        id: bulkRenameCard
        visible: root.bulkRenameOpen
        width: Math.min(parent.width - 80, 380)
        height: bulkRenameColumn.implicitHeight + contentTopInset + contentBottomInset
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 20

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: bulkRenameColumn
          anchors.fill: parent
          anchors.topMargin: bulkRenameCard.contentTopInset
          anchors.rightMargin: bulkRenameCard.contentRightInset
          anchors.bottomMargin: bulkRenameCard.contentBottomInset
          anchors.leftMargin: bulkRenameCard.contentLeftInset
          spacing: Style.spacing.sm

          Text {
            width: parent.width
            text: "Rename " + root.selectedIndices.length + " items"
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.bold: true
            color: Color.menu.text
          }

          Text {
            width: parent.width
            text: "Use {name}, {ext}, {n} (sequence number)"
            font.pixelSize: Style.font.subtitle
            font.family: Style.font.family
            color: Color.menu.text
            opacity: 0.6
            wrapMode: Text.Wrap
          }

          TextField {
            id: bulkRenameField
            width: parent.width
            text: root.bulkRenamePattern
            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() } else list.forceActiveFocus()
            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.bulkRenamePattern = text
                root.commitBulkRename()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.bulkRenameOpen = false
                event.accepted = true
              }
            }
          }

          Button {
            text: "Rename"
            bordered: true
            onClicked: { root.bulkRenamePattern = bulkRenameField.text; root.commitBulkRename() }
          }
        }
      }

      // ---------- Conectar a servidor ----------
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        visible: root.connectServerOpen
        z: 15
        onClicked: if (!root.networkConnecting) root.cancelConnectToServer()
      }

      BorderSurface {
        id: connectServerCard
        visible: root.connectServerOpen
        width: Math.min(parent.width - 80, 420)
        height: connectServerColumn.implicitHeight + contentTopInset + contentBottomInset
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 20

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: connectServerColumn
          anchors.fill: parent
          anchors.topMargin: connectServerCard.contentTopInset
          anchors.rightMargin: connectServerCard.contentRightInset
          anchors.bottomMargin: connectServerCard.contentBottomInset
          anchors.leftMargin: connectServerCard.contentLeftInset
          spacing: Style.spacing.sm

          Text {
            width: parent.width
            text: "Connect to server"
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.bold: true
            color: Color.menu.text
          }

          Text {
            width: parent.width
            text: "sftp://user@host/path · smb://server/share · dav(s)://host/path · ftp://host/path"
            font.pixelSize: Style.font.bodySmall
            font.family: Style.font.family
            color: Color.menu.text
            opacity: 0.6
            wrapMode: Text.Wrap
          }

          TextField {
            id: connectServerField
            width: parent.width
            text: root.connectServerUri
            enabled: !root.networkConnecting
            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() } else list.forceActiveFocus()
            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.connectServerUri = text
                root.commitConnectToServer()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (root.networkConnecting) root.cancelNetworkConnect()
                else root.cancelConnectToServer()
                event.accepted = true
              }
            }
          }

          Text {
            width: parent.width
            visible: root.connectServerError.length > 0
            text: root.connectServerError
            font.pixelSize: Style.font.bodySmall
            font.family: Style.font.family
            color: Color.urgent
            wrapMode: Text.Wrap
          }

          Row {
            spacing: Style.spacing.sm

            Button {
              text: root.networkConnecting ? "Connecting…" : "Connect"
              bordered: true
              enabled: !root.networkConnecting
              onClicked: { root.connectServerUri = connectServerField.text; root.commitConnectToServer() }
            }

            Button {
              text: "Cancel"
              visible: root.networkConnecting
              onClicked: root.cancelNetworkConnect()
            }
          }
        }
      }

      // ---------- Permisos (chmod) ----------
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        visible: root.chmodOpen
        z: 15
        onClicked: root.chmodOpen = false
      }

      BorderSurface {
        id: chmodCard
        visible: root.chmodOpen
        width: Math.min(parent.width - 80, 320)
        height: chmodColumn.implicitHeight + contentTopInset + contentBottomInset
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 20

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: chmodColumn
          anchors.fill: parent
          anchors.topMargin: chmodCard.contentTopInset
          anchors.rightMargin: chmodCard.contentRightInset
          anchors.bottomMargin: chmodCard.contentBottomInset
          anchors.leftMargin: chmodCard.contentLeftInset
          spacing: Style.spacing.sm

          Text {
            width: parent.width
            text: root.chmodNames.length === 1
              ? "Permissions for \"" + root.chmodNames[0] + "\""
              : "Permissions for " + root.chmodNames.length + " items"
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.bold: true
            color: Color.menu.text
            elide: Text.ElideMiddle
          }

          Text {
            width: parent.width
            visible: root.chmodMixed
            text: "Mixed permissions — choose a mode to apply to all"
            font.pixelSize: Style.font.bodySmall
            font.family: Style.font.family
            color: Qt.darker(Color.menu.text, 1.6)
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

          // Cabecera de columnas -- hueco a la izquierda del ancho de la
          // etiqueta de fila (Owner/Group/Other), luego Read/Write/Exec.
          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Item { width: 60; height: 1 }

            Repeater {
              model: ["Read", "Write", "Exec"]

              Text {
                required property string modelData
                width: Style.spacing.controlHeight
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                font.pixelSize: Style.font.caption
                font.family: Style.font.family
                color: Color.menu.text
                opacity: 0.6
              }
            }
          }

          // Owner (tú) / Group / Other -- cada fila con sus 3 casillas rwx,
          // en vez de escribir el octal a mano. root.chmodMode sigue siendo
          // la fuente de verdad (un string de 3 dígitos); cada casilla
          // consulta/cambia un bit suyo directamente.
          Repeater {
            model: [
              { label: "Owner", idx: 0 },
              { label: "Group", idx: 1 },
              { label: "Other", idx: 2 }
            ]

            Row {
              id: chmodRow
              required property var modelData
              width: chmodColumn.width
              spacing: Style.spacing.sm

              Text {
                width: 60
                anchors.verticalCenter: parent.verticalCenter
                text: chmodRow.modelData.label
                font.pixelSize: Style.font.subtitle
                font.family: Style.font.family
                color: Color.menu.text
              }

              Repeater {
                model: [4, 2, 1]

                // CursorSurface en vez de un Rectangle+MouseArea a mano --
                // mismo componente que usa cualquier otra fila/pestaña
                // clicable de la app, así que la casilla tiene el mismo
                // hover y el mismo tratamiento de "seleccionado" (current)
                // que el resto, en vez de un estilo inventado aparte.
                CursorSurface {
                  id: chmodCell
                  required property int modelData
                  width: Style.spacing.controlHeight
                  height: Style.spacing.controlHeight
                  anchors.verticalCenter: parent.verticalCenter
                  foreground: Color.menu.text
                  accent: Color.accent
                  bordered: true
                  hasCursor: chmodCellMouse.containsMouse
                  current: root.chmodBitSet(chmodRow.modelData.idx, modelData)

                  MouseArea {
                    id: chmodCellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleChmodBit(chmodRow.modelData.idx, chmodCell.modelData)
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

          Text {
            width: parent.width
            text: "Octal: " + root.chmodMode
            font.pixelSize: Style.font.subtitle
            font.family: Style.font.family
            color: Color.menu.text
            opacity: 0.6
          }

          Button {
            text: "Apply"
            bordered: true
            onClicked: root.commitChmod(root.chmodMode)
          }
        }
      }

      // ---------- Propiedades ----------
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        visible: root.propertiesOpen
        z: 15
        onClicked: root.propertiesOpen = false
      }

      BorderSurface {
        id: propertiesCard
        visible: root.propertiesOpen
        width: Math.min(parent.width - 80, 360)
        height: propertiesColumn.implicitHeight + contentTopInset + contentBottomInset
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 20

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: propertiesColumn
          anchors.fill: parent
          anchors.topMargin: propertiesCard.contentTopInset
          anchors.rightMargin: propertiesCard.contentRightInset
          anchors.bottomMargin: propertiesCard.contentBottomInset
          anchors.leftMargin: propertiesCard.contentLeftInset
          spacing: Style.spacing.xs

          Text {
            width: parent.width
            text: root.propertiesMulti
              ? root.propertiesCount + " items selected"
              : (root.propertiesEntry ? root.propertiesEntry.name : "")
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.bold: true
            color: Color.menu.text
            elide: Text.ElideMiddle
          }

          PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

          Repeater {
            model: root.propertiesMulti
              ? [
                  { label: "Items", value: String(root.propertiesCount) },
                  { label: "Total size", value: root.propertiesSizeLoading ? "Calculating…" : root.propertiesSize }
                ]
              : [
                  { label: "Type", value: root.propertiesEntry ? (root.propertiesEntry.type === "dir" ? "Folder" : "File") : "" },
                  { label: "Size", value: root.propertiesSizeLoading ? "Calculating…" : root.propertiesSize },
                  { label: "Permissions", value: root.propertiesPerms },
                  { label: "Owner", value: root.propertiesOwner },
                  { label: "Modified", value: root.propertiesMtime }
                ]

            Row {
              required property var modelData
              width: propertiesColumn.width
              spacing: Style.spacing.sm

              Text {
                width: 84
                text: parent.modelData.label
                font.pixelSize: Style.font.subtitle
                font.family: Style.font.family
                color: Color.menu.text
                opacity: 0.6
              }

              Text {
                width: parent.width - 84 - Style.spacing.sm
                text: parent.modelData.value
                font.pixelSize: Style.font.subtitle
                font.family: Style.font.family
                color: Color.menu.text
                elide: Text.ElideRight
              }
            }
          }

          Button {
            text: "Close"
            bordered: true
            onClicked: root.propertiesOpen = false
          }
        }
      }

      // ---------- Copiar/mover en curso ----------
      // No bloquea el resto de la ventana (sin MouseArea de fondo a pantalla
      // completa) -- cp/mv no reportan progreso real, así que esto es solo
      // "sigue vivo" (puntos animados) + Cancel, no una barra de porcentaje.
      BorderSurface {
        id: actionBusyCard
        visible: root.actionBusy
        width: Math.min(parent.width - 80, 420)
        height: actionBusyRow.implicitHeight + contentTopInset + contentBottomInset
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.lg
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 25

        Row {
          id: actionBusyRow
          anchors.fill: parent
          anchors.topMargin: actionBusyCard.contentTopInset
          anchors.rightMargin: actionBusyCard.contentRightInset
          anchors.bottomMargin: actionBusyCard.contentBottomInset
          anchors.leftMargin: actionBusyCard.contentLeftInset
          spacing: Style.spacing.sm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - cancelActionButton.width - parent.spacing
            text: root.actionLabel + root.actionBusyDots
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
            onClicked: root.cancelAction()
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
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        visible: root.openWithOpen
        z: 15
        onClicked: root.openWithOpen = false
      }

      BorderSurface {
        id: openWithCard
        visible: root.openWithOpen
        width: Math.min(parent.width - 80, 320)
        height: openWithColumn.implicitHeight + contentTopInset + contentBottomInset
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 20

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: openWithColumn
          anchors.fill: parent
          anchors.topMargin: openWithCard.contentTopInset
          anchors.rightMargin: openWithCard.contentRightInset
          anchors.bottomMargin: openWithCard.contentBottomInset
          anchors.leftMargin: openWithCard.contentLeftInset
          spacing: Style.spacing.xs

          Text {
            width: parent.width
            text: "Open \"" + (root.openWithEntry ? root.openWithEntry.name : "") + "\" with:"
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.bold: true
            color: Color.menu.text
            elide: Text.ElideMiddle
          }

          PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

          Text {
            visible: root.openWithApps.length === 0
            width: parent.width
            text: "No registered applications for this file type."
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            color: Color.menu.text
            opacity: 0.6
            wrapMode: Text.Wrap
          }

          Repeater {
            model: root.openWithApps

            CursorSurface {
              required property var modelData
              width: openWithColumn.width
              implicitHeight: Style.spacing.controlHeight
              foreground: Color.menu.text
              accent: Color.accent
              hasCursor: appMouse.containsMouse

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                text: parent.modelData.name
                font.pixelSize: Style.font.title
                font.family: Style.font.family
                color: Color.menu.text
              }

              MouseArea {
                id: appMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.launchWith(modelData.id)
              }
            }
          }
        }
      }

      // ---------- Menú contextual ----------
      MouseArea {
        anchors.fill: parent
        visible: root.contextMenuOpen
        z: 15
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.contextMenuOpen = false
      }

      BorderSurface {
        id: contextMenu
        visible: root.contextMenuOpen
        x: root.contextMenuX
        y: root.contextMenuY
        width: 200
        height: contextMenuColumn.implicitHeight + contentTopInset + contentBottomInset
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 20

        Column {
          id: contextMenuColumn
          anchors.fill: parent
          anchors.topMargin: contextMenu.contentTopInset
          anchors.rightMargin: contextMenu.contentRightInset
          anchors.bottomMargin: contextMenu.contentBottomInset
          anchors.leftMargin: contextMenu.contentLeftInset
          spacing: Style.spacing.xxs

          Repeater {
            model: root.contextMenuActions

            CursorSurface {
              required property var modelData
              readonly property bool actionEnabled: modelData.enabled !== false
              width: contextMenuColumn.width
              implicitHeight: Style.spacing.controlHeight
              foreground: Color.menu.text
              accent: Color.accent
              hasCursor: itemMouse.containsMouse && actionEnabled

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                text: parent.modelData.label
                font.pixelSize: Style.font.title
                font.family: Style.font.family
                color: parent.modelData.destructive ? Color.urgent : (parent.actionEnabled ? Color.menu.text : Qt.darker(Color.menu.text, 1.8))
              }

              MouseArea {
                id: itemMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: parent.actionEnabled
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.contextMenuOpen = false
                  parent.modelData.action()
                }
              }
            }
          }
        }
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
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        visible: root.pasteConflictOpen
        z: 15
        onClicked: root.cancelPasteConflict()
      }

      BorderSurface {
        id: pasteConflictCard
        visible: root.pasteConflictOpen
        width: Math.min(parent.width - 80, 360)
        height: pasteConflictColumn.implicitHeight + contentTopInset + contentBottomInset
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 20

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: pasteConflictColumn
          anchors.fill: parent
          anchors.topMargin: pasteConflictCard.contentTopInset
          anchors.rightMargin: pasteConflictCard.contentRightInset
          anchors.bottomMargin: pasteConflictCard.contentBottomInset
          anchors.leftMargin: pasteConflictCard.contentLeftInset
          spacing: Style.spacing.sm

          Text {
            width: parent.width
            text: root.pasteConflictNames.length === 1
              ? "\"" + root.pasteConflictNames[0] + "\" already exists here."
              : root.pasteConflictNames.length + " items already exist here."
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.bold: true
            color: Color.menu.text
            wrapMode: Text.Wrap
          }

          Column {
            width: parent.width
            spacing: Style.spacing.xs

            Button { width: parent.width; leftAlign: true; bordered: true; text: "Overwrite all"; onClicked: root.runPaste("overwrite") }
            Button { width: parent.width; leftAlign: true; bordered: true; text: "Skip existing"; onClicked: root.runPaste("skip") }
            Button { width: parent.width; leftAlign: true; bordered: true; text: "Cancel"; onClicked: root.cancelPasteConflict() }
          }
        }
      }

      // ---------- Conflicto al soltar (drag & drop) ----------
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        visible: root.dropConflictOpen
        z: 15
        onClicked: root.cancelDropConflict()
      }

      BorderSurface {
        id: dropConflictCard
        visible: root.dropConflictOpen
        width: Math.min(parent.width - 80, 360)
        height: dropConflictColumn.implicitHeight + contentTopInset + contentBottomInset
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 20

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: dropConflictColumn
          anchors.fill: parent
          anchors.topMargin: dropConflictCard.contentTopInset
          anchors.rightMargin: dropConflictCard.contentRightInset
          anchors.bottomMargin: dropConflictCard.contentBottomInset
          anchors.leftMargin: dropConflictCard.contentLeftInset
          spacing: Style.spacing.sm

          Text {
            width: parent.width
            text: root.dropConflictNames.length === 1
              ? "\"" + root.dropConflictNames[0] + "\" already exists here."
              : root.dropConflictNames.length + " items already exist here."
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.bold: true
            color: Color.menu.text
            wrapMode: Text.Wrap
          }

          Column {
            width: parent.width
            spacing: Style.spacing.xs

            Button { width: parent.width; leftAlign: true; bordered: true; text: "Overwrite all"; onClicked: root.runDrop("overwrite") }
            Button { width: parent.width; leftAlign: true; bordered: true; text: "Skip existing"; onClicked: root.runDrop("skip") }
            Button { width: parent.width; leftAlign: true; bordered: true; text: "Cancel"; onClicked: root.cancelDropConflict() }
          }
        }
      }

      // ---------- Paleta de comandos (: o Ctrl+P) ----------
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        visible: root.paletteOpen
        z: 25
        onClicked: root.closePalette()
      }

      BorderSurface {
        id: palette
        visible: root.paletteOpen
        width: Math.min(parent.width - 80, 420)
        height: Math.min(parent.height - 2 * Style.spacing.huge, 360)
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.spacing.huge
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
        padding: Style.spacing.sm
        z: 30

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: paletteColumn
          anchors.fill: parent
          anchors.topMargin: palette.contentTopInset
          anchors.rightMargin: palette.contentRightInset
          anchors.bottomMargin: palette.contentBottomInset
          anchors.leftMargin: palette.contentLeftInset
          spacing: Style.spacing.xs

          TextField {
            id: paletteField
            width: parent.width
            placeholderText: "Type a command…"
            text: root.paletteQuery
            onTextChanged: { root.paletteQuery = text; root.paletteIndex = 0 }
            onVisibleChanged: if (visible) forceActiveFocus(); else list.forceActiveFocus()
            Keys.onPressed: function (event) {
              var cmds = root.filteredPaletteCommands()
              if (event.key === Qt.Key_Escape) {
                root.closePalette()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.runPaletteCommand(root.paletteIndex)
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.paletteIndex = Math.min(cmds.length - 1, root.paletteIndex + 1)
                paletteList.positionViewAtIndex(root.paletteIndex, ListView.Contain)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.paletteIndex = Math.max(0, root.paletteIndex - 1)
                paletteList.positionViewAtIndex(root.paletteIndex, ListView.Contain)
                event.accepted = true
              }
            }
          }

          PanelSeparator { id: paletteSep; foreground: Color.menu.text; strength: 0.15 }

          ListView {
            id: paletteList
            width: parent.width
            height: parent.height - paletteField.height - paletteSep.height - 2 * paletteColumn.spacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.paletteOpen ? root.filteredPaletteCommands() : []

            delegate: CursorSurface {
              required property var modelData
              required property int index
              readonly property bool cmdEnabled: modelData.enabled !== false
              width: paletteList.width
              implicitHeight: Style.spacing.controlHeight
              foreground: Color.menu.text
              accent: Color.accent
              hasCursor: index === root.paletteIndex && cmdEnabled

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                text: parent.modelData.label
                font.pixelSize: Style.font.title
                font.family: Style.font.family
                color: parent.cmdEnabled ? (index === root.paletteIndex ? Color.menu.selectedText : Color.menu.text) : Qt.darker(Color.menu.text, 1.8)
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: parent.cmdEnabled
                cursorShape: Qt.PointingHandCursor
                onEntered: root.paletteIndex = index
                onClicked: root.runPaletteCommand(index)
              }
            }
          }
        }
      }
    }
  }
}

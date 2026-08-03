import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// Omafiles v0.5 -- explorador de archivos para Omarchy.
// Ventana normal (FloatingWindow, tileable en Hyprland como cualquier otra
// app), no un overlay modal. Barra lateral con accesos y unidades (montar/
// expulsar), ruta editable a mano, orden por nombre/tamaño/fecha/tipo
// (tecla "s"/"S"), menú contextual y paleta de comandos (Ctrl+P) para todas
// las acciones de fichero, avisos de conflicto al copiar/pegar/renombrar,
// propiedades. Sin drag&drop todavía.
Item {
  id: root

  property string homeDir: Quickshell.env("HOME")
  property string pluginDir: homeDir + "/.config/omarchy/plugins/omafiles"
  property string currentPath: homeDir
  property var tabs: [{ path: homeDir }]
  property int activeTabIndex: 0
  property var entries: []
  property bool searching: false
  property string deepSearchRoot: ""
  property string searchQuery: ""
  readonly property var visibleEntries: root.searchQuery
    ? root.entries.filter(function (e) { return e.name.toLowerCase().indexOf(root.searchQuery.toLowerCase()) >= 0 })
    : root.entries
  property bool opened: false
  property bool closingFromHost: false
  property bool loaded: false
  // Nombre de entrada a resaltar en cuanto termine el próximo listado --
  // lo usa open() cuando el payload pide "abre esta carpeta y selecciona
  // este fichero" (caso ShowItems de org.freedesktop.FileManager1).
  property string pendingSelectName: ""

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
    entry.undo()
    Quickshell.execDetached(["notify-send", "Omafiles", "Undone: " + entry.label])
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

  readonly property var sortKeys: ["name", "size", "mtime", "type"]
  readonly property var sortKeyLabels: ({ name: "Name", size: "Size", mtime: "Date", type: "Type" })
  property string sortKey: "name"
  property bool sortDesc: false

  property int renamingIndex: -1
  property bool creatingFolder: false
  property bool editingPath: false

  property var clipboardPaths: []
  property string clipboardMode: "" // "copy" | "cut"

  property var pendingDeleteNames: []

  property var pendingRename: null // { oldPath, newPath }
  property bool renameConflictOpen: false

  property var pasteConflictNames: []
  property bool pasteConflictOpen: false

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
  property string chmodEntry: ""
  property string chmodMode: ""

  property bool propertiesOpen: false
  property var propertiesEntry: null
  property string propertiesSize: ""
  property bool propertiesSizeLoading: false
  property string propertiesPerms: ""
  property string propertiesOwner: ""
  property string propertiesMtime: ""

  readonly property var tarExt: ["tar", "gz", "tgz", "bz2", "tbz", "xz", "txz"]
  property var previewEntry: null
  property string previewText: ""
  property bool previewIsText: false

  property string trashDir: root.homeDir + "/.local/share/Trash/files"
  property var mounts: []

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

  function thumbKeyFor(entry) {
    return root.joinPath(root.currentPath, entry.name) + "|" + entry.mtime
  }

  function videoThumbPath(entry) {
    return root.thumbCacheDir + "/" + root.simpleHash(root.thumbKeyFor(entry)) + ".jpg"
  }

  function requestVideoThumb(entry) {
    var key = root.thumbKeyFor(entry)
    if (root.videoThumbReady[key]) return
    if (root.thumbQueue.some(function (e) { return root.thumbKeyFor(e) === key })) return
    root.thumbQueue = root.thumbQueue.concat([entry])
    root.processThumbQueue()
  }

  function processThumbQueue() {
    if (root.thumbBusy || root.thumbQueue.length === 0) return
    root.thumbBusy = true
    var next = root.thumbQueue.slice()
    var entry = next.shift()
    root.thumbQueue = next
    var src = root.joinPath(root.currentPath, entry.name)
    var dest = root.videoThumbPath(entry)
    thumbProc.currentKey = root.thumbKeyFor(entry)
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

  // Recalcula la selección a partir del rectángulo del lazo (marqueeStartY/
  // marqueeCurrentY, en coordenadas de contenido). Filas de altura uniforme
  // (nombres/metadatos no hacen wrap, siempre una línea) -- basta con
  // dividir por la altura media en vez de inspeccionar los delegados reales
  // de la ListView, más simple y ajeno a la virtualización.
  function updateMarqueeSelection(additive, base) {
    var total = root.visibleEntries.length
    if (total === 0 || list.contentHeight <= 0) return
    var rowH = list.contentHeight / total
    var top = Math.min(root.marqueeStartY, root.marqueeCurrentY)
    var bottom = Math.max(root.marqueeStartY, root.marqueeCurrentY)
    var picked = []
    if (bottom > 0 && top < list.contentHeight) {
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
    listProc.command = [root.pluginDir + "/list-dir.sh", root.currentPath, root.showHidden ? "1" : "0"]
    listProc.running = true
  }

  function refreshMounts() {
    mountsProc.running = true
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

  function ejectMount(mount) {
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
    mountProc.command = ["udisksctl", "mount", "-b", mount.device]
    mountProc.running = true
  }

  function emptyTrash() {
    runAction("gio trash --empty --force")
  }

  function parseEntries(text) {
    var lines = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
    return lines.map(function (l) {
      var parts = l.split("\t")
      return { type: parts[0], name: parts[1], size: Number(parts[2] || 0), mtime: Number(parts[3] || 0) }
    })
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
    root.currentPath = path
    root.selectOnly(-1)
    root.renamingIndex = -1
    root.creatingFolder = false
    root.editingPath = false
    root.refresh()
  }

  function saveActiveTab() {
    var next = root.tabs.slice()
    next[root.activeTabIndex] = { path: root.currentPath }
    root.tabs = next
  }

  function switchToTab(index) {
    if (index < 0 || index >= root.tabs.length || index === root.activeTabIndex) return
    root.saveActiveTab()
    root.activeTabIndex = index
    root.navigateTo(root.tabs[index].path)
  }

  function newTab() {
    root.saveActiveTab()
    root.tabs = root.tabs.concat([{ path: root.currentPath }])
    root.activeTabIndex = root.tabs.length - 1
  }

  function closeTab() {
    if (root.tabs.length <= 1) { root.requestClose(); return }
    var next = root.tabs.slice()
    next.splice(root.activeTabIndex, 1)
    root.tabs = next
    var newIndex = Math.min(root.activeTabIndex, next.length - 1)
    root.activeTabIndex = newIndex
    root.navigateTo(root.tabs[newIndex].path)
  }

  function nextTab() {
    root.switchToTab((root.activeTabIndex + 1) % root.tabs.length)
  }

  function enter(entry) {
    if (!entry) return
    if (entry.type === "dir") {
      navigateTo(root.joinPath(root.currentPath, entry.name))
    } else {
      openProc.command = ["xdg-open", root.joinPath(root.currentPath, entry.name)]
      openProc.running = true
    }
  }

  function goUp() {
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
        root.tabs = [{ path: targetPath }]
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
  }

  function close() {
    root.closingFromHost = true
    root.opened = false
    panel.visible = false
    root.closingFromHost = false
    root.renamingIndex = -1
    root.creatingFolder = false
    root.editingPath = false
    root.pendingDeleteNames = []
    root.contextMenuOpen = false
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
  function metaFor(entry) {
    var parts = []
    if (entry.type !== "dir") parts.push(root.formatSize(entry.size))
    var rel = root.relativeTime(entry.mtime)
    if (rel) parts.push(rel)
    return parts.join(" · ")
  }

  function runAction(cmd) {
    actionProc.command = ["bash", "-c", cmd]
    actionProc.running = true
  }

  function startRename(index) {
    if (index < 0 || index >= root.visibleEntries.length) return
    root.creatingFolder = false
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
    runAction("mv " + (overwrite ? "-f" : "-n") + " -- " + Util.shellQuote(r.oldPath) + " " + Util.shellQuote(r.newPath))
    var oldName = r.oldPath.substring(r.oldPath.lastIndexOf("/") + 1)
    root.pushUndo("rename to \"" + oldName + "\"", function () {
      root.runAction("mv -n -- " + Util.shellQuote(r.newPath) + " " + Util.shellQuote(r.oldPath))
    })
  }

  function cancelPendingRename() {
    root.pendingRename = null
    root.renameConflictOpen = false
  }

  function startNewFolder() {
    root.renamingIndex = -1
    root.searching = false
    root.creatingFolder = true
  }

  function commitNewFolder(name) {
    root.creatingFolder = false
    name = name.trim()
    if (!name) return
    var path = root.joinPath(root.currentPath, name)
    runAction("mkdir -p -- " + Util.shellQuote(path))
    // rmdir en vez de rm -rf: si el usuario ya metió algo dentro antes de
    // deshacer, falla en vez de borrar contenido a lo tonto.
    root.pushUndo("new folder \"" + name + "\"", function () {
      root.runAction("rmdir -- " + Util.shellQuote(path))
    })
  }

  function requestDelete() {
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
      runAction("gio trash -- " + quoted)
      var label = names.length === 1 ? "delete \"" + names[0] + "\"" : "delete " + names.length + " items"
      root.pushUndo(label, function () {
        var cmds = names.map(function (n) {
          var uri = "trash:///" + n.split("/").map(encodeURIComponent).join("/")
          return "gio trash --restore -- " + Util.shellQuote(uri)
        })
        root.runAction(cmds.join(" && "))
      })
    }
  }

  function copySelected() {
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    root.clipboardPaths = entries.map(function (e) { return root.joinPath(root.currentPath, e.name) })
    root.clipboardMode = "copy"
  }

  function cutSelected() {
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    root.clipboardPaths = entries.map(function (e) { return root.joinPath(root.currentPath, e.name) })
    root.clipboardMode = "cut"
  }

  function paste() {
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
      runAction(cmds.join(" && "))
      if (isCut) {
        var label = pairs.length === 1
          ? "move \"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\""
          : "move " + pairs.length + " items"
        root.pushUndo(label, function () {
          var undoCmds = pairs.map(function (p) {
            return "mv -n -- " + Util.shellQuote(p.dest) + " " + Util.shellQuote(p.src)
          })
          root.runAction(undoCmds.join(" && "))
        })
      }
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
      runAction(cmds.join(" && "))
      if (isMove) {
        var label = pairs.length === 1
          ? "move \"" + pairs[0].dest.substring(pairs[0].dest.lastIndexOf("/") + 1) + "\""
          : "move " + pairs.length + " items"
        root.pushUndo(label, function () {
          var undoCmds = pairs.map(function (p) {
            return "mv -n -- " + Util.shellQuote(p.dest) + " " + Util.shellQuote(p.src)
          })
          root.runAction(undoCmds.join(" && "))
        })
      }
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
    if (!drop.hasUrls) { drop.accepted = false; return }
    var paths = drop.urls.map(function (u) { return root.urlToPath(u) }).filter(function (p) { return p.length > 0 })
    if (paths.length === 0) { drop.accepted = false; return }
    var isMove = drop.source !== null && drop.source !== undefined
    drop.accept(isMove ? Qt.MoveAction : Qt.CopyAction)
    root.startDropInto(destDir, paths, isMove)
  }

  function toggleHidden() {
    root.showHidden = !root.showHidden
    root.refresh()
  }

  function startEditPath() {
    root.editingPath = true
  }

  function startSearch() {
    root.creatingFolder = false
    root.searching = true
    root.searchQuery = ""
  }

  function exitSearch() {
    root.searching = false
    root.searchQuery = ""
    root.deepSearchRoot = ""
    root.refresh()
    root.selectOnly(-1)
  }

  function runDeepSearch() {
    if (!root.searchQuery) return
    root.deepSearchRoot = root.currentPath
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
      { label: "Rename", enabled: root.selectedIndices.length === 1, run: function () { root.startRename(root.selectedIndex) } },
      { label: "Copy", enabled: hasSelection, run: function () { root.copySelected() } },
      { label: "Cut", enabled: hasSelection, run: function () { root.cutSelected() } },
      { label: "Paste", enabled: root.clipboardPaths.length > 0, run: function () { root.paste() } },
      { label: "Delete", enabled: hasSelection, run: function () { root.requestDelete() } },
      { label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", run: function () { root.toggleHidden() } },
      { label: "Refresh", run: function () { root.refresh(); root.refreshMounts() } },
      { label: "Sort by name", run: function () { root.setSort("name") } },
      { label: "Sort by size", run: function () { root.setSort("size") } },
      { label: "Sort by date", run: function () { root.setSort("mtime") } },
      { label: "Sort by type", run: function () { root.setSort("type") } },
      { label: "Reverse order", run: function () { root.reverseSort() } },
      { label: root.undoStack.length > 0 ? "Undo: " + root.undoStack[root.undoStack.length - 1].label : "Undo",
        enabled: root.undoStack.length > 0, run: function () { root.undoLast() } },
      { label: "Terminal here", run: function () { root.openTerminalHere() } },
      { label: "Go to Home", run: function () { root.navigateTo(root.homeDir) } },
      { label: "Edit path", run: function () { root.startEditPath() } },
      { label: "Search", run: function () { root.startSearch() } },
      { label: "Compress to .zip", enabled: hasSelection, run: function () { root.compressSelected() } },
      { label: "Bulk rename...", enabled: root.selectedIndices.length > 1, run: function () { root.startBulkRename() } },
      { label: "Permissions...", enabled: !!entry, run: function () { if (entry) root.startChmod(entry) } },
      { label: "Properties", enabled: !!entry, run: function () { if (entry) root.showProperties(entry) } }
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
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    var archiveName = entries.length === 1
      ? entries[0].name.replace(/\/$/, "") + ".zip"
      : "selected-files.zip"
    var names = entries.map(function (e) { return Util.shellQuote(e.name) }).join(" ")
    runAction("cd -- " + Util.shellQuote(root.currentPath) + " && zip -r -q " + Util.shellQuote(archiveName) + " " + names)
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
    var cmd
    if (ext === "zip") cmd = "unzip -o -q " + path + " -d " + dir
    else if (ext === "7z") cmd = "7z x -y " + path + " -o" + dir
    else if (ext === "rar") cmd = "unrar x -o+ " + path + " " + dir + "/"
    else if (root.tarExt.indexOf(ext) >= 0) cmd = "tar xf " + path + " -C " + dir
    else return
    runAction(cmd)
  }

  function startBulkRename() {
    root.bulkRenamePattern = "{name}{ext}"
    root.bulkRenameOpen = true
  }

  function commitBulkRename() {
    var entries = root.selectedEntries()
    root.bulkRenameOpen = false
    if (entries.length === 0) return
    var pattern = root.bulkRenamePattern
    var cmds = entries.map(function (e, i) {
      var ext = e.type === "dir" ? "" : (root.extOf(e.name) ? "." + root.extOf(e.name) : "")
      var base = ext ? e.name.slice(0, -ext.length) : e.name
      var newName = pattern.replace(/\{name\}/g, base).replace(/\{ext\}/g, ext).replace(/\{n\}/g, String(i + 1))
      var oldPath = root.joinPath(root.currentPath, e.name)
      var newPath = root.joinPath(root.currentPath, newName)
      return "mv -n -- " + Util.shellQuote(oldPath) + " " + Util.shellQuote(newPath)
    })
    runAction(cmds.join(" && "))
  }

  function startChmod(entry) {
    root.chmodEntry = entry.name
    root.chmodMode = ""
    chmodStatProc.command = ["stat", "-c%a", root.joinPath(root.currentPath, entry.name)]
    chmodStatProc.running = true
    root.chmodOpen = true
  }

  function commitChmod(mode) {
    root.chmodOpen = false
    mode = mode.trim()
    if (!/^[0-7]{3,4}$/.test(mode) || !root.chmodEntry) return
    runAction("chmod " + mode + " -- " + Util.shellQuote(root.joinPath(root.currentPath, root.chmodEntry)))
  }

  function showProperties(entry) {
    if (!entry) return
    var path = root.joinPath(root.currentPath, entry.name)
    root.propertiesEntry = entry
    root.propertiesSize = entry.type === "dir" ? "" : root.formatSize(entry.size)
    root.propertiesSizeLoading = entry.type === "dir"
    root.propertiesPerms = ""
    root.propertiesOwner = ""
    root.propertiesMtime = ""
    root.propertiesOpen = true
    propertiesStatProc.command = ["stat", "-c", "%A %a\t%U:%G\t%y", "--", path]
    propertiesStatProc.running = true
    if (entry.type === "dir") {
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
    runAction(cmds.join(" && "))
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
      if (entries[0].type !== "dir") {
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
      actions.push({ label: "Permissions...", action: function () { root.startChmod(entries[0]) } })
      actions.push({ label: "Properties", action: function () { root.showProperties(entries[0]) } })
    } else {
      actions.push({ label: "Bulk rename...", action: function () { root.startBulkRename() } })
    }
    actions.push({ label: "Copy" + suffix, action: function () { root.copySelected() } })
    actions.push({ label: "Cut" + suffix, action: function () { root.cutSelected() } })
    if (root.clipboardPaths.length > 0) actions.push({ label: "Paste here", action: function () { root.paste() } })
    actions.push({ label: "Compress to .zip", action: function () { root.compressSelected() } })
    actions.push({ label: "Delete" + suffix, destructive: true, action: function () { root.requestDelete() } })
    actions.push({ label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { root.toggleHidden() } })
    return actions
  }

  function emptyAreaActions() {
    var actions = []
    if (root.currentPath === root.trashDir) {
      actions.push({ label: "Empty trash", destructive: true, action: function () { root.emptyTrash() } })
    } else {
      actions.push({ label: "New folder", action: function () { root.startNewFolder() } })
      actions.push({ label: "Paste", enabled: root.clipboardPaths.length > 0, action: function () { root.paste() } })
    }
    actions.push({ label: root.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { root.toggleHidden() } })
    actions.push({ label: "Refresh", action: function () { root.refresh(); root.refreshMounts() } })
    return actions
  }

  function bookmarkActions(bookmark) {
    var actions = [{ label: "Open", action: function () { root.navigateTo(bookmark.path) } }]
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
    var actions = [{ label: "Open", action: function () { root.navigateTo(mount.path) } }]
    if (!root.isBookmarked(mount.path)) {
      actions.push({ label: "Add to bookmarks", action: function () { root.addBookmark(mount.path, mount.label) } })
    }
    if (mount.removable) {
      actions.push({ label: "Eject", destructive: true, action: function () { root.ejectMount(mount) } })
    }
    return actions
  }

  function pathSegments() {
    if (root.currentPath === "/") return [{ label: "/", path: "/" }]
    var parts = root.currentPath.split("/").filter(function (p) { return p.length > 0 })
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
  }

  Process {
    id: deepSearchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.entries = root.sortEntries(root.parseEntries(text))
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
    onExited: root.refresh()
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
      onStreamFinished: root.chmodMode = text.trim()
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
        }

        Rectangle {
          width: 1
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

          Row {
            id: tabBar
            visible: root.tabs.length > 1
            width: parent.width
            height: Style.spacing.controlHeight
            spacing: Style.spacing.xs

            Repeater {
              model: root.tabs

              CursorSurface {
                required property var modelData
                required property int index
                implicitHeight: tabBar.height
                width: Math.min(140, tabLabel.implicitWidth + 34)
                foreground: Color.menu.text
                accent: Color.accent
                hasCursor: tabMouse.containsMouse
                current: index === root.activeTabIndex

                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.switchToTab(index)
                }

                Row {
                  anchors.fill: parent
                  anchors.margins: Style.spacing.xs
                  spacing: Style.spacing.xs

                  Text {
                    id: tabLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.path === root.homeDir ? "Home" : modelData.path.substring(modelData.path.lastIndexOf("/") + 1)
                    font.pixelSize: Style.font.subtitle
                    font.family: Style.font.family
                    color: index === root.activeTabIndex ? Color.menu.selectedText : Color.menu.text
                    elide: Text.ElideRight
                    width: parent.width - 44
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "×"
                    font.pixelSize: Style.font.subtitle
                    font.family: Style.font.family
                    color: Color.menu.text
                    opacity: 0.6

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -4
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { root.activeTabIndex = index; root.closeTab() }
                    }
                  }
                }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "+"
              font.pixelSize: Style.font.title
              font.family: Style.font.family
              color: Color.menu.text
              opacity: 0.7

              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.newTab()
              }
            }
          }

          Row {
            id: navRow
            width: parent.width
            height: Style.spacing.controlHeight
            spacing: Style.spacing.controlGap

            Button {
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              foreground: Color.menu.text
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.navigateTo(root.homeDir)

              OpticalGlyph {
                anchors.centerIn: parent
                text: ""
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
              width: parent.width - 2 * (Style.spacing.controlHeight + Style.spacing.controlGap)
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

                    Text {
                      text: modelData.label
                      font.pixelSize: Style.font.title
                      font.family: Style.font.family
                      font.bold: modelData.path === root.currentPath
                      color: Color.menu.text
                      opacity: modelData.path === root.currentPath ? 1.0 : 0.65

                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.navigateTo(modelData.path)
                      }
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
                onVisibleChanged: if (visible) { text = root.currentPath; forceActiveFocus(); selectAll() }
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

          PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

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
              onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
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
              onVisibleChanged: if (visible) forceActiveFocus()
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
            height: parent.height - navRow.height - Style.spacing.hairline
              - (tabBar.visible ? tabBar.height + mainColumn.spacing : 0)
              - (root.creatingFolder ? newFolderRow.height + mainColumn.spacing : 0)
              - (root.searching ? searchRow.height + mainColumn.spacing : 0)
              - statusText.height - mainColumn.spacing * (3 + (tabBar.visible ? 1 : 0) + (root.creatingFolder || root.searching ? 1 : 0))

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

            // Detrás de la lista: pulsar y arrastrar sobre hueco vacío
            // dibuja un lazo de selección (como Nautilus/cualquier gestor de
            // iconos) -- Ctrl mantiene pulsado suma a la selección previa en
            // vez de reemplazarla. Solo recibe el gesto si el clic empieza
            // en hueco vacío: una fila ya cubierta por su propio MouseArea
            // (por encima, en la ListView) se queda con el press primero.
            MouseArea {
              id: marqueeArea
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: root.previewOpen ? parent.width * 0.55 : parent.width
              acceptedButtons: Qt.LeftButton
              property bool additive: false
              property var baseSelection: []
              onPressed: function (mouse) {
                additive = (mouse.modifiers & Qt.ControlModifier) !== 0
                baseSelection = additive ? root.selectedIndices.slice() : []
                if (!additive) root.selectOnly(-1)
                root.marqueeStartX = mouse.x
                root.marqueeCurrentX = mouse.x
                root.marqueeStartY = mouse.y - list.y + list.contentY
                root.marqueeCurrentY = root.marqueeStartY
                root.marqueeActive = true
              }
              onPositionChanged: function (mouse) {
                if (!root.marqueeActive) return
                root.marqueeCurrentX = mouse.x
                root.marqueeCurrentY = mouse.y - list.y + list.contentY
                root.updateMarqueeSelection(additive, baseSelection)
              }
              onReleased: root.marqueeActive = false
              onCanceled: root.marqueeActive = false
            }

            ListView {
              id: list
              anchors.top: parent.top
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
              // Sin esto, el propio Flickable de ListView se queda con
              // cualquier press+arrastre en hueco vacío (para su scroll por
              // arrastre) antes de que llegue a marqueeArea, por debajo --
              // ningún gestor de archivos arrastra la lista así, esa zona es
              // para el lazo de selección. La rueda del ratón sigue
              // funcionando igual (no depende de interactive).
              interactive: false

              Keys.onPressed: function (event) {
                if (root.paletteOpen) return
                if (root.openWithOpen) {
                  if (event.key === Qt.Key_Escape) { root.openWithOpen = false; event.accepted = true }
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
                if (root.creatingFolder || root.renamingIndex >= 0 || root.editingPath || root.searching) return

                var extend = (event.modifiers & Qt.ShiftModifier) !== 0

                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) {
                  root.openTerminalHere()
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  if (root.previewOpen) root.previewOpen = false
                  else root.requestClose()
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
                      visible: thumbSlot.isDir
                      text: "󰉋"
                      fontFamily: Style.font.family
                      fontSize: Style.font.iconLarge
                      color: rowSurface.current ? Color.menu.selectedText : Color.menu.text
                    }

                    OpticalGlyph {
                      anchors.fill: parent
                      visible: !thumbSlot.isDir && !thumbSlot.hasThumb
                      text: root.iconFor(modelData)
                      fontFamily: Style.font.family
                      fontSize: Style.font.iconLarge
                      color: rowSurface.current ? Color.menu.selectedText : Color.menu.text
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
                    onVisibleChanged: if (visible) { text = modelData.name; forceActiveFocus(); selectAll() }
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
                      color: root.clipboardMode === "cut" && root.clipboardPaths.indexOf(root.joinPath(root.currentPath, modelData.name)) >= 0
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
                  // Hueco sin cubrir a la izquierda (el contenido visual --
                  // icono, texto -- no se mueve, solo se reduce el área
                  // interactiva) para poder arrancar el lazo de selección
                  // pegado al borde izquierdo de la lista. Style.spacing.xs
                  // (3px) resultó demasiado fino para acertar con el ratón
                  // -- probado en vivo, hacía falta algo mucho más ancho.
                  anchors.leftMargin: 14
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
              }
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

          // ---------- Barra de estado ----------
          Text {
            id: statusText
            text: root.visibleEntries.length + (root.visibleEntries.length === 1 ? " item" : " items")
              + (root.searchQuery ? " of " + root.entries.length : "")
              + (root.selectedIndices.length > 1 ? " · " + root.selectedIndices.length + " selected" : "")
              + (root.clipboardPaths.length > 0 ? " · clipboard: " + root.clipboardPaths.length + (root.clipboardPaths.length === 1 ? " item" : " items") + (root.clipboardMode === "cut" ? " (cut)" : " (copied)") : "")
              + " · sort: " + root.sortLabel()
            font.pixelSize: Style.font.subtitle
            font.family: Style.font.family
            color: Color.menu.text
            opacity: 0.55
          }
        }
      }

      // ---------- Renombrar en lote ----------
      MouseArea {
        anchors.fill: parent
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
            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
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

      // ---------- Permisos (chmod) ----------
      MouseArea {
        anchors.fill: parent
        visible: root.chmodOpen
        z: 15
        onClicked: root.chmodOpen = false
      }

      BorderSurface {
        id: chmodCard
        visible: root.chmodOpen
        width: Math.min(parent.width - 80, 300)
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
            text: "Permissions for \"" + root.chmodEntry + "\""
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.bold: true
            color: Color.menu.text
            elide: Text.ElideMiddle
          }

          TextField {
            id: chmodField
            width: parent.width
            text: root.chmodMode
            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.commitChmod(text)
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.chmodOpen = false
                event.accepted = true
              }
            }
          }

          Button {
            text: "Apply"
            bordered: true
            onClicked: root.commitChmod(chmodField.text)
          }
        }
      }

      // ---------- Propiedades ----------
      MouseArea {
        anchors.fill: parent
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
            text: root.propertiesEntry ? root.propertiesEntry.name : ""
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.bold: true
            color: Color.menu.text
            elide: Text.ElideMiddle
          }

          PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

          Repeater {
            model: [
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

      // ---------- Abrir con... ----------
      MouseArea {
        anchors.fill: parent
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

      // ---------- Conflicto al pegar ----------
      MouseArea {
        anchors.fill: parent
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
        visible: root.paletteOpen
        z: 25
        onClicked: root.closePalette()
      }

      BorderSurface {
        id: palette
        visible: root.paletteOpen
        width: Math.min(parent.width - 80, 420)
        height: Math.min(paletteColumn.implicitHeight + contentTopInset + contentBottomInset, 320)
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
            onVisibleChanged: if (visible) forceActiveFocus()
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
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.paletteIndex = Math.max(0, root.paletteIndex - 1)
                event.accepted = true
              }
            }
          }

          PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

          Repeater {
            model: root.paletteOpen ? root.filteredPaletteCommands() : []

            CursorSurface {
              required property var modelData
              required property int index
              readonly property bool cmdEnabled: modelData.enabled !== false
              width: paletteColumn.width
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

import QtQuick
import "../state"

// Marcadores, recientes, historial de renombrado en lote e iconos de
// unidades/red -- lógica de negocio que vivía en Omafiles.qml pese a no
// depender de casi nada (root + persistence, y tabOps/mountOps solo para
// las dos acciones de menú de unidades de red). Encontrado en la misma
// auditoría que logic/SortOps.qml y logic/FileTypeUtils.qml. Sin
// wrappers -- solo 12 sitios de llamada externos en total, repartidos en
// 3 ficheros (Sidebar.qml, OpenWithOps.qml, ConflictActions.qml).
Item {
  property Item root: null
  property Item persistence: null
  property Item tabOps: null
  property Item mountOps: null

  // ---------- Recientes / historial ----------
  // Llamado al abrir un fichero de verdad (enter()/launchWith(), NO al
  // navegar por carpetas -- para eso ya están el historial y las
  // pestañas). Mueve al principio si ya estaba, tope 20 entradas.
  function addRecent(path, name) {
    var next = BookmarksState.recentFiles.filter(function (r) { return r.path !== path })
    next.unshift({ path: path, name: name })
    if (next.length > 20) next = next.slice(0, 20)
    BookmarksState.recentFiles = next
    persistence.saveRecent()
  }

  function removeRecent(path) {
    BookmarksState.recentFiles = BookmarksState.recentFiles.filter(function (r) { return r.path !== path })
    persistence.saveRecent()
  }

  function clearRecent() {
    BookmarksState.recentFiles = []
    persistence.saveRecent()
  }

  function addBulkRenameHistory(pattern) {
    pattern = pattern.trim()
    if (!pattern) return
    var next = BookmarksState.bulkRenameHistory.filter(function (p) { return p !== pattern })
    next.unshift(pattern)
    if (next.length > 8) next = next.slice(0, 8)
    BookmarksState.bulkRenameHistory = next
    persistence.saveBulkRenameHistory()
  }

  // ---------- Marcadores / iconos de unidades ----------
  function removeBookmark(path) {
    BookmarksState.bookmarks = BookmarksState.bookmarks.filter(function (b) { return b.path !== path })
    persistence.saveBookmarks()
  }

  // type: "dir" (por defecto, compatible con marcadores guardados antes
  // de que existiera este campo -- todos eran de carpeta) o "file".
  function addBookmark(path, label, type) {
    if (BookmarksState.bookmarks.some(function (b) { return b.path === path })) return
    BookmarksState.bookmarks = BookmarksState.bookmarks.concat([{ label: label, path: path, type: type || "dir" }])
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
    return BookmarksState.bookmarks.some(function (b) { return b.path === path })
  }

  function iconForMount(mount) {
    if (mount.fstype === "iso9660") return root.iconFor({ type: "file", name: "x.iso" })
    return mount.removable ? "\u{F0553}" : "\u{F02CA}"
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
      { label: "Open in new tab", action: function () { tabOps.openInNewTab(mount.path) } },
      { label: "Disconnect", destructive: true, action: function () { mountOps.disconnectNetworkMount(mount) } }
    ]
  }
}

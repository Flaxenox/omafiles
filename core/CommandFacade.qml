import "../Utils.js" as Utils
import QtQuick
import "../state"

// CommandFacade -- fachada OPERATIVA de Omafiles (Fase 11.C, josema:
// completar el desacoplamiento del frontend). Contiene los constructores de
// menús/comandos de alto nivel que antes vivían en OmafilesContent: la
// paleta de comandos, el menú contextual de ítems/hueco vacío, las acciones
// de marcadores/puntos de montaje, abrir marcador/reciente y las migas de
// pan. Reciben los controladores que USAN por propiedad (no god object, no
// registry entero) y `root` para el estado + los wrappers de bajo nivel
// (navigateTo/enter/refresh/runAction/joinPath/emptyTrash/openTerminalHere)
// que siguen en OmafilesContent porque logic/ los llama por `root`.
//
// OmafilesContent mantiene delegados finos (function X(){ return
// commandFacade.X() }) para no tocar los ~decenas de sitios que llaman
// root.X()/hostRoot.X() desde paneles, diálogos y KeyboardShortcuts.
Item {
  id: commandFacade

  property Item root
  property var archiveActions
  property var bookmarkOps
  property var clipboardOps
  property var conflictActions
  property var deleteOps
  property var fileOps
  property var mountOps
  property var openWithOps
  property var propertiesLoader
  property var renameOps
  property var searchOps
  property var selectionOps
  property var sortOps
  property var tabOps

  function paletteCommands() {
    var hasSelection = SelectionState.selectedIndices.length > 0
    var entry = SelectionState.selectedIndices.length === 1 ? NavState.visibleEntries[SelectionState.selectedIndex] : null
    var cmds = [
      { label: "New folder", run: function () { renameOps.startNewFolder() } },
      { label: "New file", run: function () { renameOps.startNewFile() } },
      { label: "Rename", enabled: SelectionState.selectedIndices.length === 1, run: function () { renameOps.startRename(SelectionState.selectedIndex) } },
      { label: "Copy", enabled: hasSelection, run: function () { clipboardOps.copySelected() } },
      { label: "Cut", enabled: hasSelection, run: function () { clipboardOps.cutSelected() } },
      { label: "Copy path", enabled: hasSelection, run: function () { clipboardOps.copyPathFor(selectionOps.selectedEntries()) } },
      { label: "Paste", enabled: ClipboardState.clipboardPaths.length > 0, run: function () { conflictActions.paste() } },
      { label: "Delete", enabled: hasSelection, run: function () { deleteOps.requestDelete() } },
      { label: "Select all", run: function () { SelectionState.selectedIndices = Array.from({ length: NavState.visibleEntries.length }, function (_, i) { return i }) } },
      { label: "Select none", enabled: hasSelection, run: function () { selectionOps.selectNone() } },
      { label: "Invert selection", run: function () { selectionOps.invertSelection() } },
      { label: NavState.showHidden ? "Hide dotfiles" : "Show dotfiles", run: function () { searchOps.toggleHidden() } },
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
      { label: "Go to Home", run: function () { root.navigateTo(Paths.homeDir) } },
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
    if (NavState.currentPath === Paths.trashDir) {
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
      var fullPath = Utils.joinPath(NavState.currentPath, entry.name)
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
    var inTrash = NavState.currentPath === Paths.trashDir
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
        // Bug real: usar NavState.currentPath dentro del closure (en vez de
        // capturarlo aquí) leía la ruta en el momento del CLIC del menú,
        // no en el momento de abrirlo -- si el ratón pasaba por otro
        // panel de fondo mientras el menú seguía abierto (el
        // HoverHandler de cambio de pestaña no se desactiva solo por
        // haber un menú encima), la pestaña activa ya había cambiado y
        // "Open in new tab" abría la carpeta dentro de la carpeta
        // EQUIVOCADA. Capturado como variable local, coherente con como
        // ya lo hace paletteCommands() para el mismo caso.
        var dirFullPath = Utils.joinPath(NavState.currentPath, entries[0].name)
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
      var fullPath = Utils.joinPath(NavState.currentPath, entries[0].name)
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
    actions.push({ label: NavState.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { searchOps.toggleHidden() } })
    return actions
  }

  function emptyAreaActions() {
    var actions = []
    if (NavState.currentPath === Paths.trashDir) {
      actions.push({ label: "Empty trash", destructive: true, action: function () { root.emptyTrash() } })
    } else if (!ArchiveState.inArchive) {
      // Dentro de un archivo estas ya son no-op (cada función se
      // protege sola), pero se quitan de aquí para no enseñar entradas
      // muertas en el menú de hueco vacío.
      actions.push({ label: "New folder", action: function () { renameOps.startNewFolder() } })
      actions.push({ label: "New file", action: function () { renameOps.startNewFile() } })
      actions.push({ label: "Paste", enabled: ClipboardState.clipboardPaths.length > 0, action: function () { conflictActions.paste() } })
    }
    actions.push({ label: NavState.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { searchOps.toggleHidden() } })
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
      NavState.pendingSelectNames = [bookmark.path.substring(slash + 1)]
      root.navigateTo(slash > 0 ? bookmark.path.substring(0, slash) : "/")
    } else {
      root.navigateTo(bookmark.path)
    }
  }

  // Mismo mecanismo que openBookmark() para uno de tipo "file" -- todos
  // los recientes son ficheros (nunca carpetas, ver addRecent()).
  function openRecent(item) {
    var slash = item.path.lastIndexOf("/")
    NavState.pendingSelectNames = [item.name]
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
    if (bookmark.path === Paths.trashDir) {
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

  // Dentro de un comprimido, la ruta real (NavState.currentPath) no cambia --
  // solo se navega en archiveSubPath (ver enter()/goUp()/inArchive) -- así
  // que el breadcrumb tiene que construirse aparte para reflejarlo. Nadie
  // hace clic en un segmento individual (ver el Repeater real más abajo,
  // sin MouseArea propio a propósito), así que basta con que el ÚLTIMO
  // segmento tenga path === NavState.currentPath -- es lo único que usa la
  // plantilla compartida para decidir cuál pintar en negrita.
  function pathSegments() {
    if (!ArchiveState.inArchive) return root.pathSegmentsFor(NavState.currentPath)
    var segs = root.pathSegmentsFor(NavState.currentPath)
    var archiveName = ArchiveState.archivePath.substring(ArchiveState.archivePath.lastIndexOf("/") + 1)
    var parts = ArchiveState.archiveSubPath ? ArchiveState.archiveSubPath.split("/") : []
    var isLast = parts.length === 0
    segs.push({ label: archiveName, path: isLast ? NavState.currentPath : "" })
    for (var i = 0; i < parts.length; i++) {
      segs.push({ label: parts[i], path: (i === parts.length - 1) ? NavState.currentPath : "" })
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
}

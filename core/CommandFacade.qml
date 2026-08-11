import "../Utils.js" as Utils
import QtQuick
import "../state"

// CommandFacade -- OPERATIONAL facade of Omafiles (Phase 11.C, josema:
// complete the frontend decoupling). It contains the builders of
// high-level menus/commands that used to live in OmafilesContent: the
// command palette, the context menu of items/empty area, the
// bookmark/mount-point actions, open bookmark/recent and the breadcrumbs.
// They receive the controllers they USE by property (no god object, no
// whole registry) and `root` for the state + the low-level wrappers
// (navigateTo/enter/refresh/runAction/joinPath/emptyTrash/openTerminalHere)
// that stay in OmafilesContent because logic/ calls them via `root`.
//
// OmafilesContent keeps thin delegates (function X(){ return
// commandFacade.X() }) to avoid touching the ~dozens of sites that call
// root.X()/hostRoot.X() from panels, dialogs and KeyboardShortcuts.
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
  property var customActions

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
    // Real bug fixed here: unlike itemActions() (context
    // menu), this list had NO filter for ArchiveState.inArchive
    // -- "Add to bookmarks"/"Open in new tab" have no guard of their own (unlike
    // rename/copy/paste/etc., which do self-protect
    // inside their function) and mixed the real folder with the name of
    // an element INSIDE the archive, writing a broken path to
    // bookmarks.json without warning. The rest of the list is filtered here
    // too, not because it would break anything (those functions are already
    // no-ops inside an archive) but so as not to show dead entries.
    if (ArchiveState.inArchive) {
      var archiveBlocked = ["New folder", "New file", "Rename", "Copy", "Cut", "Copy path", "Paste", "Delete",
        "Compress to .zip", "Bulk rename...", "Permissions...", "Make link", "Properties",
        "Search", "Add to bookmarks", "Open in new tab", "Extract here", "Mount ISO", "Empty trash", "Restore"]
      cmds = cmds.filter(function (c) { return archiveBlocked.indexOf(c.label) < 0 })
    }
    // User actions (actions.toml). At the end of the list and never inside
    // an archive (their paths don't really exist on disk). They receive the
    // current selection to match their `context` and substitute placeholders.
    if (!ArchiveState.inArchive && customActions) {
      cmds = cmds.concat(customActions.paletteEntries(selectionOps.selectedEntries()))
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
    if (customActions) customActions.reload() // picks up changes to actions.toml without restarting
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
    if (customActions) customActions.reload() // picks up changes to actions.toml without restarting
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return []
    // Inside an archive only navigate/open is available -- nothing else
    // (rename/delete/chmod/compress/copy/link/bookmark) makes
    // sense over a path that doesn't really exist on disk.
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

    // Ordered by groups (before it was a flat list in the order the
    // functions had been added across several sessions, with no
    // criterion): 1) open, 2) clipboard, 3) organize (rename/
    // link/bookmark/compress/extract/mount), 4) permissions/delete/
    // properties, 5) view. Same group in single and multi-selection so
    // that the menu doesn't "jump" around when selecting a second item.
    if (!multi) {
      actions.push({ label: "Open", action: function () { root.enter(entries[0]) } })
      if (entries[0].type === "dir") {
        // Real bug: using NavState.currentPath inside the closure (instead of
        // capturing it here) read the path at the moment of the menu CLICK,
        // not at the moment of opening it -- if the mouse passed over another
        // background panel while the menu stayed open (the
        // tab-switch HoverHandler doesn't disable itself just for
        // having a menu on top), the active tab had already changed and
        // "Open in new tab" opened the folder inside the WRONG
        // folder. Captured as a local variable, consistent with how
        // paletteCommands() already does it for the same case.
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
    // User actions (actions.toml) that match this selection -- at the
    // end of the menu, after the native ones. inTrash/inArchive already exited earlier.
    if (customActions) {
      actions = actions.concat(customActions.menuActions(entries))
    }
    return actions
  }

  function emptyAreaActions() {
    var actions = []
    if (NavState.currentPath === Paths.trashDir) {
      actions.push({ label: "Empty trash", destructive: true, action: function () { root.emptyTrash() } })
    } else if (!ArchiveState.inArchive) {
      // Inside an archive these are already no-ops (each function
      // protects itself), but they are removed from here so as not to show
      // dead entries in the empty-area menu.
      actions.push({ label: "New folder", action: function () { renameOps.startNewFolder() } })
      actions.push({ label: "New file", action: function () { renameOps.startNewFile() } })
      actions.push({ label: "Paste", enabled: ClipboardState.clipboardPaths.length > 0, action: function () { conflictActions.paste() } })
    }
    actions.push({ label: NavState.showHidden ? "Hide dotfiles" : "Show dotfiles", action: function () { searchOps.toggleHidden() } })
    actions.push({ label: "Refresh", action: function () { root.refresh(); mountOps.refreshMounts(); mountOps.refreshNetworkMounts() } })
    return actions
  }

  // File bookmark: navigates to the folder that contains it and leaves it
  // selected -- it reuses pendingSelectNames, the same mechanism that
  // "Show in file manager" (dbus-filemanager1.py) already uses to
  // highlight a specific file on landing in a folder.
  function openBookmark(bookmark) {
    if (bookmark.type === "file") {
      var slash = bookmark.path.lastIndexOf("/")
      NavState.pendingSelectNames = [bookmark.path.substring(slash + 1)]
      root.navigateTo(slash > 0 ? bookmark.path.substring(0, slash) : "/")
    } else {
      root.navigateTo(bookmark.path)
    }
  }

  // Same mechanism as openBookmark() for a "file" type one -- all
  // recents are files (never folders, see addRecent()).
  function openRecent(item) {
    var slash = item.path.lastIndexOf("/")
    NavState.pendingSelectNames = [item.name]
    root.navigateTo(slash > 0 ? item.path.substring(0, slash) : "/")
  }

  // Double click on a recent -- unlike openRecent() (navigates and
  // selects), this actually opens it with the default app, just like
  // enter() does with a normal row. addRecent() bumps it back to the
  // top of the list, as if it had just been opened right now.
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
      // Trash is fixed -- josema removed it by mistake once and there is no
      // way to recover it except asking me by hand (defaultBookmarks
      // is only used the first time the app is opened, never again). Without
      // "Remove bookmark" for it, it can't be lost the same way again.
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

  // Inside an archive, the real path (NavState.currentPath) does not change --
  // only archiveSubPath is navigated (see enter()/goUp()/inArchive) -- so
  // the breadcrumb has to be built separately to reflect it. Nobody
  // clicks an individual segment (see the real Repeater below,
  // without its own MouseArea on purpose), so it's enough for the LAST
  // segment to have path === NavState.currentPath -- it's the only thing the
  // shared template uses to decide which one to paint in bold.
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

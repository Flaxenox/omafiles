# OmaFiles — Phase 34.2: Root API & Navigation Simplification Report

**Date:** 2026-08-14  
**Author:** Lead Software Architect & Maintainer  
**Scope:** Phase 34.2 (Root API & Navigation Simplification)  
**Status:** Completed & Verified (77/77 tests passing)

---

## 1. Executive Summary

Phase 34.2 focused on streamlining the root API surface of `OmafilesContent.qml`, eliminating massive prop-drilling down through `MainLayout.qml`, `DialogLayer.qml`, `ActiveFileList.qml`, and `KeyboardShortcuts.qml`, centralizing pure file type utility functions into `Utils.js`, and decoupling `CommandFacade.qml`.

### Key Outcomes:
1. **Pass-Through Wrappers Removed:** Eliminated ~39 thin delegation functions in `OmafilesContent.qml`, reducing the composition root from **589 lines down to 238 lines** (-59.6%).
2. **Prop-Drilling Reduced:** Injected cohesive `controllers`, `commandFacade`, and `dialogs` objects into `MainLayout.qml`, `DialogLayer.qml`, `ActiveFileList.qml`, and `KeyboardShortcuts.qml` instead of passing 25+ loose controller references.
3. **Pure Function Centralization:** Moved pure MIME/file type helpers (`extOf`, `iconFor`, `isImage`, `isVideo`, `isAudio`, `isPdf`) directly into [`Utils.js`](file:///home/josema/Projects/omafiles/Utils.js), deleting `logic/FileTypeUtils.qml`.
4. **CommandFacade Decoupled:** `CommandFacade.qml` now directly interfaces with `navController`, `actionEngine`, and `openProc` without bounce-backs through `root.*`.
5. **Modularity Preserved:** Maintained strict separation between cohesive modules (`DeleteOps`, `RenameOps`, `ClipboardOps`, `DragDropOps`, `FileOps`, `NavigationController`, `MountOps`, etc.). No file exceeded the 300-500 line threshold.
6. **Zero Regressions:** 77/77 headless self-check tests passing.

---

## 2. Changes by Component

### A. Composition Root ([`core/OmafilesContent.qml`](file:///home/josema/Projects/omafiles/core/OmafilesContent.qml))
- **Line count:** Shrunk from 589 lines to 238 lines (-351 lines).
- **Retained API:** Lifecycle functions (`open(payload)`, `close()`, `cancelPicker()`, `requestClose()`, `undoLast()`, `redoLast()`), state properties (`opened`, `loaded`, `hasBlockingOverlay`), signals (`closeRequested`, `pickerSubmitRequested`), and subsystem aliases (`controllers`, `actionEngine`, `navController`, `commandFacade`).
- **Removed Pass-Through Wrappers:**
  - Navigation: `refresh()`, `startDirWatch()`, `stopDirWatch()`, `navigateTo()`, `_goToPath()`, `navBack()`, `navForward()`, `openWithDefault()`, `enter()`, `goUp()`.
  - File types: `iconFor()`, `isImage()`, `isVideo()`, `isAudio()`, `isPdf()`.
  - Operations / Facade: `openTerminalHere()`, `cancelAction()`, `paletteCommands()`, `filteredPaletteCommands()`, `openPalette()`, `closePalette()`, `runPaletteCommand()`, `openContextMenu()`, `itemActions()`, `emptyAreaActions()`, `openBookmark()`, `openRecent()`, `launchRecent()`, `bookmarkActions()`, `mountActions()`, `pathSegments()`, `pathSegmentsFor()`, `emptyTrash()`.

### B. Main Visual Hierarchy ([`core/MainLayout.qml`](file:///home/josema/Projects/omafiles/core/MainLayout.qml))
- **Line count:** Shrunk from 452 lines to 306 lines (-146 lines).
- Replaced 27 injected controller and confirmation dialog properties with 4 structured properties:
  - `property var controllers`
  - `property var commandFacade`
  - `property var dialogs`
  - `property Timer gTimer`
- Child panels ([`panels/Sidebar.qml`](file:///home/josema/Projects/omafiles/panels/Sidebar.qml), [`panels/BackgroundPanel.qml`](file:///home/josema/Projects/omafiles/panels/BackgroundPanel.qml), [`shared/PathCompletionField.qml`](file:///home/josema/Projects/omafiles/shared/PathCompletionField.qml), [`panels/SearchBar.qml`](file:///home/josema/Projects/omafiles/panels/SearchBar.qml)) access controllers via `controllers.*` and commands via `commandFacade.*`.

### C. Modal Dialog Layer ([`core/DialogLayer.qml`](file:///home/josema/Projects/omafiles/core/DialogLayer.qml))
- **Line count:** Shrunk from 362 lines to 350 lines.
- Replaced 11 individual controller dependencies with `controllers` and `commandFacade`.
- Dialog callback handlers invoke native controllers directly (e.g. `controllers.deleteOps.confirmDelete()`, `controllers.renameOps.runPendingRename()`, `controllers.mountOps.commitConnectToServer()`).

### D. Active File List & Shortcuts ([`panels/ActiveFileList.qml`](file:///home/josema/Projects/omafiles/panels/ActiveFileList.qml) & [`logic/KeyboardShortcuts.qml`](file:///home/josema/Projects/omafiles/logic/KeyboardShortcuts.qml))
- **`ActiveFileList.qml`:** Shrunk from 447 lines to 304 lines (-143 lines).
- **`KeyboardShortcuts.qml`:** Shrunk from 257 lines to 231 lines (-26 lines).
- Cleaned up property boilerplate: both components now accept `hostControllers`, `hostCommandFacade`, and `hostDialogs` cleanly.
- Keyboard bindings dispatch directly to corresponding controllers.

### E. File Type Pure Utilities Centralization ([`Utils.js`](file:///home/josema/Projects/omafiles/Utils.js))
- Pure functions `extOf(name)`, `iconFor(entry)`, `isImage(entry)`, `isVideo(entry)`, `isAudio(entry)`, `isPdf(entry)` added to `Utils.js`.
- Deleted obsolete [`logic/FileTypeUtils.qml`](file:///home/josema/Projects/omafiles/logic/FileTypeUtils.qml) and unregistered from `ControllerRegistry.qml`.
- Updated call sites in `SortOps.qml`, `ArchiveActions.qml`, `BookmarkOps.qml`, `ConflictActions.qml`, `PreviewLoader.qml`, `Sidebar.qml`, `BackgroundPanel.qml`, and `FileListRow.qml`.

### F. Navigation Controller ([`logic/NavigationController.qml`](file:///home/josema/Projects/omafiles/logic/NavigationController.qml))
- Modular, well-bounded controller (340 lines, well below the 400-line ceiling).
- Handles history push/pop, directory listing cache synchronization, inotify directory watcher registration, and file execution dispatch.

---

## 3. Repository Line Statistics

```
 Utils.js                                     |  41 +++
 core/CommandFacade.qml                       | 126 +++------
 core/ControllerRegistry.qml                  |  17 +-
 core/DialogLayer.qml                         | 107 ++++---
 core/MainLayout.qml                          | 247 ++++-------------
 core/OmafilesContent.qml                     | 400 ++-------------------------
 logic/ArchiveActions.qml                     |  17 +-
 logic/BookmarkOps.qml                        |  40 +--
 logic/ConflictActions.qml                    |  15 +-
 logic/FileTypeUtils.qml                      |  46 ---
 logic/KeyboardShortcuts.qml                  | 155 +++++------
 logic/PreviewLoader.qml                      |  31 +--
 logic/SortOps.qml                            |   7 +-
 panels/ActiveFileList.qml                    | 192 ++-----------
 panels/BackgroundPanel.qml                   |  28 +-
 panels/FileListRow.qml                       |  18 +-
 panels/Sidebar.qml                           |  21 +-
 shared/PathCompletionField.qml               |   7 +-
 src/selfcheck/checks/CheckInfrastructure.qml |  14 +-
 19 files changed, 349 insertions(+), 1180 deletions(-)
```

**Net impact:** **-831 lines of boilerplate deleted.**

---

## 4. Verification Results

```bash
── omafiles --selfcheck · fixtures in /home/josema/.cache/omafiles-selfcheck-nheqMX ──
[PASS] Backend module loaded (Omafiles.Backend) (0ms) — HOME=/home/josema
[PASS] Backend.UDisksWatcher reactive backend (0ms) — available=true
[PASS] Backend.FolderCounter counts a directory (async, Fase 23) (1ms) — n=4 (expected 4)
[PASS] Item count smart formatting (0ms)
[PASS] Composition root creates (OmafilesContent) (76ms) — main tree instantiated
[PASS] Composition root API surface (open/close/facade) (0ms)
[PASS] NavState is source of truth (1ms)
[PASS] TabsState defaults (0ms) — tabs=1 active=0
[PASS] ControllerRegistry + CommandFacade wiring (0ms) — palette=35 emptyArea=5 segments=6
[PASS] AppBindings loaded (no side effects under selfcheck) (0ms) — AppBindings instantiated without self-registration
[PASS] Backend.JsonStore write/read round-trip (15ms)
[PASS] Backend.DirectoryModel list + natural order (0ms) — order=[sub, alpha.txt, beta.txt, gamma.txt]
[PASS] QFileSystemWatcher create event (1ms) — directoryChanged after creating subfolder
[PASS] Backend.ThumbnailProvider PNG (4ms)
[PASS] Backend.ThumbnailProvider PDF (qpdf plugin) (6ms)
[PASS] Thumbnail cache key is canonical SHA-1 (B1) (0ms) — cacheKey=244adfd729888c0a4499250ebb2e9f41d7243600
[PASS] Thumbnail cache pruning: orphans, safety, age, size (O1) (2ms) — orphan+safety+age+size OK
[PASS] Backend.PreviewProvider text (0ms) — utf-8, 3 lines
[PASS] Backend.PreviewProvider info (0ms) — keys=[executable,mime,mtime,name,path,permissions,readable,size,writable]
[PASS] Backend.FileOperations mkdir (1ms)
[PASS] Backend.FileOperations rename (0ms)
[PASS] Backend.FileOperations copy (0ms)
[PASS] Backend.FileOperations copy overwrite (replace) (0ms) — destination replaced
[PASS] Backend.FileOperations copy directory (recursive) (1ms) — 4 entries copied
[PASS] Backend.FileOperations copy symlink preserved (0ms) — copied as a link
[PASS] Backend.FileOperations copy preserves permissions (1ms) — src=rw- dst=rw-
[PASS] ActionEngine native copy runner (paste/drop path) (2ms) — runNativeCopy OK
[PASS] Backend.FileOperations move overwrite (replace) (1ms) — replaced, source consumed
[PASS] Backend.FileOperations move directory (recursive) (1ms) — tree moved, source gone
[PASS] Backend.FileOperations move symlink preserved (0ms) — moved as a link
[PASS] Backend.FileOperations move cross-filesystem (best-effort /tmp) (1ms) — dest ok, source gone
[PASS] Copy/move cancellation (cooperative, source safe) (0ms) — cancelled, source intact
[PASS] ActionEngine native move runner + undo (paste/drop path) (1ms) — moved and undone
[PASS] Backend.FileOperations delete directory (recursive) (1ms) — tree deleted
[PASS] Backend.FileOperations delete symlink (target preserved) (0ms) — link deleted, target intact
[PASS] Backend.FileOperations delete read-only (permission failure) (0ms) — error reported
[PASS] Backend.FileOperations delete missing (error vs ignoreMissing) (0ms) — error if missing, ok with ignoreMissing
[PASS] Backend.FileOperations delete cancellation (recursive tree) (0ms) — error=cancelled
[PASS] ActionEngine native remove runner (delete path) (0ms) — runNativeRemove OK
[PASS] Trash removes item from source (2ms) — sent and restored
[PASS] ActionEngine trash+restore end-to-end (frontend wiring) (2ms) — trash+restore via ActionEngine OK
[PASS] Trash + restore directory (round-trip) (2ms) — tree restored: 4
[PASS] Trash + restore symlink (round-trip) (2ms) — symlink restored as a link
[PASS] Trash + restore Unicode name (round-trip) (2ms) — unicode round-trip OK
[PASS] Trash collision (restore both by orig path) (2ms) — collision resolved, both restored
[PASS] Restore collision (destination exists -> error) (5ms) — error if destination exists
[PASS] Restore recreates missing parent (2ms) — parent recreated and file restored
[PASS] ActionEngine native trash runner + undo (delete-to-trash path) (1ms) — sent and restored by undo
[PASS] Conflict detection: existingPaths (file/dir/symlink) (1ms) — detected 3/3
[PASS] Copy conflict overwrite (directory replaces) (1ms) — dir replaced: 4 entries
[PASS] Copy conflict without overwrite errors (skip semantics) (0ms) — error: destination already exists
[PASS] Move conflict without overwrite errors (skip semantics) (0ms) — error: destination already exists
[PASS] Conflict overwrite replaces symlink dest (1ms) — symlink replaced by file
[PASS] Copy progress (byte-accurate, reaches total) (21ms) — events=33 last=33554432/33554432
[PASS] Move cross-fs progress (best-effort) (45ms) — cross-fs progress 33 events
[PASS] Copy cancellation leaves no partial file (0ms) — no partial residue
[PASS] Copy cancellation leaves no partial directory (1ms) — partial tree cleaned up
[PASS] Move cross-fs cancellation: source intact, no partial (24ms) — cross-fs cancelled: src=true no partial=true
[PASS] Undo + redo move (full cycle) (2ms) — undo and redo OK
[PASS] Undo + redo trash (full cycle) (3ms) — undo and redo trash OK
[PASS] Undo sequence (LIFO: reverts the last one first) (2ms) — LIFO OK: B and then A
[PASS] Cancel then undo (cancellation doesn't alter the stack) (1ms) — undo after cancellation reverts the move
[PASS] Undo registry consistency (UndoState stacks) (2ms) — push/undo/redo stacks: true/true/true
[PASS] Backend.FileOperations move (1ms)
[PASS] Backend.FileOperations remove (1ms)
[PASS] Backend.FileOperations trash + restore (net-zero) (7ms) — restored to its place
[PASS] Background panel refreshes on content change (non-active tab) (31ms) — reflected change via refreshTick
[PASS] Native recursive search: name, depth, hidden filter (1ms) — name+depth+hidden OK
[PASS] Native trash listing: trashRoots + trashInfo (3ms) — trashRoots+trashInfo OK
[PASS] Native network mounts listing returns a list (1ms) — Backend.NetworkMounts.list() -> 0 entries
[PASS] Conflict detection sees a broken symlink (BUG-01) (1ms) — broken symlink detected as a conflict
[PASS] empty-trash.sh empties an isolated home trash (BUG-02) (12ms) — exit=0 remaining items=0
[PASS] list-archive.sh lists a tar fixture (BUG-02) (7ms) — listed 4 top-level entries
[PASS] mount-iso.sh fails safely on a bad path (BUG-02) (10ms) — exit=1 stdout=''
[PASS] open-with-list.sh returns valid TSV (BUG-02) (28ms) — exit=0 lines=2
[PASS] Properties/chmod handle a huge selection without ARG_MAX (BUG-03) (20ms) — native OK (2000 paths)
[PASS] tar extracts a member whose name starts with '-' (BUG-05) (9ms) — new: exit=0 out='contenido05'

── selfcheck: 77 passed, 0 failed, 77 total ──
```

---

## 5. Conclusion

Phase 34.2 successfully eliminated large swathes of boilerplate, simplified prop passing across the UI tree, and made the composition root legible and maintainable without any functional regression or breach of line count boundaries.

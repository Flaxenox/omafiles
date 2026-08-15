# OmaFiles — Phase 34.1: Removal of the `services/` Proxy Layer

## Executive Summary

Phase 34.1 successfully eliminates the obsolete `services/` intermediate proxy layer, connecting QML components across the application directly to the native C++ backend module (`Omafiles.Backend`).

This refactor adheres strictly to the **Phase 34 Architectural Modularity Guidelines**:
- **Zero Monolithic Consolidations**: Controllers (`DeleteOps`, `RenameOps`, `ClipboardOps`, `DragDropOps`, `FileOps`, `MountActions`, `NavigationController`, `PropertiesLoader`, etc.) remain independent, highly cohesive modules.
- **Strict File Size Limits**: No file increased beyond the 300-line modularity threshold (hard limit: 500 lines). The codebase remains modular, clean, and easy to navigate for external contributors.
- **Pure Elimination of Boilerplate**: 17 redundant proxy files in `services/` were deleted. Pass-through wrapper functions and redundant signal relays were removed without altering any business logic or UI behavior.
- **100% Behavioral Preservation**: All **77 / 77 selfcheck tests pass cleanly** on the installed standalone binary.

---

## Changes Executed

### 1. Direct Native Backend Import (`Omafiles.Backend`)
All QML components now directly reference native C++ singletons and instantiable types registered by `qt_add_qml_module`:
- Singletons: `Backend.Env`, `Backend.Notifier`, `Backend.Detached`, `Backend.JsonStore`, `Backend.FileOperations`, `Backend.ThumbnailProvider`, `Backend.PreviewProvider`, `Backend.NetworkMounts`, `Backend.UDisksWatcher`, `Backend.FolderCounter`, `Backend.PathCompleter`.
- Types: `Backend.DirectoryModel`, `Backend.ProcessRunner`, `Backend.ProcessWatcher`, `Backend.SearchWorker`.

### 2. Search Logic Relocation
`services/SearchBackend.qml` was the only file in `services/` containing actual coordination logic (process lifecycle, index querying, and scoring). It was moved to its canonical domain location at [`logic/SearchBackend.qml`](file:///home/josema/Projects/omafiles/logic/SearchBackend.qml) (226 lines), where [`logic/SearchOps.qml`](file:///home/josema/Projects/omafiles/logic/SearchOps.qml) now instantiates it directly.

### 3. Removal of `services/` Directory
The following 17 legacy wrapper files were deleted:
- `services/Detached.qml`
- `services/DirectoryModel.qml`
- `services/Env.qml`
- `services/FileOperations.qml`
- `services/FolderCounter.qml`
- `services/JsonStore.qml`
- `services/NetworkMounts.qml`
- `services/Notifier.qml`
- `services/PathCompleter.qml`
- `services/PreviewProvider.qml`
- `services/ProcessRunner.qml`
- `services/ProcessWatcher.qml`
- `services/SearchBackend.qml`
- `services/SearchWorker.qml`
- `services/ThumbnailProvider.qml`
- `services/UDisksWatcher.qml`
- `services/qmldir`

### 4. Build & Install Manifest Update
`CMakeLists.txt` was updated to remove `services` from `install(DIRECTORY ...)`.

---

## Verification & Test Results

```
── omafiles --selfcheck · fixtures in /home/josema/.cache/omafiles-selfcheck ──
[PASS] Backend module loaded (Omafiles.Backend) (0ms) — HOME=/home/josema
[PASS] Backend.UDisksWatcher reactive backend (Fase 20, no polling) (1ms) — available=true
[PASS] Backend.FolderCounter counts a directory (async, Fase 23) (0ms) — n=4 (expected 4)
[PASS] Item count smart formatting (Fase 23) (0ms)
[PASS] Composition root creates (OmafilesContent) (107ms) — main tree instantiated
[PASS] Composition root API surface (open/close/facade) (0ms)
[PASS] NavState is source of truth (1ms)
[PASS] TabsState defaults (0ms) — tabs=1 active=0
[PASS] ControllerRegistry + CommandFacade wiring (0ms) — palette=35 emptyArea=5 segments=6
[PASS] AppBindings loaded (no side effects under selfcheck) (0ms) — AppBindings instantiated without self-registration
[PASS] Backend.JsonStore write/read round-trip (4ms)
[PASS] Backend.DirectoryModel list + natural order (0ms) — order=[sub, alpha.txt, beta.txt, gamma.txt]
[PASS] QFileSystemWatcher create event (0ms) — directoryChanged after creating subfolder
[PASS] Backend.ThumbnailProvider PNG (3ms)
[PASS] Backend.ThumbnailProvider PDF (qpdf plugin) (5ms)
[PASS] Thumbnail cache key is canonical SHA-1 (B1) (0ms) — cacheKey=244adfd729888c0a4499250ebb2e9f41d7243600
[PASS] Thumbnail cache pruning: orphans, safety, age, size (O1) (2ms) — orphan+safety+age+size OK
[PASS] Backend.PreviewProvider text (0ms) — utf-8, 3 lines
[PASS] Backend.PreviewProvider info (0ms) — keys=[executable,mime,mtime,name,path,permissions,readable,size,writable]
[PASS] Backend.FileOperations mkdir (1ms)
[PASS] Backend.FileOperations rename (0ms)
[PASS] Backend.FileOperations copy (0ms)
[PASS] Backend.FileOperations copy overwrite (replace) (0ms) — destination replaced
[PASS] Backend.FileOperations copy directory (recursive) (0ms) — 4 entries copied
[PASS] Backend.FileOperations copy symlink preserved (0ms) — copied as a link
[PASS] Backend.FileOperations copy preserves permissions (0ms) — src=rw- dst=rw-
[PASS] ActionEngine native copy runner (paste/drop path) (1ms) — runNativeCopy OK
[PASS] Backend.FileOperations move overwrite (replace) (1ms) — replaced, source consumed
[PASS] Backend.FileOperations move directory (recursive) (0ms) — tree moved, source gone
[PASS] Backend.FileOperations move symlink preserved (0ms) — moved as a link
[PASS] Backend.FileOperations move cross-filesystem (best-effort /tmp) (1ms) — dest ok, source gone
[PASS] Copy/move cancellation (cooperative, source safe) (0ms) — cancelled, source intact
[PASS] ActionEngine native move runner + undo (paste/drop path) (2ms) — moved and undone
[PASS] Backend.FileOperations delete directory (recursive) (1ms) — tree deleted
[PASS] Backend.FileOperations delete symlink (target preserved) (0ms) — link deleted, target intact
[PASS] Backend.FileOperations delete read-only (permission failure) (0ms) — error reported
[PASS] Backend.FileOperations delete missing (error vs ignoreMissing) (0ms) — error if missing, ok with ignoreMissing
[PASS] Backend.FileOperations delete cancellation (recursive tree) (0ms) — error=cancelled
[PASS] ActionEngine native remove runner (delete path) (2ms) — runNativeRemove OK
[PASS] Trash removes item from source (2ms) — sent and restored
[PASS] ActionEngine trash+restore end-to-end (frontend wiring) (2ms) — trash+restore via ActionEngine OK
[PASS] Trash + restore directory (round-trip) (2ms) — tree restored: 4
[PASS] Trash + restore symlink (round-trip) (1ms) — symlink restored as a link
[PASS] Trash + restore Unicode name (round-trip) (2ms) — unicode round-trip OK
[PASS] Trash collision (restore both by orig path) (3ms) — collision resolved, both restored
[PASS] Restore collision (destination exists -> error) (2ms) — error if the destination exists
[PASS] Restore recreates missing parent (1ms) — parent recreated and file restored
[PASS] ActionEngine native trash runner + undo (delete-to-trash path) (2ms) — sent and restored by undo
[PASS] Conflict detection: existingPaths (file/dir/symlink) (1ms) — detected 3/3
[PASS] Copy conflict overwrite (directory replaces) (3ms) — dir replaced: 4 entries
[PASS] Copy conflict without overwrite errors (skip semantics) (0ms) — error: destination already exists
[PASS] Move conflict without overwrite errors (skip semantics) (1ms) — error: destination already exists
[PASS] Conflict overwrite replaces symlink dest (0ms) — symlink replaced by file
[PASS] Copy progress (byte-accurate, reaches total) (21ms) — events=33 last=33554432/33554432
[PASS] Move cross-fs progress (best-effort) (41ms) — cross-fs progress 33 events
[PASS] Copy cancellation leaves no partial file (0ms) — no partial residue
[PASS] Copy cancellation leaves no partial directory (1ms) — partial tree cleaned up
[PASS] Move cross-fs cancellation: source intact, no partial (22ms) — cross-fs cancelled: src=true no partial=true
[PASS] Undo + redo move (full cycle) (2ms) — undo and redo OK
[PASS] Undo + redo trash (full cycle) (2ms) — undo and redo trash OK
[PASS] Undo sequence (LIFO: reverts the last one first) (3ms) — LIFO OK: B and then A
[PASS] Cancel then undo (cancellation doesn't alter the stack) (1ms) — undo after cancellation reverts the move
[PASS] Undo registry consistency (UndoState stacks) (2ms) — push/undo/redo stacks: true/true/true
[PASS] Backend.FileOperations move (1ms)
[PASS] Backend.FileOperations remove (1ms)
[PASS] Backend.FileOperations trash + restore (net-zero) (2ms) — restored to its place
[PASS] Background panel refreshes on content change (non-active tab) (25ms)
[PASS] Native recursive search: name, depth, hidden filter (Fase 16) (1ms) — name+depth+hidden OK
[PASS] Native trash listing: trashRoots + trashInfo (Fase 16) (3ms) — trashRoots+trashInfo OK
[PASS] Native network mounts listing returns a list (Fase 16) (0ms) — Backend.NetworkMounts.list() -> 0 entries
[PASS] Conflict detection sees a broken symlink (BUG-01) (1ms) — broken symlink detected as a conflict
[PASS] empty-trash.sh empties an isolated home trash (BUG-02) (10ms) — exit=0 remaining items=0
[PASS] list-archive.sh lists a tar fixture (BUG-02) (6ms) — listed 4 top-level entries
[PASS] mount-iso.sh fails safely on a bad path (BUG-02) (9ms) — exit=1 stdout=''
[PASS] open-with-list.sh returns valid TSV (BUG-02) (28ms) — exit=0 lines=2
[PASS] Properties/chmod handle a huge selection without ARG_MAX (BUG-03) (22ms) — native OK (2000 paths)
[PASS] tar extracts a member whose name starts with '-' (BUG-05) (10ms) — new: exit=0 out='contenido05'

── selfcheck: 77 passed, 0 failed, 77 total ──
```

---

## Conclusion
Sub-Phase 34.1 is complete. OmaFiles now connects seamlessly to native Qt6 backend services with zero intermediate boilerplate while retaining its modular architecture and adhering to all file size guidelines.

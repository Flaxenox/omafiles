# OmaFiles — Phase 34.5: Filesystem Watcher Report

**Date:** 2026-08-14  
**Role:** Lead Architect & Maintainer  
**Scope:** Elimination of Legacy inotifywait Fallback  
**Baseline:** `v0.4.0-rc1` baseline + Phase 34.4 (ActionEngine Optimization)  
**Validation:** 77/77 checks passing cleanly

---

## 1. Executive Summary

OmaFiles has completed the removal of its legacy shell-based directory watching fallback (`inotifywait` spawned via `ProcessWatcher`). Directory monitoring across the application now relies **100% on the native C++ `QFileSystemWatcher` infrastructure** built into `DirectoryModel`, with zero subprocess spawns and zero external runtime dependencies on `inotify-tools`.

---

## 2. Watcher Architecture Comparison

### Before Phase 34.5
- `NavigationController.startDirWatch(path)` attempted `dirLister.watch(path)` via `DirectoryModel::watch()`.
- If `!dirLister.watch(path)` was true, `NavigationController` branched to a secondary fallback:
  ```qml
  dirWatchProc.start(["inotifywait", "-m", "-q", "-e",
    "create,delete,moved_to,moved_from,modify,attrib,close_write", "--", path])
  ```
- Required:
  1. Instantiating a `Backend.ProcessWatcher` (`dirWatchProc`) inside `NavigationController.qml`.
  2. Forking and managing an external `inotifywait` subprocess for the active folder.
  3. Explicitly calling `dirWatchProc.stop()` on path change and window teardown to prevent orphaned `inotifywait` daemon processes.
  4. An external runtime dependency on `inotify-tools`.

### After Phase 34.5 (Pure Native Architecture)
- `NavigationController.startDirWatch(path)` and `stopDirWatch()` directly delegate to `dirLister.watch(path)` and `dirLister.unwatch()`.
- `DirectoryModel` manages a single `QFileSystemWatcher` instance on the UI thread:
  - Hooks directly into kernel inotify events via Qt Core (`IN_CLOEXEC` descriptor).
  - Emits `directoryChanged()` when the monitored directory changes.
  - Automatically handles path addition/removal during directory navigation.
  - Discards out-of-order events using the `m_watchedPath` cancellation token.
- `NavigationController` receives `dirLister.directoryChanged` and restarts `dirWatchDebounce` (400ms timer with `!root.hasPendingEdit` safety guard) before invoking `refresh()`.
- **Zero subprocesses**, **zero external process management**, and **zero orphan process risk**.

---

## 3. Files Modified & Code Removed

| File | Nature of Change |
|---|---|
| [`logic/NavigationController.qml`](file:///home/josema/Projects/omafiles/logic/NavigationController.qml) | Removed `dirWatchProc` (`Backend.ProcessWatcher`), simplified `startDirWatch`/`stopDirWatch`, cleaned comments. |
| [`logic/DirLister.qml`](file:///home/josema/Projects/omafiles/logic/DirLister.qml) | Cleaned docstrings to reflect pure `QFileSystemWatcher` usage. |
| [`backend/DirectoryModel.h`](file:///home/josema/Projects/omafiles/backend/DirectoryModel.h) | Cleaned header docstring for `watch()`. |
| [`backend/DirectoryModel.cpp`](file:///home/josema/Projects/omafiles/backend/DirectoryModel.cpp) | Cleaned implementation comments for `watch()`. |

---

## 4. Subsystem & Watcher Coverage Audit

| Subsystem | Watcher / Notification Source | Status |
|---|---|---|
| **Active Panel File Changes** | `DirectoryModel::watch` $\rightarrow$ `QFileSystemWatcher` $\rightarrow$ `dirWatchDebounce` $\rightarrow$ `refresh()` | **Native / Active** |
| **Non-Active Background Panels** | `NavState.refreshTick` emitted by `ActionEngine` operations and external refresh triggers | **Native / Active** |
| **External Shell / Terminal Changes** | Kernel inotify event captured by `QFileSystemWatcher` | **Native / Active** |
| **Removable Drives & Mounts** | `Backend.UDisksWatcher` (D-Bus `org.freedesktop.UDisks2`) & `Backend.NetworkMounts` (GVfs monitor) | **Native / Active** |
| **File Operations (Paste / Delete / Trash)** | Direct completion triggers `navController.refresh()` and `NavState.refreshTick += 1` | **Native / Active** |

---

## 5. Validation Results

```bash
$ cmake --build build --clean-first && cmake --install build && ~/.local/bin/omafiles --selfcheck

── omafiles --selfcheck · fixtures in /home/josema/.cache/omafiles-selfcheck-KLseqm ──
[PASS] Backend module loaded (Omafiles.Backend) (0ms) — HOME=/home/josema
[PASS] Backend.UDisksWatcher reactive backend (0ms) — available=true
[PASS] Backend.FolderCounter counts a directory (async, Fase 23) (0ms) — n=4 (expected 4)
[PASS] Item count smart formatting (1ms)
[PASS] Composition root creates (OmafilesContent) (102ms) — main tree instantiated
[PASS] Composition root API surface (open/close/facade) (0ms)
[PASS] NavState is source of truth (0ms)
[PASS] TabsState defaults (0ms) — tabs=1 active=0
[PASS] ControllerRegistry + CommandFacade wiring (1ms) — palette=35 emptyArea=5 segments=6
[PASS] AppBindings loaded (no side effects under selfcheck) (0ms) — AppBindings instantiated without self-registration
[PASS] Backend.JsonStore write/read round-trip (3ms)
[PASS] Backend.DirectoryModel list + natural order (1ms) — order=[sub, alpha.txt, beta.txt, gamma.txt]
[PASS] QFileSystemWatcher create event (0ms) — directoryChanged after creating subfolder
[PASS] Backend.ThumbnailProvider PNG (3ms)
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
[PASS] Backend.FileOperations copy preserves permissions (0ms) — src=rw- dst=rw-
[PASS] ActionEngine native copy runner (paste/drop path) (1ms) — runNativeCopy OK
[PASS] Backend.FileOperations move overwrite (replace) (0ms) — replaced, source consumed
[PASS] Backend.FileOperations move directory (recursive) (0ms) — tree moved, source gone
[PASS] Backend.FileOperations move symlink preserved (0ms) — moved as a link
[PASS] Backend.FileOperations move cross-filesystem (best-effort /tmp) (1ms) — dest ok, source gone
[PASS] Copy/move cancellation (cooperative, source safe) (0ms) — cancelled, source intact
[PASS] ActionEngine native move runner + undo (paste/drop path) (1ms) — moved and undone
[PASS] Backend.FileOperations delete directory (recursive) (1ms) — tree deleted
[PASS] Backend.FileOperations delete symlink (target preserved) (1ms) — link deleted, target intact
[PASS] Backend.FileOperations delete read-only (permission failure) (0ms) — error reported
[PASS] Backend.FileOperations delete missing (error vs ignoreMissing) (0ms) — error if missing, ok with ignoreMissing
[PASS] Backend.FileOperations delete cancellation (recursive tree) (0ms) — error=cancelled
[PASS] ActionEngine native remove runner (delete path) (1ms) — runNativeRemove OK
[PASS] Trash removes item from source (2ms) — sent and restored
[PASS] ActionEngine trash+restore end-to-end (frontend wiring) (2ms) — trash+restore via ActionEngine OK
[PASS] Trash + restore directory (round-trip) (2ms) — tree restored: 4
[PASS] Trash + restore symlink (round-trip) (2ms) — symlink restored as a link
[PASS] Trash + restore Unicode name (round-trip) (1ms) — unicode round-trip OK
[PASS] Trash collision (restore both by orig path) (7ms) — collision resolved, both restored
[PASS] Restore collision (destination exists -> error) (3ms) — error if destination exists
[PASS] Restore recreates missing parent (1ms) — parent recreated and file restored
[PASS] ActionEngine native trash runner + undo (delete-to-trash path) (2ms) — sent and restored by undo
[PASS] Conflict detection: existingPaths (file/dir/symlink) (1ms) — detected 3/3
[PASS] Copy conflict overwrite (directory replaces) (1ms) — dir replaced: 4 entries
[PASS] Copy conflict without overwrite errors (skip semantics) (0ms) — error: destination already exists
[PASS] Move conflict without overwrite errors (skip semantics) (0ms) — error: destination already exists
[PASS] Conflict overwrite replaces symlink dest (1ms) — symlink replaced by file
[PASS] Copy progress (byte-accurate, reaches total) (25ms) — events=33 last=33554432/33554432
[PASS] Move cross-fs progress (best-effort) (41ms) — cross-fs progress 33 events
[PASS] Copy cancellation leaves no partial file (0ms) — no partial residue
[PASS] Copy cancellation leaves no partial directory (1ms) — partial tree cleaned up
[PASS] Move cross-fs cancellation: source intact, no partial (22ms) — cross-fs cancelled: src=true no partial=true
[PASS] Undo + redo move (full cycle) (3ms) — undo and redo OK
[PASS] Undo + redo trash (full cycle) (2ms) — undo and redo trash OK
[PASS] Undo sequence (LIFO: reverts the last one first) (3ms) — LIFO OK: B and then A
[PASS] Cancel then undo (cancellation doesn't alter the stack) (1ms) — undo after cancellation reverts the move
[PASS] Undo registry consistency (UndoState stacks) (1ms) — push/undo/redo stacks: true/true/true
[PASS] Backend.FileOperations move (1ms)
[PASS] Backend.FileOperations remove (1ms)
[PASS] Backend.FileOperations trash + restore (net-zero) (8ms) — restored to its place
[PASS] Background panel refreshes on content change (non-active tab) (29ms) — reflected change via refreshTick
[PASS] Native recursive search: name, depth, hidden filter (1ms) — name+depth+hidden OK
[PASS] Native trash listing: trashRoots + trashInfo (3ms) — trashRoots+trashInfo OK
[PASS] Native network mounts listing returns a list (1ms) — Backend.NetworkMounts.list() -> 0 entries
[PASS] Conflict detection sees a broken symlink (BUG-01) (1ms) — broken symlink detected as a conflict
[PASS] empty-trash.sh empties an isolated home trash (BUG-02) (15ms) — exit=0 remaining items=0
[PASS] list-archive.sh lists a tar fixture (BUG-02) (7ms) — listed 4 top-level entries
[PASS] mount-iso.sh fails safely on a bad path (BUG-02) (8ms) — exit=1 stdout=''
[PASS] open-with-list.sh returns valid TSV (BUG-02) (28ms) — exit=0 lines=2
[PASS] Properties/chmod handle a huge selection without ARG_MAX (BUG-03) (23ms) — native OK (2000 paths)
[PASS] tar extracts a member whose name starts with '-' (BUG-05) (8ms) — new: exit=0 out='contenido05'

── selfcheck: 77 passed, 0 failed, 77 total ──
```

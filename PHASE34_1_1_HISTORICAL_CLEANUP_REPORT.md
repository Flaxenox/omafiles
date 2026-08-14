# OmaFiles — Phase 34.1.1: Historical Cleanup Report

## Executive Summary

Phase 34.1.1 completed a comprehensive cleanup of obsolete historical comments, phase annotations, and references to retired architectures across the OmaFiles codebase. 

No executable code or runtime behavior was altered. All **77 / 77 selfcheck tests continue to pass cleanly (0 failures)**.

---

## 1. Classification & Audit of Historical References

Every reference identified during the audit was reviewed and handled according to the maintainer guidelines:

| Category | Description | Action Taken |
| :--- | :--- | :--- |
| **Phase / Author Annotations** | Historical phase tags such as `(Phase 23, josema)`, `(Phase 10.A)`, `(Phase 29)`, `(Phase 5.C)`, etc. | **Deleted** across all source files |
| **Retired `services/` Layer** | Comments referencing `services/FileOperations.qml`, `services/ProcessRunner`, etc. | **Updated** to direct `Omafiles.Backend` or removed |
| **QuickShell Assumptions** | Comments explaining old `Quickshell.Io.Process`, `Quickshell.execDetached`, `FloatingWindow`, or shell environment workarounds | **Deleted** or replaced with concise Qt6 QProcess / QML descriptions |
| **Omarchy Plugin Assumptions** | References to old plugin directory structures (`~/.config/omarchy/plugins/omafiles`) and plugin summon lifecycle | **Deleted** or modernized to canonical XDG paths (`~/.config/omafiles`) |
| **Legacy Wrapper Notes** | Comments discussing previous multi-layered wrappers that have since been simplified | **Deleted** |
| **Current Architectural Decisions** | Active descriptions of async I/O, inotify debounce, natural sort, portal D-Bus semantics, and memory boundaries | **Kept intact** |
| **Historical Architectural Context** | High-level evolution from plugin to standalone Qt6 application and retirement of `services/` | **Moved to `ARCHITECTURE.md` (Historical Archival Notes)** |

---

## 2. File-by-File Summary of Cleanups

### C++ Backend (`backend/` & `main.cpp`)
- [`backend/Detached.h`](file:///home/josema/Projects/omafiles/backend/Detached.h) & [`backend/Detached.cpp`](file:///home/josema/Projects/omafiles/backend/Detached.cpp): Cleaned Quickshell execution comparisons; streamlined to describe `QProcess::startDetached`.
- [`backend/Env.h`](file:///home/josema/Projects/omafiles/backend/Env.h): Removed obsolete Quickshell environment notes; documented direct environment access.
- [`backend/Notifier.h`](file:///home/josema/Projects/omafiles/backend/Notifier.h) & [`backend/Notifier.cpp`](file:///home/josema/Projects/omafiles/backend/Notifier.cpp): Removed legacy script construction notes.
- [`backend/ProcessRunner.h`](file:///home/josema/Projects/omafiles/backend/ProcessRunner.h) & [`backend/ProcessWatcher.h`](file:///home/josema/Projects/omafiles/backend/ProcessWatcher.h): Removed `services/` and `Quickshell.Io` comparisons; documented native asynchronous process management.
- [`backend/DirectoryModel.h`](file:///home/josema/Projects/omafiles/backend/DirectoryModel.h) & [`backend/DirectoryModel.cpp`](file:///home/josema/Projects/omafiles/backend/DirectoryModel.cpp): Removed adapter and phase notes; preserved sorting and syscall optimization notes.
- [`backend/JsonStore.h`](file:///home/josema/Projects/omafiles/backend/JsonStore.h): Removed retired rule and adapter references.
- [`backend/NetworkMounts.h`](file:///home/josema/Projects/omafiles/backend/NetworkMounts.h), [`backend/PathCompleter.h`](file:///home/josema/Projects/omafiles/backend/PathCompleter.h), [`backend/PreviewProvider.h`](file:///home/josema/Projects/omafiles/backend/PreviewProvider.h), [`backend/ThumbnailProvider.h`](file:///home/josema/Projects/omafiles/backend/ThumbnailProvider.h), [`backend/UDisksWatcher.h`](file:///home/josema/Projects/omafiles/backend/UDisksWatcher.h): Removed dead service references and engine comparison comments.

### Logic Controllers (`logic/`)
- [`logic/ActionEngine.qml`](file:///home/josema/Projects/omafiles/logic/ActionEngine.qml): Removed wrapper boilerplate comments and process group comments.
- [`logic/NavigationController.qml`](file:///home/josema/Projects/omafiles/logic/NavigationController.qml): Cleaned references to root wrapper delegates and legacy launcher trials.
- [`logic/Persistence.qml`](file:///home/josema/Projects/omafiles/logic/Persistence.qml): Updated session lifecycle comments from Quickshell to standalone application startup.
- [`logic/SearchBackend.qml`](file:///home/josema/Projects/omafiles/logic/SearchBackend.qml): Cleaned dead coupling notes.
- [`logic/BookmarkOps.qml`](file:///home/josema/Projects/omafiles/logic/BookmarkOps.qml), [`logic/FileOps.qml`](file:///home/josema/Projects/omafiles/logic/FileOps.qml), [`logic/FileTypeUtils.qml`](file:///home/josema/Projects/omafiles/logic/FileTypeUtils.qml), [`logic/MountActions.qml`](file:///home/josema/Projects/omafiles/logic/MountActions.qml), [`logic/RenameOps.qml`](file:///home/josema/Projects/omafiles/logic/RenameOps.qml): Removed legacy root wrapper commentary.

### Core & State (`core/`, `state/`, `app/`, `panels/`)
- [`core/OmafilesContent.qml`](file:///home/josema/Projects/omafiles/core/OmafilesContent.qml): Removed plugin loader notes and wrapper delegations.
- [`state/Paths.qml`](file:///home/josema/Projects/omafiles/state/Paths.qml): Streamlined XDG path documentation; removed migration history from headers.
- [`state/NavState.qml`](file:///home/josema/Projects/omafiles/state/NavState.qml) & [`state/SelectionState.qml`](file:///home/josema/Projects/omafiles/state/SelectionState.qml): Cleaned plugin property notes.
- [`app/HostAdapter.qml`](file:///home/josema/Projects/omafiles/app/HostAdapter.qml) & [`app/Main.qml`](file:///home/josema/Projects/omafiles/app/Main.qml): Modernized window lifecycle and geometry restoration comments.
- [`Utils.js`](file:///home/josema/Projects/omafiles/Utils.js): Cleaned phase numbers and removed legacy wrapper references while preserving algorithmic documentation.
- [`src/selfcheck/SelfCheckRunner.qml`](file:///home/josema/Projects/omafiles/src/selfcheck/SelfCheckRunner.qml): Renamed `pluginRoot` to `resourceRoot` and cleaned headless harness comments.

### Documentation (`ARCHITECTURE.md`)
- Completely modernized [`ARCHITECTURE.md`](file:///home/josema/Projects/omafiles/ARCHITECTURE.md) to reflect the current clean Qt6 standalone structure, direct `Omafiles.Backend` integration, controller registry, and canonical XDG compliance, with archival notes preserved in a dedicated section.

---

## 3. Validation Results

```
── omafiles --selfcheck · fixtures in /home/josema/.cache/omafiles-selfcheck ──
[PASS] Backend module loaded (Omafiles.Backend) (0ms) — HOME=/home/josema
[PASS] Backend.UDisksWatcher reactive backend (0ms) — available=true
[PASS] Backend.FolderCounter counts a directory (async) (1ms) — n=4 (expected 4)
[PASS] Item count smart formatting (0ms)
[PASS] Composition root creates (OmafilesContent) (244ms) — main tree instantiated
[PASS] Composition root API surface (open/close/facade) (0ms)
[PASS] NavState is source of truth (0ms)
[PASS] TabsState defaults (0ms) — tabs=1 active=0
[PASS] ControllerRegistry + CommandFacade wiring (1ms) — palette=35 emptyArea=5 segments=6
[PASS] AppBindings loaded (no side effects under selfcheck) (0ms)
[PASS] Backend.JsonStore write/read round-trip (3ms)
[PASS] Backend.DirectoryModel list + natural order (0ms) — order=[sub, alpha.txt, beta.txt, gamma.txt]
[PASS] QFileSystemWatcher create event (0ms) — directoryChanged after creating subfolder
[PASS] Backend.ThumbnailProvider PNG (4ms)
[PASS] Backend.ThumbnailProvider PDF (qpdf plugin) (4ms)
[PASS] Thumbnail cache key is canonical SHA-1 (B1) (0ms) — cacheKey=244adfd729888c0a4499250ebb2e9f41d7243600
[PASS] Thumbnail cache pruning: orphans, safety, age, size (O1) (3ms) — orphan+safety+age+size OK
[PASS] Backend.PreviewProvider text (0ms) — utf-8, 3 lines
[PASS] Backend.PreviewProvider info (0ms) — keys=[executable,mime,mtime,name,path,permissions,readable,size,writable]
[PASS] Backend.FileOperations mkdir (1ms)
[PASS] Backend.FileOperations rename (0ms)
[PASS] Backend.FileOperations copy (1ms)
[PASS] Backend.FileOperations copy overwrite (replace) (0ms) — destination replaced
[PASS] Backend.FileOperations copy directory (recursive) (0ms) — 4 entries copied
[PASS] Backend.FileOperations copy symlink preserved (1ms) — copied as a link
[PASS] Backend.FileOperations copy preserves permissions (0ms) — src=rw- dst=rw-
[PASS] ActionEngine native copy runner (paste/drop path) (1ms) — runNativeCopy OK
[PASS] Backend.FileOperations move overwrite (replace) (1ms) — replaced, source consumed
[PASS] Backend.FileOperations move directory (recursive) (1ms) — tree moved, source gone
[PASS] Backend.FileOperations move symlink preserved (1ms) — moved as a link
[PASS] Backend.FileOperations move cross-filesystem (best-effort /tmp) (0ms) — dest ok, source gone
[PASS] Copy/move cancellation (cooperative, source safe) (1ms) — cancelled, source intact
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
[PASS] Trash collision (restore both by orig path) (6ms) — collision resolved, both restored
[PASS] Restore collision (destination exists -> error) (2ms) — error if the destination exists
[PASS] Restore recreates missing parent (1ms) — parent recreated and file restored
[PASS] ActionEngine native trash runner + undo (delete-to-trash path) (2ms) — sent and restored by undo
[PASS] Conflict detection: existingPaths (file/dir/symlink) (0ms) — detected 3/3
[PASS] Copy conflict overwrite (directory replaces) (1ms) — dir replaced: 4 entries
[PASS] Copy conflict without overwrite errors (skip semantics) (0ms) — error: destination already exists
[PASS] Move conflict without overwrite errors (skip semantics) (0ms) — error: destination already exists
[PASS] Conflict overwrite replaces symlink dest (1ms) — symlink replaced by file
[PASS] Copy progress (byte-accurate, reaches total) (22ms) — events=33 last=33554432/33554432
[PASS] Move cross-fs progress (best-effort) (39ms) — cross-fs progress 33 events
[PASS] Copy cancellation leaves no partial file (1ms) — no partial residue
[PASS] Copy cancellation leaves no partial directory (1ms) — partial tree cleaned up
[PASS] Move cross-fs cancellation: source intact, no partial (22ms) — cross-fs cancelled: src=true no partial=true
[PASS] Undo + redo move (full cycle) (2ms) — undo and redo OK
[PASS] Undo + redo trash (full cycle) (2ms) — undo and redo trash OK
[PASS] Undo sequence (LIFO: reverts the last one first) (4ms) — LIFO OK: B and then A
[PASS] Cancel then undo (cancellation doesn't alter the stack) (1ms) — undo after cancellation reverts the move
[PASS] Undo registry consistency (UndoState stacks) (2ms) — push/undo/redo stacks: true/true/true
[PASS] Backend.FileOperations move (1ms)
[PASS] Backend.FileOperations remove (1ms)
[PASS] Backend.FileOperations trash + restore (net-zero) (2ms) — restored to its place
[PASS] Background panel refreshes on content change (non-active tab) (37ms)
[PASS] Native recursive search: name, depth, hidden filter (2ms) — name+depth+hidden OK
[PASS] Native trash listing: trashRoots + trashInfo (2ms) — trashRoots+trashInfo OK
[PASS] Native network mounts listing returns a list (0ms) — Backend.NetworkMounts.list() -> 0 entries
[PASS] Conflict detection sees a broken symlink (BUG-01) (1ms) — broken symlink detected as a conflict
[PASS] empty-trash.sh empties an isolated home trash (BUG-02) (13ms) — exit=0 remaining items=0
[PASS] list-archive.sh lists a tar fixture (BUG-02) (7ms) — listed 4 top-level entries
[PASS] mount-iso.sh fails safely on a bad path (BUG-02) (10ms) — exit=1 stdout=''
[PASS] open-with-list.sh returns valid TSV (BUG-02) (25ms) — exit=0 lines=2
[PASS] Properties/chmod handle a huge selection without ARG_MAX (BUG-03) (22ms) — native OK (2000 paths)
[PASS] tar extracts a member whose name starts with '-' (BUG-05) (9ms) — new: exit=0 out='contenido05'

── selfcheck: 77 passed, 0 failed, 77 total ──
```

---

## 4. Conclusion
The codebase is now clean of dead architectural artifacts and historical noise, presenting a modern, professional, and accessible codebase for new contributors.

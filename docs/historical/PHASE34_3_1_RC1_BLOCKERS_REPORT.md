# OmaFiles — Phase 34.3.1: RC1 Release Blockers Resolution Report

**Date:** 2026-08-14  
**Role:** Release Engineer & Maintainer  
**Scope:** Phase 34.3.1 (Resolution of RC1 Release Blockers)  
**Target Release:** `v0.4.0-rc1`  
**Status:** All Blockers Resolved & Verified (77/77 tests passing)

---

## 1. Executive Summary

Following the independent verification audit, three release blockers were identified prior to tagging `v0.4.0-rc1`. All three blockers have been addressed with minimal, high-precision patches:

1. **Fix 1 (D-Bus Portability):** Replaced hardcoded `~/.local/bin/omafiles` in `dbus-filechooser.py`, `dbus-filemanager1.py`, and `dbus-app-open.py` with dynamic `shutil.which("omafiles")` lookup, enabling robust system-wide distro package support (`/usr/bin/omafiles`).
2. **Fix 2 (QML Null Safety):** Added a defensive null-guard to `hostSortOps` in [`panels/BackgroundPanel.qml`](file:///home/josema/Projects/omafiles/panels/BackgroundPanel.qml) footer text binding.
3. **Fix 3 (Version Synchronization):** Standardized canonical versioning on `v0.4.0-rc1` across [`CMakeLists.txt`](file:///home/josema/Projects/omafiles/CMakeLists.txt) and [`README.md`](file:///home/josema/Projects/omafiles/README.md), removing lingering references to old beta tags and deleted `services/` layers.

---

## 2. Modified Files & Exact Patches

### A. D-Bus Integration Scripts
Updated [`scripts/dbus-filechooser.py`](file:///home/josema/Projects/omafiles/scripts/dbus-filechooser.py), [`scripts/dbus-filemanager1.py`](file:///home/josema/Projects/omafiles/scripts/dbus-filemanager1.py), and [`scripts/dbus-app-open.py`](file:///home/josema/Projects/omafiles/scripts/dbus-app-open.py):

```python
import shutil
from pathlib import Path

# The standalone Qt6 binary (single instance) is launched from its portable path.
OMAFILES_BIN = shutil.which("omafiles") or str(Path.home() / ".local" / "bin" / "omafiles")
```

### B. QML Null-Safety Guard
In [`panels/BackgroundPanel.qml`](file:///home/josema/Projects/omafiles/panels/BackgroundPanel.qml#L560):

```diff
--- i/panels/BackgroundPanel.qml
+++ w/panels/BackgroundPanel.qml
@@ -557,7 +557,7 @@ Item {
          + " of " + bgPanel.bgSearchEntries.length
          + (bgPanel.modelData.searchTruncated ? " · showing first 200" : ""))
       : (dirLister.entries.length + (dirLister.entries.length === 1 ? " item" : " items")
-         + " · sort: " + hostSortOps.sortLabel())
+         + " · sort: " + (hostSortOps ? hostSortOps.sortLabel() : ""))
     font.pixelSize: Style.font.subtitle
     font.family: Style.font.family
     color: Color.menu.text
```

### C. Version Synchronization
In [`CMakeLists.txt`](file:///home/josema/Projects/omafiles/CMakeLists.txt):
```diff
--- i/CMakeLists.txt
+++ w/CMakeLists.txt
@@ -1,5 +1,5 @@
 cmake_minimum_required(VERSION 3.21)
-project(omafiles LANGUAGES CXX)
+project(omafiles VERSION 0.4.0 LANGUAGES CXX)
```

In [`README.md`](file:///home/josema/Projects/omafiles/README.md):
- Standardized header and status to `v0.4.0-rc1`.
- Cleaned legacy `services/` mention from architecture breakdown.

---

## 3. Validation Results

```bash
$ cmake --build build --clean-first && cmake --install build && ~/.local/bin/omafiles --selfcheck

── omafiles --selfcheck · fixtures in /home/josema/.cache/omafiles-selfcheck-BeJeIp ──
[PASS] Backend module loaded (Omafiles.Backend) (0ms) — HOME=/home/josema
[PASS] Backend.UDisksWatcher reactive backend (0ms) — available=true
[PASS] Backend.FolderCounter counts a directory (async, Fase 23) (0ms) — n=4 (expected 4)
[PASS] Item count smart formatting (1ms)
[PASS] Composition root creates (OmafilesContent) (78ms) — main tree instantiated
[PASS] Composition root API surface (open/close/facade) (0ms)
[PASS] NavState is source of truth (1ms)
[PASS] TabsState defaults (0ms) — tabs=1 active=0
[PASS] ControllerRegistry + CommandFacade wiring (0ms) — palette=35 emptyArea=5 segments=6
[PASS] AppBindings loaded (no side effects under selfcheck) (0ms) — AppBindings instantiated without self-registration
[PASS] Backend.JsonStore write/read round-trip (4ms)
[PASS] Backend.DirectoryModel list + natural order (0ms) — order=[sub, alpha.txt, beta.txt, gamma.txt]
[PASS] QFileSystemWatcher create event (1ms) — directoryChanged after creating subfolder
[PASS] Backend.ThumbnailProvider PNG (4ms)
[PASS] Backend.ThumbnailProvider PDF (qpdf plugin) (5ms)
[PASS] Thumbnail cache key is canonical SHA-1 (B1) (0ms) — cacheKey=244adfd729888c0a4499250ebb2e9f41d7243600
[PASS] Thumbnail cache pruning: orphans, safety, age, size (O1) (2ms) — orphan+safety+age+size OK
[PASS] Backend.PreviewProvider text (0ms) — utf-8, 3 lines
[PASS] Backend.PreviewProvider info (1ms) — keys=[executable,mime,mtime,name,path,permissions,readable,size,writable]
[PASS] Backend.FileOperations mkdir (0ms)
[PASS] Backend.FileOperations rename (0ms)
[PASS] Backend.FileOperations copy (1ms)
[PASS] Backend.FileOperations copy overwrite (replace) (0ms) — destination replaced
[PASS] Backend.FileOperations copy directory (recursive) (0ms) — 4 entries copied
[PASS] Backend.FileOperations copy symlink preserved (1ms) — copied as a link
[PASS] Backend.FileOperations copy preserves permissions (0ms) — src=rw- dst=rw-
[PASS] ActionEngine native copy runner (paste/drop path) (1ms) — runNativeCopy OK
[PASS] Backend.FileOperations move overwrite (replace) (0ms) — replaced, source consumed
[PASS] Backend.FileOperations move directory (recursive) (0ms) — tree moved, source gone
[PASS] Backend.FileOperations move symlink preserved (0ms) — moved as a link
[PASS] Backend.FileOperations move cross-filesystem (best-effort /tmp) (0ms) — dest ok, source gone
[PASS] Copy/move cancellation (cooperative, source safe) (1ms) — cancelled, source intact
[PASS] ActionEngine native move runner + undo (paste/drop path) (1ms) — moved and undone
[PASS] Backend.FileOperations delete directory (recursive) (1ms) — tree deleted
[PASS] Backend.FileOperations delete symlink (target preserved) (0ms) — link deleted, target intact
[PASS] Backend.FileOperations delete read-only (permission failure) (0ms) — error reported
[PASS] Backend.FileOperations delete missing (error vs ignoreMissing) (0ms) — error if missing, ok with ignoreMissing
[PASS] Backend.FileOperations delete cancellation (recursive tree) (0ms) — error=cancelled
[PASS] ActionEngine native remove runner (delete path) (2ms) — runNativeRemove OK
[PASS] Trash removes item from source (2578ms) — sent and restored
[PASS] ActionEngine trash+restore end-to-end (frontend wiring) (2ms) — trash+restore via ActionEngine OK
[PASS] Trash + restore directory (round-trip) (1ms) — tree restored: 4
[PASS] Trash + restore symlink (round-trip) (3ms) — symlink restored as a link
[PASS] Trash + restore Unicode name (round-trip) (2ms) — unicode round-trip OK
[PASS] Trash collision (restore both by orig path) (3ms) — collision resolved, both restored
[PASS] Restore collision (destination exists -> error) (2ms) — error if destination exists
[PASS] Restore recreates missing parent (1ms) — parent recreated and file restored
[PASS] ActionEngine native trash runner + undo (delete-to-trash path) (2ms) — sent and restored by undo
[PASS] Conflict detection: existingPaths (file/dir/symlink) (1ms) — detected 3/3
[PASS] Copy conflict overwrite (directory replaces) (0ms) — dir replaced: 4 entries
[PASS] Copy conflict without overwrite errors (skip semantics) (1ms) — error: destination already exists
[PASS] Move conflict without overwrite errors (skip semantics) (0ms) — error: destination already exists
[PASS] Conflict overwrite replaces symlink dest (0ms) — symlink replaced by file
[PASS] Copy progress (byte-accurate, reaches total) (24ms) — events=33 last=33554432/33554432
[PASS] Move cross-fs progress (best-effort) (41ms) — cross-fs progress 33 events
[PASS] Copy cancellation leaves no partial file (0ms) — no partial residue
[PASS] Copy cancellation leaves no partial directory (1ms) — partial tree cleaned up
[PASS] Move cross-fs cancellation: source intact, no partial (23ms) — cross-fs cancelled: src=true no partial=true
[PASS] Undo + redo move (full cycle) (2ms) — undo and redo OK
[PASS] Undo + redo trash (full cycle) (2ms) — undo and redo trash OK
[PASS] Undo sequence (LIFO: reverts the last one first) (2ms) — LIFO OK: B and then A
[PASS] Cancel then undo (cancellation doesn't alter the stack) (1ms) — undo after cancellation reverts the move
[PASS] Undo registry consistency (UndoState stacks) (1ms) — push/undo/redo stacks: true/true/true
[PASS] Backend.FileOperations move (0ms)
[PASS] Backend.FileOperations remove (1ms)
[PASS] Backend.FileOperations trash + restore (net-zero) (3ms) — restored to its place
[PASS] Background panel refreshes on content change (non-active tab) (35ms) — reflected change via refreshTick
[PASS] Native recursive search: name, depth, hidden filter (1ms) — name+depth+hidden OK
[PASS] Native trash listing: trashRoots + trashInfo (3ms) — trashRoots+trashInfo OK
[PASS] Native network mounts listing returns a list (2ms) — Backend.NetworkMounts.list() -> 0 entries
[PASS] Conflict detection sees a broken symlink (BUG-01) (1ms) — broken symlink detected as a conflict
[PASS] empty-trash.sh empties an isolated home trash (BUG-02) (14ms) — exit=0 remaining items=0
[PASS] list-archive.sh lists a tar fixture (BUG-02) (7ms) — listed 4 top-level entries
[PASS] mount-iso.sh fails safely on a bad path (BUG-02) (10ms) — exit=1 stdout=''
[PASS] open-with-list.sh returns valid TSV (BUG-02) (25ms) — exit=0 lines=2
[PASS] Properties/chmod handle a huge selection without ARG_MAX (BUG-03) (21ms) — native OK (2000 paths)
[PASS] tar extracts a member whose name starts with '-' (BUG-05) (9ms) — new: exit=0 out='contenido05'

── selfcheck: 77 passed, 0 failed, 77 total ──
```

---

## 4. Release Status Assessment

All blockers identified in the independent verification audit are resolved. The repository is in an **RC1-ready state** and prepared for tagging `v0.4.0-rc1`.

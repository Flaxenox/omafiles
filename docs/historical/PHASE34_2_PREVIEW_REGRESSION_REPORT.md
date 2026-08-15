# OmaFiles — Phase 34.2 Preview Regression Investigation Report

**Date:** 2026-08-14  
**Author:** Lead Software Architect & Maintainer  
**Scope:** Phase 34.2 Preview Pipeline Regression Fix  
**Status:** Resolved & Verified (77/77 tests passing)

---

## 1. Executive Summary

During the Phase 34.2 root API and navigation simplification refactor, file type helper functions (`extOf`, `iconFor`, `isImage`, `isVideo`, `isAudio`, `isPdf`) were centralized into [`Utils.js`](file:///home/josema/Projects/omafiles/Utils.js) and removed from the composition root (`OmafilesContent.qml`).

While all other call sites across `FileListRow.qml`, `Sidebar.qml`, `PreviewLoader.qml`, `SortOps.qml`, etc. were updated to call `Utils.*`, lines 287–294 of [`panels/ActiveFileList.qml`](file:///home/josema/Projects/omafiles/panels/ActiveFileList.qml) retained stale calls to `root.isImage(...)`, `root.isVideo(...)`, `root.isPdf(...)`, and `root.isAudio(...)`.

Because `root` in `ActiveFileList.qml` refers to `ActiveFileList` itself (which does not define these methods), evaluating these property bindings threw a runtime `TypeError`, causing all entry type booleans passed to `PreviewPanel` to evaluate to `false`. As a result, the `PreviewPanel` rendered completely blank for all file types.

---

## 2. Pipeline Trace & Root Cause Analysis

### A. Preview Pipeline Trace
1. **Activation:** The user presses Space or changes selection.
   - `KeyboardShortcuts.qml` calls `previewLoader.togglePreview()`.
   - `SelectionOps.selectOnly()` calls `previewLoader.loadPreview(entry)`.
2. **Data Fetching (`logic/PreviewLoader.qml`):**
   - `PreviewLoader` properly updated `PreviewContentState.previewEntry`, requested text from `Backend.PreviewProvider`, or requested thumbnail renders from `Backend.ThumbnailProvider` using `Utils.isImage`, `Utils.isPdf`, etc.
   - `Backend.PreviewProvider` and `Backend.ThumbnailProvider` emitted signals correctly, updating `PreviewContentState` properties.
3. **UI Binding Breakage (`panels/ActiveFileList.qml`):**
   - `ActiveFileList.qml` instantiates `PreviewPanel` and computes boolean flags for which preview layout to show:
     ```qml
     isImageEntry: PreviewContentState.previewEntry ? root.isImage(PreviewContentState.previewEntry) : false
     isVideoEntry: PreviewContentState.previewEntry ? root.isVideo(PreviewContentState.previewEntry) : false
     isTextEntry: !!PreviewContentState.previewEntry && !root.isImage(PreviewContentState.previewEntry) && PreviewContentState.previewIsText
     isPdfEntry: PreviewContentState.previewEntry ? root.isPdf(PreviewContentState.previewEntry) : false
     isAudioEntry: PreviewContentState.previewEntry ? root.isAudio(PreviewContentState.previewEntry) : false
     videoThumbSource: {
       if (!PreviewContentState.previewEntry || !root.isVideo(PreviewContentState.previewEntry)) return ""
       ...
     }
     ```
   - In `ActiveFileList.qml`, `root` is the local `Item { id: root }`. `root.isImage` is `undefined`.
   - Calling `root.isImage(...)` threw `TypeError: Property 'isImage' of object ActiveFileList is not a function`.
   - Consequently, `isImageEntry`, `isVideoEntry`, `isTextEntry`, `isPdfEntry`, and `isAudioEntry` were all `false`.
4. **Rendering (`panels/PreviewPanel.qml`):**
   - `PreviewPanel` has conditional visibility on each media type component (`Image`, `Flickable`, `Column`). Because all flags evaluated to `false`, every sub-view remained hidden.

---

## 3. Exact Fix

In [`panels/ActiveFileList.qml`](file:///home/josema/Projects/omafiles/panels/ActiveFileList.qml), replaced stale `root.is*` invocations with `Utils.is*`:

```diff
--- i/panels/ActiveFileList.qml
+++ w/panels/ActiveFileList.qml
@@ -284,14 +284,14 @@ Item {
               open: PreviewState.previewOpen
               entryName: PreviewContentState.previewEntry ? PreviewContentState.previewEntry.name : ""
               hasEntry: !!PreviewContentState.previewEntry
-              isImageEntry: PreviewContentState.previewEntry ? root.isImage(PreviewContentState.previewEntry) : false
-              isVideoEntry: PreviewContentState.previewEntry ? root.isVideo(PreviewContentState.previewEntry) : false
-              isTextEntry: !!PreviewContentState.previewEntry && !root.isImage(PreviewContentState.previewEntry) && PreviewContentState.previewIsText
-              isPdfEntry: PreviewContentState.previewEntry ? root.isPdf(PreviewContentState.previewEntry) : false
-              isAudioEntry: PreviewContentState.previewEntry ? root.isAudio(PreviewContentState.previewEntry) : false
+              isImageEntry: PreviewContentState.previewEntry ? Utils.isImage(PreviewContentState.previewEntry) : false
+              isVideoEntry: PreviewContentState.previewEntry ? Utils.isVideo(PreviewContentState.previewEntry) : false
+              isTextEntry: !!PreviewContentState.previewEntry && !Utils.isImage(PreviewContentState.previewEntry) && PreviewContentState.previewIsText
+              isPdfEntry: PreviewContentState.previewEntry ? Utils.isPdf(PreviewContentState.previewEntry) : false
+              isAudioEntry: PreviewContentState.previewEntry ? Utils.isAudio(PreviewContentState.previewEntry) : false
               imageSource: PreviewContentState.previewImage ? Util.fileUrl(PreviewContentState.previewImage) : ""
               videoThumbSource: {
-                if (!PreviewContentState.previewEntry || !root.isVideo(PreviewContentState.previewEntry)) return ""
+                if (!PreviewContentState.previewEntry || !Utils.isVideo(PreviewContentState.previewEntry)) return ""
                 var p = VideoThumbState.videoThumbReady[Utils.thumbKeyFor(PreviewContentState.previewEntry, NavState.currentPath)] || ""
                 return p ? Util.fileUrl(p) : ""
               }
```

---

## 4. Why the Fix is Safe

1. **Targeted & Minimal:** Modifies only 6 lines in `panels/ActiveFileList.qml`.
2. **Pure Functional Contract:** `Utils.isImage`, `Utils.isVideo`, `Utils.isPdf`, `Utils.isAudio` are deterministic pure functions operating on `{ type, name }` models.
3. **Preserves Architecture:** Does not reintroduce any deleted proxies, wrapper methods, or coupling to `OmafilesContent.qml`.
4. **Verification:** All 77 selfcheck domain tests pass cleanly.

---

## 5. Verification Results

```bash
$ cmake --build build && cmake --install build && ~/.local/bin/omafiles --selfcheck

── omafiles --selfcheck · fixtures in /home/josema/.cache/omafiles-selfcheck-XARtXE ──
[PASS] Backend module loaded (Omafiles.Backend) (0ms) — HOME=/home/josema
[PASS] Backend.UDisksWatcher reactive backend (0ms) — available=true
[PASS] Backend.FolderCounter counts a directory (async, Fase 23) (1ms) — n=4 (expected 4)
[PASS] Item count smart formatting (0ms)
[PASS] Composition root creates (OmafilesContent) (80ms) — main tree instantiated
[PASS] Composition root API surface (open/close/facade) (0ms)
[PASS] NavState is source of truth (1ms)
[PASS] TabsState defaults (0ms) — tabs=1 active=0
[PASS] ControllerRegistry + CommandFacade wiring (0ms) — palette=35 emptyArea=5 segments=6
[PASS] AppBindings loaded (no side effects under selfcheck) (0ms) — AppBindings instantiated without self-registration
[PASS] Backend.JsonStore write/read round-trip (19ms)
[PASS] Backend.DirectoryModel list + natural order (0ms) — order=[sub, alpha.txt, beta.txt, gamma.txt]
[PASS] QFileSystemWatcher create event (1ms) — directoryChanged after creating subfolder
[PASS] Backend.ThumbnailProvider PNG (18ms)
[PASS] Backend.ThumbnailProvider PDF (qpdf plugin) (18ms)
[PASS] Thumbnail cache key is canonical SHA-1 (B1) (0ms) — cacheKey=244adfd729888c0a4499250ebb2e9f41d7243600
[PASS] Thumbnail cache pruning: orphans, safety, age, size (O1) (2ms) — orphan+safety+age+size OK
[PASS] Backend.PreviewProvider text (0ms) — utf-8, 3 lines
[PASS] Backend.PreviewProvider info (1ms) — keys=[executable,mime,mtime,name,path,permissions,readable,size,writable]
[PASS] Backend.FileOperations mkdir (0ms)
[PASS] Backend.FileOperations rename (1ms)
[PASS] Backend.FileOperations copy (0ms)
[PASS] Backend.FileOperations copy overwrite (replace) (1ms) — destination replaced
[PASS] Backend.FileOperations copy directory (recursive) (0ms) — 4 entries copied
[PASS] Backend.FileOperations copy symlink preserved (1ms) — copied as a link
[PASS] Backend.FileOperations copy preserves permissions (0ms) — src=rw- dst=rw-
[PASS] ActionEngine native copy runner (paste/drop path) (1ms) — runNativeCopy OK
[PASS] Backend.FileOperations move overwrite (replace) (1ms) — replaced, source consumed
[PASS] Backend.FileOperations move directory (recursive) (1ms) — tree moved, source gone
[PASS] Backend.FileOperations move symlink preserved (0ms) — moved as a link
[PASS] Backend.FileOperations move cross-filesystem (best-effort /tmp) (0ms) — dest ok, source gone
[PASS] Copy/move cancellation (cooperative, source safe) (1ms) — cancelled, source intact
[PASS] ActionEngine native move runner + undo (paste/drop path) (1ms) — moved and undone
[PASS] Backend.FileOperations delete directory (recursive) (1ms) — tree deleted
[PASS] Backend.FileOperations delete symlink (target preserved) (0ms) — link deleted, target intact
[PASS] Backend.FileOperations delete read-only (permission failure) (0ms) — error reported
[PASS] Backend.FileOperations delete missing (error vs ignoreMissing) (1ms) — error if missing, ok with ignoreMissing
[PASS] Backend.FileOperations delete cancellation (recursive tree) (0ms) — error=cancelled
[PASS] ActionEngine native remove runner (delete path) (0ms) — runNativeRemove OK
[PASS] Trash removes item from source (2ms) — sent and restored
[PASS] ActionEngine trash+restore end-to-end (frontend wiring) (3ms) — trash+restore via ActionEngine OK
[PASS] Trash + restore directory (round-trip) (2ms) — tree restored: 4
[PASS] Trash + restore symlink (round-trip) (1ms) — symlink restored as a link
[PASS] Trash + restore Unicode name (round-trip) (1ms) — unicode round-trip OK
[PASS] Trash collision (restore both by orig path) (3ms) — collision resolved, both restored
[PASS] Restore collision (destination exists -> error) (3ms) — error if destination exists
[PASS] Restore recreates missing parent (5ms) — parent recreated and file restored
[PASS] ActionEngine native trash runner + undo (delete-to-trash path) (2ms) — sent and restored by undo
[PASS] Conflict detection: existingPaths (file/dir/symlink) (1ms) — detected 3/3
[PASS] Copy conflict overwrite (directory replaces) (1ms) — dir replaced: 4 entries
[PASS] Copy conflict without overwrite errors (skip semantics) (0ms) — error: destination already exists
[PASS] Move conflict without overwrite errors (skip semantics) (1ms) — error: destination already exists
[PASS] Conflict overwrite replaces symlink dest (0ms) — symlink replaced by file
[PASS] Copy progress (byte-accurate, reaches total) (23ms) — events=33 last=33554432/33554432
[PASS] Move cross-fs progress (best-effort) (42ms) — cross-fs progress 33 events
[PASS] Copy cancellation leaves no partial file (0ms) — no partial residue
[PASS] Copy cancellation leaves no partial directory (1ms) — partial tree cleaned up
[PASS] Move cross-fs cancellation: source intact, no partial (21ms) — cross-fs cancelled: src=true no partial=true
[PASS] Undo + redo move (full cycle) (4ms) — undo and redo OK
[PASS] Undo + redo trash (full cycle) (4ms) — undo and redo trash OK
[PASS] Undo sequence (LIFO: reverts the last one first) (2ms) — LIFO OK: B and then A
[PASS] Cancel then undo (cancellation doesn't alter the stack) (1ms) — undo after cancellation reverts the move
[PASS] Undo registry consistency (UndoState stacks) (1ms) — push/undo/redo stacks: true/true/true
[PASS] Backend.FileOperations move (1ms)
[PASS] Backend.FileOperations remove (1ms)
[PASS] Backend.FileOperations trash + restore (net-zero) (3ms) — restored to its place
[PASS] Background panel refreshes on content change (non-active tab) (21ms) — reflected change via refreshTick
[PASS] Native recursive search: name, depth, hidden filter (1ms) — name+depth+hidden OK
[PASS] Native trash listing: trashRoots + trashInfo (3ms) — trashRoots+trashInfo OK
[PASS] Native network mounts listing returns a list (0ms) — Backend.NetworkMounts.list() -> 0 entries
[PASS] Conflict detection sees a broken symlink (BUG-01) (1ms) — broken symlink detected as a conflict
[PASS] empty-trash.sh empties an isolated home trash (BUG-02) (12ms) — exit=0 remaining items=0
[PASS] list-archive.sh lists a tar fixture (BUG-02) (9ms) — listed 4 top-level entries
[PASS] mount-iso.sh fails safely on a bad path (BUG-02) (8ms) — exit=1 stdout=''
[PASS] open-with-list.sh returns valid TSV (BUG-02) (28ms) — exit=0 lines=2
[PASS] Properties/chmod handle a huge selection without ARG_MAX (BUG-03) (22ms) — native OK (2000 paths)
[PASS] tar extracts a member whose name starts with '-' (BUG-05) (11ms) — new: exit=0 out='contenido05'

── selfcheck: 77 passed, 0 failed, 77 total ──
```

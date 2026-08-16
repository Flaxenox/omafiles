# Omafiles — Full Bug Matrix

**Date:** 2026-08-16
**Repo:** /home/josema/Projects/omafiles (branch `v1.0-dev`, 215 commits at time of audit)
**Scope:** Adversarial, read-only forensic pass across concurrency, filesystem edge cases, QML binding safety, security, and UX-regression lenses, plus regression verification of five self-reported "fixed" historical incident reports.

**Method note:** Every finding below was independently re-verified against current on-disk source (file reads, greps, `git blame`/`git show`, and in some cases live command execution or an actual `--selfcheck` run) — not accepted at face value from any prior report, including this project's own `docs/historical/*.md` self-reports. Claims that could not be directly verified are explicitly marked UNVERIFIED in their own section. 20 of 22 candidate findings survived adversarial verification; the 2 refuted candidates are documented in the appendix with the specific reasoning that refuted them, for transparency about what was considered and rejected.

**Note on attribution:** All commits in this repo's history are authored by Percius04, Sebasgl23, or Sebastián Guardo — there is no separate "Gemini" (or other named AI agent) author in `git log`. Where source material referenced "Gemini's changes," this matrix treats that as shorthand for "the post-Phase-30 refactor era" and does not assert a distinct agent identity performed any specific commit.

---

## Bug Matrix

Ordered by severity (critical → high → medium → low).

### BUG-001 — [critical] New-folder action races the native batch state machine
- **Lens:** concurrency
- **File:** `logic/ActionEngine.qml`
- **Function:** `runPendingNewFolder()` / `commitNewFolder()` (lines ~554-577, ~978-988) vs. the unfiltered `Connections { target: Backend.FileOperations }` block (lines ~152-179); `mkdir` call at line 576
- **Mechanism:** Every native batch operation (copy/move/remove/trash/restore/emptyTrash) goes through `_runNative()`/`emptyTrash()`, both gated by `if (actionProc.busy || nativeBusy) { ...; return false }` before setting `nativeBusy = true` and driving `_batchQueue`/`_batchIdx` sequentially via `_batchNext()`. **"New folder" bypasses this gate entirely.** `startNewFolder()` (bound to Ctrl+Shift+N in `logic/KeyboardShortcuts.qml:185-187` and the "New folder" command in `core/CommandFacade.qml`) and `commitNewFolder() → runPendingNewFolder()` call `Backend.FileOperations.mkdir(pending.path)` directly with **zero busy check**. Meanwhile the first `Connections` block's `onFinished`/`onError` handlers (lines 161-171) filter **only** on `nativeBusy`, never on the `op` argument:
  ```
  function onFinished(op, path) {
    if (!nativeBusy) return
    if (_nativeKind === "emptyTrash") { _finishNative(true); return }
    _progBase += _lastItemTotal
    _lastItemTotal = 0
    _batchIdx += 1
    _batchNext()
  }
  ```
  Since `Backend.FileOperations` is a `QML_SINGLETON` dispatching every op via `QThreadPool::globalInstance()->start(...)` (backend/FileOperations.cpp:29-51) with no internal serialization, an mkdir job and an in-flight copy/move batch job run genuinely concurrently and emit into the same `finished(op,path)`/`error(op,path,msg)` signals. When mkdir's near-instant job finishes, the generic (op-agnostic) handler treats it as "the current batch item finished," advancing `_batchIdx` and calling `_batchNext()` while the real batch item is still copying/moving on the pool. A second, correctly-filtered `Connections` block (lines 582-608, `if (op !== "mkdir") return`) exists for mkdir's own undo registration, but this does not stop the first block from also reacting to the same signal.
- **Repro:** 1) Paste a large copy/move into a slow destination so the progress bar stays visible. 2) While it runs, press Ctrl+Shift+N, type a folder name, press Enter. 3) Observe the batch progress jump/advance incorrectly or finish early while background items are still copying, unmonitored and uncancelable.
- **Impact:** Pressing "New folder" while any batch progress bar is visible corrupts the batch state machine: multiple items share the single `m_cancelled` flag and progress bookkeeping (`_progBase`/`_lastItemTotal` go wrong), the batch can report `finished` (firing `pushUndo`/`onDone`) while items are still copying in the background, and any subsequent error from those orphaned copies is silently dropped (`if (!nativeBusy) return` is already true). On overlapping source/destination paths this can produce genuinely corrupted/partial file trees.
- **Proposed fix:** (a) Gate `startNewFolder()`/`commitNewFolder()`/`runPendingNewFolder()` behind the same `actionProc.busy || nativeBusy` check used everywhere else, or (b) make the top `Connections.onFinished`/`onError` filter on `op` matching `_nativeKind` (and ideally `path` matching `_batchQueue[_batchIdx]`) before touching `_batchIdx`/`_progBase`.
- **Regression risk of fix:** Low for (a) — only adds a "busy, try again" notification matching the existing pattern for every other destructive action. (b) is more robust but requires correctly correlating `path` with the in-flight batch item.

---

### BUG-002 — [critical] SearchWorker use-after-free via mid-loop `this` dereference
- **Lens:** concurrency
- **File:** `backend/SearchWorker.cpp`
- **Function:** `SearchWorker::search()` (~lines 36-90) and `SearchWorker::searchContent()` (~lines 102-207)
- **Mechanism:** Both submit a `QRunnable` to `QThreadPool::globalInstance()` capturing `[this, life, gen, rootPath, q, showHidden]`. Inside the `QDirIterator`/`QTextStream` scan loop, cancellation is checked every iteration via a bare `if (m_gen.load() != gen) return;` (lines 51, 115, 154) — `m_gen` is a private member, so this implicitly dereferences `this` on every loop iteration with no lifetime guard. The `shared_ptr<Life> life` (mutex + alive flag) is acquired and checked **only at the very end**, immediately before the final `QMetaObject::invokeMethod(this, ..., Qt::QueuedConnection)`. This is asymmetric with `backend/DirectoryModel.cpp`'s `startScan()`, whose job closure never touches `this` until *after* the `life`-guarded lock is held (confirmed by direct comparison of both files). `~SearchWorker()` sets `alive=false` under the lock but never calls `QThreadPool::waitForDone()` and there is no `aboutToQuit` hook anywhere in the repo (verified via repo-wide grep, zero hits).
- **Repro:** `logic/SearchBackend.qml` instantiates one persistent `Backend.SearchWorker { id: recursive }` (`logic/SearchOps.qml`), itself instantiated once for the app's lifetime by `core/ControllerRegistry.qml`. Trigger a recursive/content search over a large or slow tree (e.g. a network mount — `backend/NetworkMounts.cpp`/`NetworkResolver.cpp` confirm support) so the scan loop is still walking when the user quits (`Qt.quit()` in `app/Main.qml`); QML engine teardown deletes the singleton-lifetime `SearchWorker` while its `QThreadPool` task is still mid-loop.
- **Impact:** Heap-use-after-free reading (and via `std::atomic`, potentially touching freed cache lines of) a destroyed `SearchWorker`'s memory for as long as the background walk keeps running post-destruction. Can silently loop on garbage, SIGSEGV on an unmapped page, or corrupt heap metadata under allocator contention — classic UB, hard to reproduce deterministically but real under ASan/valgrind or unlucky timing.
- **Proposed fix:** Move the generation counter into the shared `Life`-style control block (or a separate `shared_ptr<atomic<quint64>>`) so the loop's cancellation check touches only the shared_ptr-owned, independently-lifetimed block, never `this` — mirroring exactly how `DirectoryModel`/`FileOperations` never touch `this` before the locked delivery.
- **Regression risk of fix:** Low-to-medium — mechanical, isolated to `SearchWorker.h/.cpp`; external contract (`search()`/`searchContent()`/`cancel()`/`results` signal) unchanged. Care needed that `cancel()` and generation increments still operate on the relocated atomic.

---

### BUG-003 — [critical] ThumbnailProvider use-after-free — no life-guard at all on `invokeMethod(this, ...)`
- **Lens:** concurrency
- **File:** `backend/ThumbnailProvider.cpp`
- **Function:** `ThumbnailProvider::request()` (lines 184-223)
- **Mechanism:**
  ```cpp
  QThreadPool::globalInstance()->start(QRunnable::create(
      [this, path, size, outPath, key]() {
        const bool ok = generate(path, size, outPath);
        QMetaObject::invokeMethod(
            this,
            [this, path, outPath, key, ok]() {
              m_inflight.remove(key);
              if (ok) emit ready(path, outPath);
            },
            Qt::QueuedConnection);
      }));
  ```
  `generate()` is `static` and touches no member state (safe), but the outer lambda captures raw `this` with **no life-guard whatsoever** — no `shared_ptr<Life>`, no mutex, nothing — unlike the sibling classes `DirectoryModel`, `FileOperations`, and `SearchWorker` (BUG-002), all of which use a deliberate `shared_ptr<Life>{mutex, bool}` control block. `ThumbnailProvider.h` declares `QML_SINGLETON` with **no custom destructor at all**. Calling `QMetaObject::invokeMethod` directly on the worker thread against a raw pointer whose object may already be destroyed is undefined behavior at the call site itself (reading the object's thread affinity/d-pointer from potentially-freed memory) — this is a materially weaker guarantee than the sibling-class pattern that exists in the same codebase specifically to prevent this class of bug.
- **Repro:** Open a folder with several large images/multi-page PDFs (or a slow network mount) so `QImageReader`/`QPdfDocument::render` takes measurable time, then close the app / Ctrl+Q while thumbnails are still generating (visible as icons not yet swapped for real thumbnails). Confirmed via grep this fires from `FileListRow.qml`, `BackgroundListDelegate.qml`, `VideoThumbnails.qml`, `ActionEngine.qml`, `PreviewLoader.qml` — i.e. essentially every visible image/PDF thumbnail during normal browsing.
- **Impact:** Quitting the app while any thumbnail generation is in flight is a heap-use-after-free at the `invokeMethod` call site. This is a common window in practice given how many call sites trigger `request()`. No `QThreadPool::waitForDone()`/`aboutToQuit` drain exists anywhere in the repo (verified by grep).
- **Proposed fix:** Adopt the same `shared_ptr<Life>{mutex, bool}` pattern already proven in `DirectoryModel`/`FileOperations`/`SearchWorker`: capture a `shared_ptr<Life> life = m_life` copy, lock, check `life->alive` before calling `invokeMethod(this, ...)`, and set `alive=false` under the same lock in an explicit `~ThumbnailProvider()`.
- **Regression risk of fix:** Low — purely additive, no happy-path behavior change, and the pattern is already proven/tested elsewhere in the same codebase.

---

### BUG-006 — [critical] Silent truncation on mid-copy I/O read error — reports success on data loss
- **Lens:** fs-edge-cases
- **File:** `backend/FileOpsPrivate.h`
- **Function:** `FileOpsPrivate::copyFile` (lines 60-92, loop at line 76)
- **Mechanism:** `while ((n = in.read(buf.data(), kChunk)) > 0) { ... }`. `QFile::read()` returns **-1 on an I/O error** (network share disconnects mid-read, a failing/unplugged USB device, a bad sector, an NFS/CIFS/gvfs/sshfs mount going stale) and **0 on normal EOF**. The loop condition `n > 0` treats both identically: it silently exits as if the file were fully read. Execution then falls through to `out.close(); in.close(); out.setPermissions(in.permissions()); return true;` — the function reports **success** even though only part of the source was read/written. Called from `copyTree()` (lines 95-123), used by both `copy()` and `move()`'s cross-filesystem fallback, both wired to the live UI (paste, drag-drop copy, cut/move) via `logic/ActionEngine.qml`. Confirmed no post-copy verification of size/integrity anywhere in `FileOperations_Copy.cpp` — on `copyTree` returning true it emits progress using the precomputed *expected* total (not actual bytes copied) and returns `{true, QString()}`.
- **Repro:** Copy a large file from a gvfs/sshfs/NFS/SMB mount and disconnect the network partway through the copy (or use a FUSE filesystem returning EIO on read after N bytes). Omafiles emits `finished("copy", ...)` with no error; the destination file is smaller than the source and contains only the bytes read before the disconnect.
- **Impact:** Silent data corruption — the worst-case outcome for a file manager's core copy path. No error notification, no partial-copy warning; the user has no signal that data is missing.
- **Proposed fix:** After the loop (or by distinguishing `n == 0` from `n < 0`), add `if (n < 0) { err = QStringLiteral("read failed on %1").arg(src); return false; }` before the success path.
- **Regression risk of fix:** Low — only changes behavior for a case previously mis-reported as success; no selfcheck simulates a mid-read I/O error today.

---

### BUG-009 — [critical] `refreshArchiveListing()` references undeclared `list` — archive browsing is completely broken
- **Lens:** qml-binding
- **File:** `logic/ActionEngine.qml`
- **Function:** `refreshArchiveListing()` (lines 1116-1120) and `archiveListProc.onFinished` (lines 1177-1191)
- **Mechanism:** Both reference the bare identifier `list` (`list.contentY = list.originY` at line 1118; `list.positionViewAtBeginning()` at line 1188), but `ActionEngine.qml` declares **no** `property Item list` anywhere (only `root`, `navController`, `_nativeMkdirPending`, and action-state properties). `list` exists only as a document-local `id:` inside `core/MainLayout.qml:214` (`ActiveFileList { id: list ... }`) — not visible across file/component boundaries under QML's per-file id scoping. In `core/ControllerRegistry.qml`, `ActionEngine { id: actionEngine root: registry.root navController: navController }` is instantiated **without** a `list: registry.list` binding, unlike sibling controllers `SearchOps`, `TabOps`, and `NavigationController`, which all explicitly receive `list: registry.list` and each declare `property Item list: null`. **Confirmed regression via git history:** before commit `37f3f318` ("chore: architecture consolidation and final v0.9.0 stability fixes", 2026-08-15, Percius04), a separate `ArchiveActions` controller owned these functions and *was* wired with `list: registry.list` (`git show 37f3f318^:core/ControllerRegistry.qml`, line 52). That commit merged `ArchiveActions` (and a dozen other controllers) into `ActionEngine.qml` but dropped the `list` property/wiring. HEAD (`bf38073`) has not touched `ActionEngine.qml` since.
- **Repro:** 1) Navigate to a folder with a `.zip`/`.7z`/`.rar`/`.tar.gz`. 2) Double-click it (`NavigationController.qml:253` calls `actionEngine.enterArchive(...)`). Expected: archive contents list. Actual: `ReferenceError: list is not defined` (visible via `journalctl --user`), the file list never updates, app stuck believing it's inside the archive. Alternative repro: open an archive in one tab, switch tabs, switch back — `TabOps._restoreTabArchive()` (line 133) hits the same broken call.
- **Impact:** Archive browsing is completely non-functional at HEAD. Two independent trigger paths (direct double-click-into-archive, and tab-restore-of-archive-state) both throw before `archiveListProc.start(...)` ever runs.
- **Proposed fix:** Add `property Item list: null` to `logic/ActionEngine.qml`, and add `list: registry.list` to the `ActionEngine { ... }` block in `core/ControllerRegistry.qml`, matching the pattern already used by `TabOps`/`SearchOps`/`NavigationController`.
- **Regression risk of fix:** Low — purely additive property + wiring following an already-working established pattern; only affects the currently-broken archive path.

---

### BUG-012 — [high] Archive "open" cache path is a predictable, unsalted hash → symlink-based arbitrary file overwrite
- **Lens:** security-bugs
- **File:** `logic/ActionEngine.qml`
- **Function:** `openFileInArchive(entry)` (~lines 1124-1137), keyed by `backend/ThumbnailProvider.cpp` `hashKey()`/`cacheKey()` (lines 225-232)
- **Mechanism:** `openFileInArchive()` builds `out = ~/.cache/omafiles/archive-open/<hash>/<entry.name>`, where `<hash> = SHA1(archivePath + "|" + fullMemberPath)` via `Backend.ThumbnailProvider.cacheKey()` — plain unsalted `QCryptographicHash::Sha1`, **100% deterministic and computable offline** by anyone who knows the archive's path and the internal member path (both attacker-controlled/predictable if the attacker authored the archive). Extraction runs as `bash -c "mkdir -p -- '<outDir>' && unzip -p -- '<archive>' '<full>' > '<out>'"` (same pattern for 7z/rar/tar). There is **no pre-check that `<out>` doesn't already exist**, and no `O_EXCL`/`O_NOFOLLOW` — the shell `>` redirect opens with `O_CREAT|O_TRUNC`, which follows an existing symlink and truncates its **target**. Empirically verified: `bash -c "echo PWNED > 'thelink'"` where `thelink -> target.txt` overwrote `target.txt`'s content while leaving the symlink untouched. Also empirically verified `cacheKey` computation reproduces a specific hash offline with no access to the victim's machine.
- **Repro:** 1) Attacker computes `hash = SHA1("/home/victim/Downloads/notes.zip|readme.txt")` offline. 2) Attacker gets any local write access to `~/.cache/omafiles/archive-open/` and plants a symlink `<hash>/readme.txt -> /home/victim/.bashrc`. 3) Attacker gets `notes.zip` (containing member `readme.txt` with a malicious payload) placed at `/home/victim/Downloads/notes.zip`. 4) Victim opens Omafiles, enters `notes.zip`, double-clicks `readme.txt`. 5) Omafiles runs `unzip -p ... > '<cache>/<hash>/readme.txt'`, following the symlink and overwriting `~/.bashrc`.
- **Impact:** Arbitrary-file overwrite with fully attacker-controlled bytes, escalatable to code execution (`~/.bashrc`, `~/.config/autostart/*.desktop`, `~/.ssh/authorized_keys`). Precondition: attacker needs *some* local write access to the cache dir as the same OS user ahead of time — a materially lower bar than already having full `$HOME` write access. No timing race required; the symlink can be pre-planted once and sits until the victim ever opens that member from that archive path.
- **Proposed fix:** The codebase already uses the correct mitigating pattern elsewhere (`compressSelected()` does `rm -f -- <quoted archiveName> && zip ...` specifically to avoid following an existing path, per the comment at `ActionEngine.qml` lines 851-860). Add `rm -f -- <quoted out> && ` before the mkdir/extract command in `openFileInArchive()`.
- **Regression risk of fix:** Very low — no caching/skip-if-exists logic exists today (every click already re-extracts unconditionally), so unconditional cleanup has no behavior change for the legitimate case. Verified empirically that `rm -f` on a symlink removes only the link, leaving any prior target file untouched.

---

### BUG-015 — [high] Undo/redo reports success optimistically before the async action actually completes
- **Lens:** ux-regression
- **File:** `logic/ActionEngine.qml`
- **Function:** `undoLast()` / `redoLast()` (lines 35-72), used by every `pushUndo()`-registered action (rename, new-file, mkdir, bulk-rename, chmod, symlink, trash-delete, paste-move, drag-drop-move)
- **Mechanism:** `undoLast()` pops the entry off `UndoState.undoStack` **before** knowing whether the undo actually succeeds, then calls `entry.undo()`. That function is always `runAction(...)`/`runNativeMove(...)`/etc., which return `true` as soon as the shell command or native op is merely **started** — success/failure is only known later, asynchronously, via `actionProc.onFinished` or the `FileOperations` `Connections`. `undoLast()` treats the synchronous `true` as proof of success: it unconditionally shows `Notifier.notify("Undoing: " + entry.label)` and pushes to `redoStack`. The only safety net (`started === false` → re-push) fires **exclusively** on a busy-check, never on a genuine failure or silent no-op. Empirically confirmed with GNU `mv -n`: when the undo target already exists (e.g. re-created externally), `mv -n src dst` exits 0 doing **nothing** — the exact command used by `runPendingRename()`'s undo (`mv -n -- newPath oldPath`, no onSuccess/verification callback).
- **Repro:** 1) Rename `fileA.txt → fileB.txt` (pushes undo entry whose undo is `mv -n fileB.txt fileA.txt`). 2) Before Ctrl+Z, externally create a new empty `fileA.txt`. 3) Press Ctrl+Z. `mv -n` is a no-op (target exists, no-clobber), exits 0; `runAction()` already returned `true` synchronously; `undoLast()` shows "Undoing: rename to fileA.txt" as if it worked and drops the entry. `fileB.txt` is never renamed back; the user is told the undo happened and has no way to retry (entry is gone from the stack).
- **Impact:** Any external filesystem change that makes an undo/redo a no-op (not merely an error) is swallowed silently while the app reports success and mutates the undo/redo stacks as if the reversal happened — permanently corrupting undo history with zero indication to the user.
- **Proposed fix:** Drive the notification and stack placement from the actual completion callback, not the synchronous start-return value; on real failure/no-op, restore the entry to `undoStack` (or surface a distinct "Undo failed: target already exists" message).
- **Regression risk of fix:** Moderate — touches shared undo/redo plumbing used by every reversible action; must be done consistently for both `actionProc`-based and native-batch-based undo/redo, and shifts "Undoing/Redoing" notification timing from sync to async.

---

### BUG-016 — [high] Cancelling a multi-file move/trash batch mid-way leaves already-completed items un-undoable and unreported
- **Lens:** ux-regression
- **File:** `logic/ActionEngine.qml`
- **Function:** `_batchNext()` / `_finishNative()` (lines 254-276), reached via `runNativeCopy`/`runNativeMove`/`runNativeTrash`/`runNativeRemove` (lines 190-252) and `cancelAction()` (lines 109-126)
- **Mechanism:** Native batches process one item at a time; each success advances `_batchIdx` and calls `_batchNext()`. Clicking Cancel sets `_cancelling=true` and calls `Backend.FileOperations.cancel()`; the in-flight item aborts (`onError` with `"cancelled"`), and `_batchNext()`'s first check `if (_cancelling) { _finishNative(false); return }` stops the queue. `_finishNative(success)` only invokes the batch's `onDone` callback — **where `pushUndo()` is registered** — `if (success && cb)`. On cancellation, `success` is always `false`, so the callback (and `pushUndo`) never runs, **regardless of how many items already completed successfully** before the cancel. Additionally, `Connections.onError` (lines 173-178) explicitly suppresses any notification when `msg === "cancelled"` — zero feedback distinguishing "nothing happened" from "some items already moved." Confirmed `pushUndo` is called exactly 9 times in the file, all at the batch-level `onDone` callback — no per-item or partial-batch registration exists anywhere.
- **Repro:** Select 5 sizeable files, Ctrl+X then Ctrl+V into another folder. While 2 of 5 have completed (visible via progress bar), click Cancel. The 2 already-moved files stay in the destination, gone from the source — but `UndoState.undoStack` is untouched (nothing to Ctrl+Z) and no toast reports the partial completion.
- **Impact:** Cancelling a multi-file cut+paste (move) or drag-and-drop move partway through leaves already-completed items physically moved with no corresponding undo entry and no notification.
- **Proposed fix:** Track `_batchIdx` at cancellation time and, in `_finishNative(false)`, if `_batchIdx > 0` for move/trash kinds, still invoke a partial-completion path that pushes an undo entry covering only the completed subset, with an explicit "Cancelled after N of M items — undo available" notification.
- **Regression risk of fix:** Moderate — requires slicing `_batchQueue` at `_batchIdx` and differentiating from full-success/full-cancel paths; must avoid double-pushing undo.

---

### BUG-007 — [high] Failed copy/move (disk full, permission denied, source vanishes) leaves a truncated partial artifact on disk
- **Lens:** fs-edge-cases
- **File:** `backend/FileOperations_Copy.cpp` / `backend/FileOperations_Move.cpp`
- **Function:** `FileOperations::copy` (L6-43) and `FileOperations::move` (L6-54), cross-filesystem branch
- **Mechanism:** When `copyTree()`/`copyFile()` fails, destination cleanup (`forceRemove(destination)`) is gated strictly on `err == QLatin1String("cancelled")` (Copy.cpp L34-39; Move.cpp L42-47 for the EXDEV fallback). Any **other** failure — disk full (`out.write() != n` → `"write failed on <dst>"`, `FileOpsPrivate.h` L81-83), permission denied partway through a large tree, or a source vanishing mid-tree — leaves whatever was already written at the destination, uncleaned, with no indication to the user that it's partial/corrupt. `run()`'s wrapper in `FileOperations.cpp` only forwards `Result` to signals; no rollback/cleanup logic exists there.
- **Repro:** Copy a file larger than the free space on the destination filesystem (e.g. a size-limited tmpfs/loop mount). The copy fails with "write failed on `<dst>`"; `ls` shows a truncated file still present at the destination; retrying without overwrite now fails with "destination already exists" instead of cleanly retrying.
- **Impact:** Disk-full mid-copy leaves a truncated, half-written file or partially-populated directory tree at the destination, indistinguishable from a real file until inspected. A retry without `overwrite=true` fails with a confusing "destination already exists."
- **Proposed fix:** Replace the `if (err == "cancelled") forceRemove(destination);` guard with an unconditional `forceRemove(destination);` before returning `{false, err}` from the failure branch — since this code only runs after the pre-existing-destination guard already returned early, it can only ever delete content this operation itself just wrote.
- **Regression risk of fix:** Low-medium — reuses the existing best-effort `forceRemove()` already used for the cancellation case; for `move()`'s EXDEV fallback, ensure `removeTree(source,...)` is still skipped when the copy step failed (already the case).

---

### BUG-013 — [medium] "Extract Here" has no independent zip-slip / path-traversal check
- **Lens:** security-bugs
- **File:** `logic/ActionEngine.qml`
- **Function:** `extractHere(entry)` (~lines 905-934)
- **Mechanism:** Builds `unzip -o -q <path> -d <dir>` / `7z x -y <path> -o<dir>` / `unrar x -o+ <path> <dir>/` / `tar xf <path> -C <dir>`, run via `bash -c`. The only pre-extraction check (`extractListProc`, lines 905-933, feeding `runPendingExtract()` at 1162-1169) is a **name-collision** check against top-level entries, not a path-traversal check — an archive member with `"../"` segments or an absolute path is never filtered before extraction. Safety is delegated entirely to the extraction binaries. `runAction()` executes the raw command string via `bash -c` unconditionally (line 92).
- **Repro:** Not reproducible against the currently-installed toolchain on this machine (GNU tar 1.35 refuses `..` entries with exit 2; `unzip` strips leading `../`; 7-Zip 26.02 confines output to `-d`). Flagged as a defense-in-depth gap rather than a currently-triggerable bug — the app performs zero independent validation, so safety is entirely a function of which tool version happens to be installed. Could not build a test `.rar` to check `UnRAR` directly, though 7.23 postdates the CVE-2022-30333 symlink/traversal fix class.
- **Impact:** If the system's extraction tool does *not* sanitize `..`/absolute paths (older/alternate/minimal builds, containers, some distros), "Extract Here" on a malicious archive can write files outside the target folder — classic zip-slip.
- **Proposed fix:** Reuse the already-computed `extractListProc` listing to reject/warn if any member name contains a `..` segment or starts with `/`, instead of relying solely on third-party tool behavior.
- **Regression risk of fix:** Low — legitimate archives essentially never contain literal `..` segments.

---

### BUG-008 — [medium] `rename()` uses symlink-blind existence checks — breaks on broken symlinks, can silently clobber
- **Lens:** fs-edge-cases
- **File:** `backend/FileOperations.cpp`
- **Function:** `FileOperations::rename` (L88-100)
- **Mechanism:** Checks source/destination with plain `QFileInfo::exists(path)`/`QFileInfo::exists(dst)` instead of the lstat-aware `FileOpsPrivate::entryExists()` helper the rest of the file deliberately uses (`existingPaths()`, `copy()`, `move()`) specifically to handle broken symlinks (doc comment at `FileOpsPrivate.h` L24-35 references "BUG-01, Hardening-1"). `QFileInfo::exists()` follows symlinks and returns `false` for a broken one. Consequences: (1) if the source is itself a broken symlink, the source-exists check (L91) wrongly reports "source does not exist," refusing a rename of an entry the user can plainly see in the file list; (2) if a broken symlink occupies the destination name, the destination-exists check (L93) misses it, so the unconditional `::rename()` syscall silently clobbers it — contradicting the function's own "Does not overwrite" doc comment.
- **Repro:** `ln -s /nonexistent /tmp/opsdir/badlink`; call `rename("/tmp/opsdir/badlink", "renamed")` → `error("rename", path, "source does not exist")` despite `ls -la` showing the symlink. Separately, create a second broken symlink at the target name and rename onto it — it silently disappears with no conflict error.
- **Impact:** Renaming a broken symlink is currently impossible via this native invokable. Renaming onto a broken-symlink-occupied name silently destroys it instead of surfacing the no-overwrite conflict. Currently exercised only by the selfcheck suite (`CheckFilesystemOps.qml` L20-31, which only tests a regular file, no symlink coverage) — **not yet wired to the live rename UI**, which still uses a shell `mv -n`/`mv -f` (`ActionEngine.qml` L490-495). Not user-facing today, but will become so the moment the live rename path migrates to this native function, consistent with the project's documented migration-from-shell trend.
- **Proposed fix:** Replace both `QFileInfo::exists()` calls with `entryExists()` (already in scope via `using namespace FileOpsPrivate;`).
- **Regression risk of fix:** Low — `entryExists()` is a superset of `exists()`; only changes behavior for the broken-symlink edge case.

---

### BUG-004 — [medium] Single process-wide cancellation flag shared across all FileOperations calls
- **Lens:** concurrency
- **File:** `backend/FileOperations.h` / `backend/FileOperations.cpp`
- **Function:** `std::atomic<bool> m_cancelled` (`FileOperations.h:162`), shared across `copy()`/`move()`/`remove()`/`emptyTrash()`/`restoreByOrigPath()`
- **Mechanism:** Exactly one cancellation flag for the entire `QML_SINGLETON`, not scoped per-operation. Every cancel()-supporting entry point resets it with `m_cancelled.store(false)` at its own start (`FileOperations_Copy.cpp:8`, `_Move.cpp:8`, `_Remove.cpp:7`, `_Trash.cpp:18` and `:96`); `cancel()` (`FileOperations.cpp:53`) sets it `true` unconditionally with no notion of "current operation." Safe today only because the sole production caller, `logic/ActionEngine.qml`, serializes all native calls behind its own per-instance `nativeBusy` property. But this serialization is enforced per-ActionEngine-**instance**, not inside `FileOperations` itself, and a second, independent instantiation pattern already exists in the codebase: `src/selfcheck/checks/CheckFilesystemTrash.qml:29-33` does `Qt.createComponent(ActionEngine.qml)` and creates its own standalone `ActionEngine` with its own separate `nativeBusy`, calling the same process-wide singleton.
- **Repro:** UNVERIFIED as directly reachable in the shipped app — demonstrated only structurally via the selfcheck harness's independent `ActionEngine` instantiation. `main.cpp:434-439` confirms `--selfcheck` runs as a fully separate OS process (`return runSelfCheck(argc, argv)` before any `QGuiApplication`/single-instance setup), so this second instance never actually shares process memory with a live user session today.
- **Impact:** No confirmed live trigger in the shipped production UI — reported as a **latent architectural fragility**. The shared, un-scoped `m_cancelled` flag has zero protection at the C++ layer, and the codebase's own selfcheck harness demonstrates the exact bypass pattern that would turn it into a real cross-operation-cancellation bug the moment a second concurrent caller is added.
- **Proposed fix:** Scope cancellation per-operation: return an opaque token/handle from each entry point, and have `cancel(token)` only set a flag specific to that in-flight job (e.g. `QHash<token, shared_ptr<atomic<bool>>>`).
- **Regression risk of fix:** Medium — a real public API change to `FileOperations`' `Q_INVOKABLE` signatures and call sites; worth doing before any second production caller is introduced, not urgent given no live trigger found.

---

### BUG-017 — [medium] Cancelling a chained shell batch (bulk-rename/chmod) mid-way leaves partial changes un-undoable
- **Lens:** ux-regression
- **File:** `logic/ActionEngine.qml`
- **Function:** `cancelAction()` (lines 109-126) combined with `chainCmds()`-based batches: `runPendingBulkRename()` (lines 623-648) and `commitChmod()` (lines 655-688)
- **Mechanism:** Bulk rename and chmod join per-file commands into one `bash -c` script via `chainCmds()` (`{ cmd; } || st=1`, joined, `exit $st`), executed sequentially in a single `actionProc` process. `cancelAction()`'s non-native branch is just `actionProc.cancel(); _resetActionState()` — it kills the whole process group. If N of M sub-commands already ran before the kill, those renames/chmods already took effect on disk, but because the process is killed, `runAction`'s `onSuccess` callback — the **only** place `pushUndo()` is called for these two actions — never executes (`onFinished` only calls `cb()` `if (result.exitCode === 0)`). Confirmed via `backend/ProcessRunner.cpp`: `cancel()` sends `SIGTERM` to the whole process group; an un-trapped `bash -c` script terminates immediately without reaching `exit $st`, so both the success callback and the error-notify branch (`!result.cancelled`) are skipped — fully silent.
- **Repro:** Select 6 files, Bulk Rename with a pattern changing every name, click Rename, click Cancel after 2-3 of the chained `mv` commands have already executed. Those files stay renamed; Ctrl+Z has nothing to undo.
- **Impact:** Cancelling a bulk rename or recursive chmod mid-batch leaves already-processed files renamed/permission-changed on disk with zero undo entry registered — the shell-batch analogue of BUG-016.
- **Proposed fix:** Have `chainCmds` emit per-item completion markers (or split into tracked per-item `runAction` calls) so a mid-chain cancellation can still register a partial undo and notify the user.
- **Regression risk of fix:** Moderate — reworks a piece shared by rename/new-file/new-folder/chmod/link/compress/extract; must preserve the existing "one failure doesn't eat the others" guarantee.

---

### BUG-018 — [medium] Bulk-rename pattern has no empty/whitespace validation, unlike every sibling commit function
- **Lens:** ux-regression
- **File:** `dialogs/BulkRenamePanel.qml` (lines 56-64, 119-125) and `logic/ActionEngine.qml` `commitBulkRename()` (lines 871-903)
- **Mechanism:** `BulkRenamePanel` emits `renameRequested(bulkRenameField.text)` verbatim on Enter or the Rename button, with no trim/empty check anywhere (confirmed: no validator on the shared `TextField.qml` base, no `enabled:` gating on the button). `commitBulkRename()` computes `newName` via token substitution with **no validation** that the result is non-empty/non-whitespace — unlike `commitRename()` (L949: `.trim(); if (!newName || newName === oldName) return`), `commitNewFile()` (L969), and `commitNewFolder()` (L981), which all explicitly guard.
- **Repro:** Select 3+ files, open Bulk Rename, clear the field (Ctrl+A + Delete), press Enter. Traced concretely: `Utils.js` `joinPath(base, "") = base + "/"`; `FileOperations::existingPaths()` → `entryExists()` resolves a trailing-slash path to the directory itself, which *does* exist, so every selected file is flagged as colliding with the directory — producing a nonsensical confirm dialog ("N renames would collide... and will be skipped"). With a whitespace-only pattern, the first file in iteration order is actually renamed to a literal-space filename (valid but effectively invisible), the rest silently skipped via `mv -n`.
- **Impact:** Reachable purely through the UI with no validation blocking it, inconsistent with every other create/rename entry point in the app.
- **Proposed fix:** Trim the pattern in `commitBulkRename()` (or in `BulkRenamePanel` before emitting) and bail with a clear notification if empty, mirroring the existing guards on the sibling commit functions.
- **Regression risk of fix:** Low — purely additive validation matching an existing pattern.

---

### BUG-005 — [low] ProcessWatcher restart can silently fail to relaunch (dead code, but live/compiled)
- **Lens:** concurrency
- **File:** `backend/ProcessWatcher.cpp`
- **Function:** `ProcessWatcher::start()` (lines 18-40)
- **Mechanism:** On restart of an already-running process, `start()` calls `m_proc->terminate()` then blocks the calling thread with `m_proc->waitForFinished(500)`; on timeout it calls `m_proc->kill()` and **immediately falls through** to `m_proc->start(program, command)` without waiting for the kill to actually reap the process. `QProcess::start()` is a documented Qt no-op (with a `qWarning` + error state, unchecked here) if the process is not yet `NotRunning`. `active()` just reflects `m_proc->state()`, so a failed restart leaves the watcher looking idle, never emitting `lineRead` again, with no error signal on the class to report it.
- **Repro:** UNVERIFIED as reachable — grepped every `.qml` file in the repo and found **zero** instantiations of `Backend.ProcessWatcher`. It is compiled and QML-registered (`QML_ELEMENT`) via `CMakeLists.txt` but appears to be dead code left over from before the Phase 34.5 filesystem-watcher refactor, which replaced its use with `DirectoryModel::watch()`'s `QFileSystemWatcher`-based approach.
- **Impact:** If wired back up in the future and `start()` is called twice in quick succession while the wrapped process resists SIGTERM for the full 500ms, the second start silently fails, permanently breaking that watcher instance until an explicit `stop()`/`start()`. Also blocks the calling thread (GUI thread if invoked from QML) for up to 500ms.
- **Proposed fix:** After `kill()`, also `waitForFinished(-1)` (or bounded) before calling `start()`, and check/propagate `QProcess::errorOccurred` so a failed restart is at least observable.
- **Regression risk of fix:** Low — no current callers; if reused, blocking longer on old-process shutdown is the safer default.

---

### BUG-010 — [low] Background-panel empty state reads literal "undefined" for zero-result searches
- **Lens:** qml-binding
- **File:** `panels/BackgroundPanel.qml`
- **Function:** `EmptyState` `message` binding (line 293)
- **Mechanism:** Reads `bgPanel.bgSearchQuery`, but the file never declares that property — only `bgSearching`, `bgSearchEntries`, and `bgVisibleSearchEntries` (which internally computes a local `q` from `modelData.searchQuery` but never exposes it under that name) exist. Accessing an undeclared QML property yields `undefined` (no thrown error), and `"str" + undefined` → the literal string `"undefined"` via JS coercion.
- **Repro:** Run a global search with 0 matches (e.g. "zzzzzz") in the active tab, then switch tabs so the searching tab becomes a background panel. Expected: `No results for "zzzzzz"`. Actual: `No results for "undefined"`.
- **Impact:** Cosmetic but user-visible; undermines trust in the rest of the search UI.
- **Proposed fix:** Add `readonly property string bgSearchQuery: modelData.searchQuery || ""` next to the existing search-related properties.
- **Regression risk of fix:** Trivial.

---

### BUG-011 — [medium] Non-default sort (date/size/name-desc) runs a synchronous, allocation-heavy JS sort on the UI thread for every listing
- **Lens:** qml-binding
- **File:** `state/SortState.qml` (`sortEntries`/`compareEntries`), invoked from `logic/DirLister.qml` `_sorted()` and directly from `SortState.setSort()`/`reverseSort()`
- **Mechanism:** `DirLister._sorted(raw)` (lines 112-114) only skips JS-side sorting when `SortState.isDefaultOrder` (name-ascending, already returned pre-sorted by C++ `DirectoryModel`) is true. For **any** other sort (size, date, type, or name-descending), `SortState.sortEntries(raw)` still runs synchronously on the UI thread on every listing/refresh; `setSort()`/`reverseSort()` (lines 45-58) additionally re-sort `NavState.entries` synchronously and unconditionally on every sort-control click, with no size threshold. `compareEntries()` falls back to `Utils.naturalCompare()` for ties (and unconditionally for the "name" key, used whenever `sortDesc=true`), which does two regex-driven `String.replace` calls per comparison, building fresh JS arrays via `push`, plus `localeCompare` — real per-comparison allocation cost, invoked O(n log n) times by `Array.sort`. Grepped `SortState.qml`/`DirLister.qml`/`NavigationController.qml` for `WorkerScript`/`Qt.callLater`/`setTimeout`/`requestAnimationFrame` — zero hits, confirming fully synchronous UI-thread execution. `DirectoryModel.cpp` has no entry-count cap upstream.
- **Repro:** Open a folder with tens of thousands of entries (or Trash), set sort to Date or Size, refresh/navigate or toggle descending — the UI thread blocks proportional to entry count. Exact duration not measured in-session (no benchmark harness exercises this path); severity is plausible/order-of-magnitude, not a hard measured number.
- **Impact:** For a large directory (the repo's own `bench/gen-datasets.py` models 50k-100k entries as realistic scale), sorting by anything other than default name-ascending triggers a full O(n log n) JS sort with non-trivial per-comparison cost, synchronously on the UI thread, on every folder open/refresh and every sort-control click. The project's own Phase 38 performance-gate report (`docs/historical/PHASE38_PERFORMANCE_REGRESSION_REPORT.md`) never benchmarks `sortEntries`/`naturalCompare` at any scale (confirmed via grep, zero matches) — its "READY FOR RELEASE" verdict says nothing about this code path; it is untested, not verified-clean. An additional unguarded call site not covered by the original candidate was found at `logic/ActionEngine.qml:1187` (`NavState.entries = SortState.sortEntries(parsed)`).
- **Proposed fix:** (a) Extend the native `DirectoryModel`/backend to accept a sort key + direction so C++ produces already-sorted results for non-default orders too, removing the JS sort entirely; or (b) precompute a cheap sort key per entry once (Schwartzian transform) and/or move the sort off the UI thread (`WorkerScript`) with the same stale-result guard pattern `DirLister` already uses.
- **Regression risk of fix:** Moderate — risks subtly changing ordering behavior (natural-compare edge cases, locale differences); an off-thread move introduces async ordering/races needing the same request-id guarding used elsewhere (e.g. `PreviewContentState._previewTextOwner`).

---

### BUG-014 — [low] Video-thumbnail cache path shares the predictable-symlink-target weakness (partially self-mitigated)
- **Lens:** security-bugs
- **File:** `logic/VideoThumbnails.qml` + `scripts/runtime/thumbnail-video.sh`
- **Function:** `processThumbQueue()`/`thumbProc` (`logic/VideoThumbnails.qml` lines 23-40)
- **Mechanism:** Same systemic pattern as BUG-012: `dest = thumbCacheDir + "/" + ThumbnailProvider.cacheKey(thumbKeyFor(entry, basePath)) + ".jpg"` is a deterministic, unsalted, offline-computable path. `thumbnail-video.sh` does `[[ -f "$dest" ]] && exit 0` **before** calling `ffmpegthumbnailer -i "$src" -o "$dest"` — `-f` follows symlinks, so a pre-planted symlink at the predictable `dest` pointing at an *existing* regular file causes early exit, neutralizing the common case. **Not fully closed**: if the symlink points at a not-yet-existing (dangling) path, `-f` is false, the script proceeds, and `ffmpegthumbnailer` creates/writes through the symlink at the attacker-chosen location. Written bytes are an actual rendered JPEG derived from the real video, not free-form attacker content, limiting (not eliminating) practical impact.
- **Repro:** Empirically reproduced against the live installed `ffmpegthumbnailer` binary: (1) dangling-symlink case — pre-planted a symlink at the predictable dest pointing to a not-yet-existing external path; the unmodified script proceeded past the `-f` check and wrote a genuine JPEG through the symlink to the attacker-chosen path, confirming the mechanism is real, not theoretical. (2) pre-existing-file case — symlink pointed at an existing regular file; the `-f` check correctly caught it, content preserved, confirming the common case is already mitigated.
- **Impact:** Low on its own (content isn't attacker-controlled; common case already blocked) but shares the same root design weakness as BUG-012 (predictable, unsalted per-item cache paths combined with a write that follows symlinks).
- **Proposed fix:** Same as BUG-012: `rm -f -- "$dest"` immediately before the `ffmpegthumbnailer` call.
- **Regression risk of fix:** Very low — mirrors existing cache-invalidation semantics.

---

### BUG-019 — [low] Bulk-rename conflict dialog undercounts skipped files when 3+ items collide on one name
- **Lens:** ux-regression
- **File:** `logic/ActionEngine.qml`
- **Function:** `commitBulkRename()` (lines 871-903)
- **Mechanism:** `bulkRenameInternalDupes` is `Object.keys(targetCounts).filter(k => targetCounts[k] > 1).length` — the number of **distinct colliding target names**, not the number of files that will actually be skipped. `runPendingBulkRename()` (lines 623-648) turns each surviving rename into an independent `mv -n -- oldPath newPath`, chained via `chainCmds` with no short-circuit — so with 3 files colliding on the same generated name, the first `mv` succeeds and the other 2 are silently skipped, but the dupe count reports only 1 (one colliding key), not 2.
- **Repro:** Select 3 files sharing an extension, pattern like `"backup{ext}"` (no `{n}` token) so all three compute the same `newName`. Dialog reports "1 rename would collide... and will be skipped" when the real number is 2.
- **Impact:** The pre-confirm dialog (`core/DialogLayer.qml` lines 312-326) undercounts how many renames will actually be skipped whenever 3+ files collide on the identical generated name.
- **Proposed fix:** Sum `targetCounts[k] - 1` over all keys with count > 1, instead of counting the number of colliding groups.
- **Regression risk of fix:** Very low — purely a display/count computation, no effect on which files are actually renamed.

---

### BUG-020 — [low] Shared error-toast fallback string is hardcoded to a trash-restore message for 8 unrelated actions
- **Lens:** ux-regression
- **File:** `logic/ActionEngine.qml`
- **Function:** `actionProc`'s `Connections.onFinished` (lines 278-289) — the single `ProcessRunner` shared by rename, new-file/new-folder overwrite, bulk rename, chmod, link, compress, and extract
- **Mechanism:** On failure with empty `stderr`, the fallback message is hardcoded: `Backend.Notifier.notify(result.stderr.trim() || "Couldn't restore from trash")`. This exact `ProcessRunner` instance backs every shell-based action in the file (confirmed via grep of `runAction(` call sites: rename L491/493/495, new-file L536, new-folder L564/566/568/596, bulk-rename L637/643/645, chmod L676/683/685, symlink L712/714/716, compress L1154, extract L1168). Notably, "restore from trash" **itself doesn't even use this path anymore** — `restoreFromTrash()` routes through the native `_runNative`/`Backend.FileOperations` path with its own separate `Connections.onError` handler; this is a stale leftover string from before restore was migrated to the native backend.
- **Repro:** Trigger any shell-based action that fails without writing to stderr (tool/locale-dependent) — the toast reads "Couldn't restore from trash" regardless of what was actually attempted.
- **Impact:** Any of rename/new-file/new-folder-overwrite/bulk-rename/chmod/link/compress/extract that fails with empty stderr shows a nonsensical, wrong-context error toast — actively misleading the user.
- **Proposed fix:** Use a generic action-agnostic fallback like "Action failed" (already used elsewhere, e.g. `Connections.onError` line 176), or pass a per-call fallback message into `runAction()`.
- **Regression risk of fix:** Very low — cosmetic string fix.

---

## Regression Matrix

Verification of five self-reported "fixed" historical incident reports against current source (not taken at face value).

| Report | Subsystem | Still fixed? | Notes |
|---|---|---|---|
| `PHASE34_2_PREVIEW_REGRESSION_REPORT.md` | Preview pipeline (`PreviewProvider`, `PreviewState.qml`, `PreviewContentState.qml`) | **TRUE** | Original bug: `panels/ActiveFileList.qml` called `root.isImage/isVideo/isPdf/isAudio(...)` where `root` was the wrong object, making all preview-type booleans evaluate false. Confirmed current source uses `Utils.isImage/isVideo/isPdf/isAudio(...)` throughout (lines 281-288), matching the claimed fix. Repo-wide grep for stale `root.is*(...)` calls returns zero matches. `shared/Utils.js` (moved from repo-root post-refactor — benign path drift) defines the pure helper functions as expected. Same pattern verified correct at all other call sites (`FileListRow.qml`, `BackgroundListDelegate.qml`, `PreviewLoader.qml`). Verification was static/source-level only — did not run a built binary for this specific check. |
| `PHASE37_TRASH_UNDO_FAILURE_REPORT.md` | Trash + undo (`FileOperations_Trash.cpp`, `UndoState.qml`, `TrashState.qml`) | **TRUE** | Original bug: undoing a trash on a file inside a symlinked directory failed with "no matching trashed item" due to strict string comparison against canonicalized paths. Confirmed the claimed 3-way match (`decoded == origPath` / `QDir::cleanPath` / `canonicalPathForFile`) is present verbatim in current `FileOperations_Trash.cpp:119-121`, and `canonicalPathForFile()` still exists in `FileOpsPrivate.h:232-241`. Traced the full undo call path through `ActionEngine.qml` intact. **Empirically confirmed** by building and running the actual `--selfcheck` binary: 85/85 passed, including "Trash + restore from symlinked directory (path normalization)" which reproduces the exact original bug scenario. |
| `PHASE37_UNDO_REDO_REGRESSION_REPORT.md` | Undo/redo pipeline (`UndoState.qml`, `ActionEngine.qml`) | **TRUE** | The report itself never states an actual bug (it's an audit-trace/verification-matrix document whose cited "Phase 37" commit scope is unrelated to undo/redo). The real substantive fix was traced to a different commit not mentioned in the report's own scope (`7f8b8ad`, "restore trash undo path resolution" — same underlying fix verified for the report above). Confirmed this fix survived the later `37f3f318` architecture-consolidation commit unchanged (`git log` on the relevant files since shows no further changes). Core undo/redo mechanics (LIFO pop, 20-entry cap, re-queue-on-busy-failure) verified intact in current `ActionEngine.qml` lines 30-72. **Empirically confirmed**: live `--selfcheck` run, 85/85 passed including all undo/redo-specific checks. |
| `PHASE38_PERFORMANCE_REGRESSION_REPORT.md` | Performance (native listing/search/file-ops benchmarks) | **TRUE** | This document is a clean-pass benchmark gate snapshot (0 regressions, 2 improvements, 2 sub-threshold warnings, "READY FOR RELEASE") rather than a bug+fix narrative. Verified the report faithfully renders `bench/baseline.json` and matches `bench/bench-gate.py`'s actual output format byte-for-byte. Confirmed `backend/` has zero uncommitted changes since the benchmark was taken. **Independently re-ran the full gate today** against current committed source (real recompile of `bench/perfbench.cpp` against live `DirectoryModel.cpp`, real re-execution of `measure-search.qml`/`measure-ui-guard.qml`): PASSED, 0 regressions. Two different metrics tipped into the 3-8% warning band this run than in the original (normal run-to-run noise), never crossing the 8% regression line either time. Methodological caveat: the directory-navigation benchmark uses only a single run (not a median of several like other metrics), making that specific number noisier than the rest of the gate. |
| `PR2_RUNTIME_FAILURE_REPORT.md` | Runtime/install (Zen Browser file-picker D-Bus integration) | **FALSE** | The narrowly-documented original fix (the `cp -r "$SELF_RES/scripts" "$RES_DIR/"` fallback + `$RES_DIR`-based `Exec=` paths in `scripts/install-integrations.sh`) **is** genuinely present and correct in current source. However, a **fresh, currently-live regression** was found one layer up the call chain: `core/AppBindings.qml:32` now invokes `Paths.resourceDir + "/scripts/runtime/scripts/install-integrations.sh"` — a path that has never existed on disk (confirmed via `find`). `git blame` traces this to the same `37f3f318` consolidation commit (2026-08-15) that moved five *other* helper scripts into `scripts/runtime/` but did not move `install-integrations.sh` (which still lives at `scripts/install-integrations.sh`), leaving what looks like a copy/rename mistake. `backend/Detached.cpp::run()` discards `QProcess::startDetached()`'s boolean return, so the failure is completely silent — the same "nothing happens" failure mode the original report complained about. Net effect: on any fresh install, the integration-registration script (and thus the D-Bus filechooser fix) never runs automatically. Not caught by the 85-selfcheck suite (`CheckIntegration.qml` has no reference to `install-integrations`/`AppBindings`/`resourceDir`). On this specific machine the regression is currently masked by a stale `~/.local/state/omafiles/integrations-version` file from a prior successful run — incidental, not evidence the pipeline works end to end. **Follow-up fix needed:** `core/AppBindings.qml:32` should read `Paths.resourceDir + "/scripts/install-integrations.sh"`. |

---

## Appendix: Refuted Candidates

Included for transparency about what was considered and rejected during adversarial verification, with the specific reasoning that refuted each one.

### REFUTED — backend/PreviewProvider.cpp: claimed use-after-free via unguarded `invokeMethod(this, ...)`
- **Original claim [high]:** Identical pattern to the ThumbnailProvider finding — `requestAudio()`/`requestText()` QThreadPool lambdas capture raw `this`, do the actual work in free/static-ish calls, then call `QMetaObject::invokeMethod(this, ..., Qt::QueuedConnection)` on the worker thread with zero life-guard, on a `QML_SINGLETON` destroyed only at app teardown with nothing draining the thread pool first.
- **Refutation:** The code structure matches the claim exactly (`requestAudio()` lines 28-44, `requestText()` lines 73-117; no `QPointer`/guard wraps `this`). But the conclusion is wrong about the specific Qt API in use. `QMetaObject::invokeMethod(QObject *context, Functor&&, Qt::ConnectionType)` — the overload used here — treats `this` as the **context/receiver**, using the same underlying QObject destruction-safety plumbing as `connect(sender, signal, context, functor)` and the documented `QTimer::singleShot(interval, context, functor)` idiom ("the functor will be called only if the context object has not been destroyed before the interval occurs," per Qt docs). Qt's QObject destructor purges/cancels any pending queued deliveries targeting that object before teardown completes. The outer lambda never dereferences `this` directly — it only does file I/O / `SyntaxHighlighter::highlight` / `MediaInfo::extract` (free/static calls, as the original claim itself notes), then hands the pointer to `invokeMethod` as the context. If `PreviewProvider` is destroyed between work-start and delivery, the posted call is discarded by Qt's own machinery before the inner lambda (which touches member state) ever runs. Worst case: a silently dropped result at shutdown — the intended, safe behavior of this idiom, not a crash. This is precisely the guarded idiom Qt provides for this scenario, used correctly.

### REFUTED — backend/FolderCounter.cpp: claimed cross-thread QPointer TOCTOU race
- **Original claim [medium]:** `QPointer<FolderCounter> self(this)` captured into a QThreadPool lambda, checked with `if (self)` before `QMetaObject::invokeMethod(self, "counted", Qt::QueuedConnection, ...)` on the worker thread — claimed QPointer's auto-nulling is documented as unsafe across threads, with a TOCTOU gap between the check and the use.
- **Refutation:** The code matches the claim exactly (line 13 `QPointer<FolderCounter> self(this)`, lines 33-35 `if (self) QMetaObject::invokeMethod(self, ...)`), and `FolderCounter` is confirmed `QML_SINGLETON`. But the "QPointer is unsafe across threads" premise is outdated for the Qt6 codebase this project uses (confirmed via `CMakeLists.txt`, `find_package(Qt6 REQUIRED ...)`). The cross-thread guard-clearing race was a real Qt4 bug (QTBUG-16005, fixed in 4.8.0); a further related crash (QTBUG-21715) was fixed in Qt 5.0.0 by double-checking the pointer under a mutex before and after acquiring the guard lock — since Qt5, reading a QPointer from another thread while the tracked object is concurrently destroyed is memory-safe (atomically old value or nullptr, no internal crash). Additionally, `self` is not a cached raw pointer — every use (`if (self)` and the argument expression itself) is an independent, freshly-guarded read; even in the theoretical gap, the second read would very likely also observe nullptr. `QMetaObject::invokeMethod` also internally null-checks its target. This is the standard, Qt-recommended idiom for exactly this scenario (worker thread signaling back to a possibly-destroyed QObject), not a misuse of it — no concrete crash or demonstrated failure was shown, only a theoretical nanosecond-scale TOCTOU common to the whole idiom in general.

---

## Files Referenced

`logic/ActionEngine.qml`, `backend/SearchWorker.cpp`, `backend/SearchWorker.h`, `backend/ThumbnailProvider.cpp`, `backend/ThumbnailProvider.h`, `backend/FileOpsPrivate.h`, `backend/FileOperations.cpp`, `backend/FileOperations.h`, `backend/FileOperations_Copy.cpp`, `backend/FileOperations_Move.cpp`, `backend/FileOperations_Trash.cpp`, `backend/DirectoryModel.cpp`, `backend/PreviewProvider.cpp`, `backend/FolderCounter.cpp`, `backend/ProcessWatcher.cpp`, `backend/ProcessRunner.cpp`, `backend/Detached.cpp`, `core/ControllerRegistry.qml`, `core/MainLayout.qml`, `core/DialogLayer.qml`, `core/AppBindings.qml`, `core/CommandFacade.qml`, `logic/KeyboardShortcuts.qml`, `logic/SearchBackend.qml`, `logic/SearchOps.qml`, `logic/DirLister.qml`, `logic/NavigationController.qml`, `logic/TabOps.qml`, `logic/VideoThumbnails.qml`, `panels/BackgroundPanel.qml`, `panels/ActiveFileList.qml`, `panels/FileListRow.qml`, `panels/BackgroundListDelegate.qml`, `panels/PreviewPanel.qml`, `dialogs/BulkRenamePanel.qml`, `state/SortState.qml`, `state/UndoState.qml`, `state/TrashState.qml`, `shared/Utils.js`, `scripts/install-integrations.sh`, `scripts/runtime/thumbnail-video.sh`, `scripts/dbus-filechooser.py`, `src/selfcheck/checks/CheckFilesystemOps.qml`, `src/selfcheck/checks/CheckFilesystemTrash.qml`, `src/selfcheck/checks/CheckActions.qml`, `src/selfcheck/checks/CheckIntegration.qml`, `bench/bench-gate.py`, `bench/baseline.json`, `bench/perfbench.cpp`, `docs/historical/PHASE34_2_PREVIEW_REGRESSION_REPORT.md`, `docs/historical/PHASE37_TRASH_UNDO_FAILURE_REPORT.md`, `docs/historical/PHASE37_UNDO_REDO_REGRESSION_REPORT.md`, `docs/historical/PHASE38_PERFORMANCE_REGRESSION_REPORT.md`, `docs/historical/PR2_RUNTIME_FAILURE_REPORT.md`.

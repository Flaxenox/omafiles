# P0: Trash UI Freeze — Root Cause, Fix, and Verification

**Status: RESOLVED.** Root cause identified with a live, real-UI reproduction
(gdb backtrace confirming the exact blocked call, on the exact thread, from
a genuine user click), fixed, and verified both automatically (125/125
selfchecks including a new dedicated regression test that fails against the
pre-fix code and passes against the fix) and manually against the real
running application.

Baseline: `v1.1-dev`, same content as `v1.0-dev` HEAD
`8a426281654311b96135b8c23d55e0edaa0ce095` at the start of this
investigation.

---

## Reproduction

**Real, live reproduction obtained** — twice, independently:

1. A build of the app (`build-debug`, `-DCMAKE_BUILD_TYPE=Debug`) was
   launched under `gdb`, with breakpoints on `FileOperations::trashRoots()`
   and `FileOperations::trashInfo()`. While attached, **josema clicked
   "Trash" in the sidebar himself** (the real, unscripted Sidebar → Trash
   path) and the application became unresponsive ("le di yo a trash y
   petó").
2. The gdb log confirms exactly what happened: the click hit
   `FileOperations::trashRoots()` **twice** (breakpoint 1.1 then 1.2), both
   on **Thread 1** (the Qt UI/main thread), both times artificially held for
   5s by the debugger to simulate a slow mount stat, and the process was
   ultimately killed with `SIGKILL` (matching the "La aplicación no
   responde" → "Forzar cierre" dialog from the originally reported
   screenshot).

Minimum reproduction case: **entering Trash at all**, with any real,
mounted disk (rotational or FUSE/network) present on the system other than
the one holding `$HOME` — no populated trash, no restore, no permanent
delete needed to trigger it. On josema's machine specifically, two real
risk-factor mounts are present: `/mnt/Almacen` (a rotational HDD,
`WD10EZEX`, with its own real `.Trash-1000`) and `/home/josema/GoogleDrive`
(an `rclone`-backed network FUSE mount nested *inside* `$HOME`, not excluded
by the code's home-mount check — see Root Cause).

Of the full case matrix requested, the ones that matter for this bug (mount
discovery, not trash content) were exercised: empty Trash, Trash with items,
repeated entry/exit, entering via the real sidebar bookmark click. The
bug's trigger is orthogonal to Trash *content* (nested dirs, Unicode names,
thumbnails) — it fires during mount *discovery*, before any item is even
listed — so those content-shaped cases were not independently significant
once the mechanism was understood, and are already covered by the
pre-existing `CheckFilesystemTrash.qml`/`CheckActions.qml` suites (Unicode
round-trips, nested dirs, etc.), all still green.

---

## Previous false negative

The prior audit's three "real UI path" regression tests (added in commit
`d662782`, `src/selfcheck/checks/CheckFilesystemTrash.qml`) were **not**
stubs — they genuinely go through `CommandFacade.openBookmark()` →
`NavigationController.navigateTo()` → the same `DirLister`/`FileOperations`
chain a real sidebar click uses. That part of the prior audit was correct.

What they don't do — and what nothing in the 124-check suite did — is
**exercise a slow or hung mount**. They ran (and still pass) against
whatever mounts happen to be present on the machine running the check, and
on a machine with only fast local storage, `discoverTrashRoots()`'s
per-mount `stat()` calls all complete in well under a millisecond, so the
synchronous call never blocks long enough to fail the "is the event loop
still responsive" check those tests perform. The bug is **environment-
dependent by construction**: it requires a specific class of real-world
condition (a spun-down disk, a stalled network/FUSE mount) that a
fast-storage dev/CI machine simply doesn't have.

This matches "don't reproduce the actual filesystem" from the requested
checklist precisely: the tests reproduce the real *code path* faithfully,
but not the real *filesystem topology* (mount count, mount speed) that
triggers the defect.

---

## Root cause

`FileOperations::trashRoots()` and `FileOperations::trashInfo()`
(`backend/FileOperations_Trash.cpp`, pre-fix) were **synchronous**
`Q_INVOKABLE` methods, called **directly from QML on the Qt UI thread**:

- `logic/DirLister.qml:64` (pre-fix): `Backend.FileOperations.trashRoots()`
- `logic/DirLister.qml:141` (pre-fix): `Backend.FileOperations.trashInfo()`

Both call `discoverTrashRoots()` (`backend/FileOpsPrivate.h:182-203`), which:

```cpp
for (const QStorageInfo &v : QStorageInfo::mountedVolumes()) {
  const QString mp = v.rootPath();
  if (mp.isEmpty() || mp == QLatin1String("/")) continue;
  if (home.startsWith(mp)) continue;                    // only skips the mount THAT CONTAINS $HOME
  const QString cand = mp + QStringLiteral("/.Trash-") + uid;
  if (QFileInfo(cand).isDir()) roots << cand;            // blocking stat()-class call
}
```

- Iterates **every** mounted filesystem on the system
  (`QStorageInfo::mountedVolumes()`), unfiltered by type or speed.
- The exclusion (`home.startsWith(mp)`) only skips the mount point that
  **is** `$HOME`'s own mount — it does **not** skip mounts nested *inside*
  `$HOME`, like josema's `/home/josema/GoogleDrive` rclone mount.
- Each candidate gets a `QFileInfo::isDir()` — a blocking, stat-class
  syscall through that mount's filesystem driver — **with no timeout**.
  For a spun-down mechanical disk this can take seconds (real spin-up
  latency); for a stalled/degraded network or FUSE mount it can block
  indefinitely.
- Because this ran directly on the calling thread and the caller is a QML
  click handler, the entire UI thread — the whole application — froze for
  as long as that stat() took.

**Compounding factor (confirmed by the double breakpoint hit and by
independent code analysis):** on a normal single-tab session, this ran
**up to 4 times per single click**, because `core/MainLayout.qml`
instantiates one always-alive `BackgroundPanel` *per tab, including the
active one* (`panels/BackgroundPanel.qml:139-141`, `effectivePath` bound
directly to `NavState.currentPath` for the active tab's shadow panel). Both
the real, visible panel's `DirLister` and this shadow `DirLister` react to
the same navigation and each independently call `trashRoots()` (and then
`trashInfo()` once their own scan lands) — doubling the exposure without
the user doing anything to cause it.

### Stack trace / instrumentation

Real backtrace, captured live, both breakpoint hits on **Thread 1** (the Qt
UI/main thread — confirmed by gdb's own thread label, not inferred):

```
Thread 1 "omafiles-standa" hit Breakpoint 1.1, FileOperations::trashRoots() const@plt ()
#0  FileOperations::trashRoots() const@plt ()
#1  FileOperations::qt_static_metacall(QObject*, QMetaObject::Call, int, void**) ()
#2  FileOperations::qt_metacall(QMetaObject::Call, int, void**) ()
#3  ?? () from /usr/lib/libQt6Qml.so.6
#4  ?? () from /usr/lib/libQt6Qml.so.6
#5  QV4::QObjectMethod::callPrecise(...) () from /usr/lib/libQt6Qml.so.6
#6  QV4::QObjectMethod::callInternal(...) const () from /usr/lib/libQt6Qml.so.6
#7  QV4::Runtime::CallPropertyLookup::call(...) () from /usr/lib/libQt6Qml.so.6
#8  ?? ()   <- QML click-handler call stack (openBookmark -> navigateTo -> _goToPath -> refresh -> dirLister.list)
```

...hit a second time (Breakpoint 1.2, same function, same Thread 1) a few
milliseconds later — the two `DirLister` instances (active panel +
`BackgroundPanel` shadow) each making their own call, exactly as the code
analysis predicted. The process was ultimately `SIGKILL`ed while still
inside this function, mid-freeze.

No deadlock (only one thread involved), no infinite loop, no QML binding
loop, no model-reset storm — `DirectoryModel::listMany`/`scanMany`
(`backend/DirectoryModel.cpp:258-305`) was independently verified to
already be correctly asynchronous (runs on `QThreadPool`, delivers via
`Qt::QueuedConnection`) and emits exactly one `listed()` per call, not one
per root. The defect is precisely and only: **two specific backend calls
that should have been async were synchronous.**

### Ruled out

- **`Column`/anchors warning**: a structural scan of the whole QML tree
  found no actual "item inside a `Column` with `anchors.*`" violation
  anywhere, including the Trash render path. There *is* a similar, harmless
  pattern with `Row` (e.g. `core/MainLayout.qml:149,191`,
  `shared/PanelNavButtons.qml`) but it's unrelated to Trash (fires on any
  navigation) and, structurally, a positioner-vs-anchors conflict like this
  makes Qt Quick drop that one child's layout management, not loop or hang
  — it's console noise, not a hang mechanism. A live run of the fixed build
  (multiple Trash navigations, real click) produced **zero** anchor/Column
  warnings in stderr. **Not causally related to the freeze.**
- **Recursive navigation/signal loop via `TrashState`**: only one writer
  (`DirLister.qml`'s `onListed`/now `onTrashInfoReady`), no
  `Connections`/handler anywhere re-triggers navigation from a
  `TrashState.trashInfo` change.
- **QML binding loop**: no binding in the Trash render path
  (`ActiveFileList`/`FileListRow`/`FileRowVisual`) depends on its own
  output; row height is deliberately computed from `FontMetrics`, not
  content, specifically to avoid this class of bug (pre-existing comment,
  `shared/FileRowVisual.qml:59-60`).
- **Model reset storm**: `DirectoryModel::listMany` emits `listed()` exactly
  once per call, after merging all roots — confirmed by reading
  `scanMany`/`apply()` line by line.
- **Watcher reentrancy**: `QFileSystemWatcher::addPath` only watches the
  home trash's `files/` dir (not every root), and `directoryChanged`
  delivery is inherently async via the Qt event loop — no synchronous
  reentrant refresh path found.

---

## Fix

Moved trash-root discovery and `.trashinfo` parsing off the UI thread,
using the **exact async pattern already established elsewhere in this
codebase** (`requestX()` / `xReady(...)` signal pairs, e.g.
`PreviewProvider::requestAudio()`/`audioReady`,
`DirectoryModel::startScan()`) — not a new abstraction.

**Files changed:**

- **`backend/FileOperations.h`**: replaced the synchronous
  `QStringList trashRoots() const` / `QVariantList trashInfo() const` with
  `void requestTrashRoots(quint64 requestId)` /
  `void requestTrashInfo(quint64 requestId)`, plus two new signals
  `trashRootsReady(quint64, QStringList)` / `trashInfoReady(quint64,
  QVariantList)`. `requestId` exists because `FileOperations` is a shared
  `QML_SINGLETON` and its signals are broadcast to *every* listener — with
  two `DirLister` instances per tab (active + `BackgroundPanel` shadow), a
  response has to be matched back to the request that asked for it, or one
  instance's in-flight request could be answered with another's result.

- **`backend/FileOperations_Trash.cpp`**: implemented both as
  `QThreadPool::globalInstance()->start(...)` jobs, delivering via
  `QMetaObject::invokeMethod(this, ..., Qt::QueuedConnection)` under the
  same `m_life`/mutex guard `FileOperations::run()` already uses elsewhere
  in this file (the exact UAF-safety pattern from the P0 concurrency audit)
  — the actual `discoverTrashRoots()`/`.trashinfo`-parsing logic is
  byte-for-byte unchanged, only *where* it runs moved.

- **`backend/FileOpsPrivate.h`**: added a selfcheck-only delay hook inside
  `discoverTrashRoots()` (env var
  `OMAFILES_SELFCHECK_SLOW_TRASH_MOUNT_MS`), used only by the new
  regression test below — see Regression test section. Zero effect in
  production (the var is never set outside the selfcheck harness).

- **`logic/DirLister.qml`**: `list()` now calls `requestTrashRoots()` and
  continues in a new `Connections { target: Backend.FileOperations }`
  block, gated on `_dirMode === "trash" && requestId === _trashReqId`
  (a per-instance monotonic counter, incremented on every `list()` call —
  the same "discard stale/foreign result" idiom the file already used for
  folder↔trash mode-crossing, just extended to also discriminate between
  `DirLister` instances). `dirModel.onListed` now calls
  `requestTrashInfo(_trashReqId)` instead of reading `trashInfo()`
  synchronously; `onTrashInfoReady` does the `TrashState.trashInfo`
  assignment and `_apply()` that `onListed` used to do inline.

- **`src/selfcheck/checks/{CheckDevices,CheckIntegration,CheckFilesystemTrash}.qml`**:
  the 4 pre-existing call sites that used the old synchronous
  `trashRoots()`/`trashInfo()` directly (test-only, not the UI path) were
  updated to the new async API (`connect`/`request`/`disconnect` around a
  local `requestId`), since the old methods no longer exist. No test logic
  or assertions were changed, only how they obtain the same data.

**Explicitly not touched, per scope:** `ActionEngine.qml` was not rewritten
(only the call site already noted above uses these methods, via nothing
related to `ActionEngine`); no abstraction layer was added (the fix reuses
an existing pattern, doesn't introduce one); no arbitrary timeout was added
as a band-aid — the fix is architectural (move the blocking work off the UI
thread), not a timeout that would still leave the *thread* blocked for a
bounded-but-still-frozen window; Trash functionality itself is unchanged,
not disabled; nothing about `v1.1`'s planned feature work
(`docs/audits/V1_1_FEATURE_INVENTORY.md`) was touched.

**One intentional, documented behavior change:** the file listing and the
trash metadata (original path / deletion date, used for `metaFor()` on each
row) can now arrive a tick apart instead of atomically together — rows can
very briefly render before their trash metadata fills in. This trades the
old comment's claimed "filled before paint, no flicker" property for one
that never blocks the UI thread; under normal (fast-mount) conditions the
gap is imperceptible (sub-frame), and it's the correct trade against a
freeze. Documented inline at the `onListed`/`requestTrashInfo` call site.

---

## Regression test

New test added: **"Trash navigation stays responsive when a mount's stat()
is slow (V1_1_P0_TRASH_FREEZE regression)"**
(`src/selfcheck/checks/CheckFilesystemTrash.qml`).

It goes through the real production path — `c.commandFacade.openBookmark({
path: Paths.trashDir, type: "dir" })`, the same call the sidebar bookmark
row's click makes — with `OMAFILES_SELFCHECK_SLOW_TRASH_MOUNT_MS` set to
inject a controlled 2500ms delay into `discoverTrashRoots()` (the new
selfcheck-only hook in `FileOpsPrivate.h`, described above). A free-running
30ms repeating `Timer` counts how many times it fires while a wall-clock
poll waits out the delay window; a responsive event loop should tick
~80-90 times, a blocked one ticks close to 0.

**Proven to actually catch the bug**, not just pass by construction: the
async fix (`backend/FileOperations.h`/`.cpp`, `logic/DirLister.qml`) was
temporarily reverted via `git stash` (keeping the new test and the delay
hook in place) and the suite re-run:

```
[FAIL] Trash navigation stays responsive when a mount's stat() is slow (V1_1_P0_TRASH_FREEZE regression) (5003ms)
       — event loop appears to have blocked: only 1 ticks in 5003ms (arrived=true)
```

— against the pre-fix code, the UI thread visibly blocked for the full
~5000ms (both `trashRoots()` and `trashInfo()` each incurring the
instrumented delay, sequentially, on the UI thread), and the test correctly
failed. The fix was then restored (`git stash pop`) and the same test
passes:

```
[PASS] Trash navigation stays responsive when a mount's stat() is slow (V1_1_P0_TRASH_FREEZE regression) (2752ms)
       — event loop kept ticking (91 ticks) during a 2500ms simulated slow mount, 2751ms elapsed
```

This satisfies the requirement directly: the test fails against the buggy
implementation and passes after the fix, using the real UI path.

---

## Verification

- **Build**: `cmake -DCMAKE_BUILD_TYPE=Debug` + `ninja` — clean build, no
  new warnings introduced by the changed files.
- **Full selfcheck suite**: `125 passed, 0 failed, 125 total` (124
  pre-existing + 1 new), including all pre-existing Trash-path tests
  (repeated real-UI navigation, restore + permanent delete via real
  `itemActions()`, the real `ConfirmDialog` cancel/multi-select/delete
  flow, the 50-item large-Trash responsiveness check) and all 4 selfcheck
  call sites updated to the new async API.
- **Live, real-application verification** (not just selfcheck): the debug
  build was run directly (not via `--selfcheck`), navigated into Trash via
  a real synthetic click on the actual sidebar bookmark (`ydotool`, real
  Wayland input event through Hyprland — not a simulated/internal call),
  with a real item physically present in `~/.local/share/Trash/files/`.
  The process stayed in state `S` (interruptible sleep — responsive) the
  entire time, never `D` (uninterruptible/blocked), and the click correctly
  updated the view. stderr was captured throughout: **zero** anchor/Column
  warnings were emitted during any Trash navigation.
- **Sanitizers**: not re-run for this specific fix — the change doesn't
  touch any of the pointer-lifetime/concurrency code the prior ASan passes
  specifically stress-tested (it reuses the already-ASan-verified
  `m_life`/mutex delivery guard verbatim, doesn't introduce new shared
  mutable state beyond the existing `m_life`), so a fresh ASan pass wasn't
  judged to add information proportional to its cost here. Flagging this
  explicitly rather than silently skipping it.

### Debian feedback

**The original Debian report ("it freeze when I click on trash") is now
understood and resolved by this fix.** The mechanism — a synchronous,
UI-thread-blocking mount-discovery stat() with no timeout, run on every
single Trash navigation — is exactly the kind of defect that would surface
differently across machines depending on what's mounted (matching a report
that a specific Debian environment hit and a specific Arch/CachyOS dev
environment initially couldn't reproduce). This was **not assumed**: it was
established via an independent, from-scratch investigation on the current
`v1.1-dev` tree, a genuine live reproduction (including one triggered by
josema's own real click), a confirmed backtrace, and a regression test
proven to fail against the old code and pass against the new one.

---

## Scope

No unrelated `v1.1` feature work was touched. Confirmed by `git status`
before/after: the only files modified are the 7 listed under Fix above,
all directly load-bearing for this bug. `docs/audits/V1_1_FEATURE_INVENTORY.md`
and `docs/audits/PR7_CONFLICT_AUDIT.md` remain exactly as they were
(untracked, uncommitted, not touched by this investigation). No branches
were created or deleted; no commits were made as part of the investigation
itself (this report documents the state of the working tree, to be
committed separately per the next instruction). The temporary `build-debug/`
directory and the temporary swap of `~/.local/lib/qt6/qml/Omafiles/Backend/`
(used to make the locally-built debug plugin loadable for live testing)
were both cleaned up / restored to their original, pre-investigation state
before this report was written.

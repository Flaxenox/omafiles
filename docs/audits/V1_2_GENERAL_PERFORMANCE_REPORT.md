# V1.2 General Performance Audit — OmaFiles

**Repo**: `/home/josema/Projects/omafiles`, branch `v1.2-dev`
**Date**: 2026-08-19
**Scope**: follow-up to the startup-performance audit (`V1_2_STARTUP_PERFORMANCE_REPORT.md`) — general runtime performance (navigation, listing, search, file ops, v1.1/v1.2 feature runtime cost), per josema's "sí, rendimiento en general". Extended afterward with a general code-quality review ("algo que veas mal, innecesario, optimizable") — the "Code-quality fixes" section below covers that follow-up work. No commits/pushes/tags/merges — everything below is uncommitted on `v1.2-dev`.

---

## Summary

**Two real fixes this pass:**

1. `state/FolderCountState.qml` reassigned its whole `counts` cache on every single async folder-count result, invalidating every visible row's subtitle binding each time instead of just the row that changed. Fixed by coalescing a burst of results into one reassignment. **41 reassignments → 2** (and, in the isolated unit test, **30 set() calls → 1 reassignment**), no behavior change, no added latency.

2. While building a realistic regression test for fix #1 (real navigation into a directory with many subfolders), a **separate, pre-existing, 100%-reproducible SEGFAULT** was uncovered. Initial investigation (documented in full below) misread it as a vanishing "heisenbug" race condition; a deeper pass with AddressSanitizer + `QV4_FORCE_INTERPRETER=1` + targeted tracing found the **actual root cause**: `panels/BackgroundPanel.qml`'s active-slot delegate fed its rows a *stale* path (`modelData.path`, only updated by `TabOps.saveActiveTab()` at specific points) while the panel's own listing already used the *live* `NavState.currentPath` — the two could disagree for a real window after every navigation, letting a fresh entry name combine with a stale base path into a nonexistent, garbage combined path. Something in Qt 6.11.1's QML engine crashes (null-pointer write, `QV4::Object::insertMember`) when that garbage path gets inserted as a brand-new key into an internal cache. **Fixed**: one property now reuses the panel's own already-correct `effectivePath` instead of the stale one, keeping the two permanently in lockstep. Verified: **0 crashes across every run since the fix** (previously 100% reproducible), full trace evidence below.

Everything else surveyed (see the prioritized candidate list from the initial scan) was either already fine (C++ `DirectoryModel` scan/sort, `SortState.sortEntries`, `Utils.entriesEqual`, image/PDF thumbnails already parallelized) or lower-priority/edge-case (serial video thumbnails, unbounded bulk-rename regex) — see Deferred below.

**Follow-up code-quality review** (separate ask, same session) found and fixed two more real issues — see "Code-quality fixes" below: `scripts/runtime/list-mounts.sh` (3 subprocess forks per mount refresh) retired to a native `LocalMounts` D-Bus class, and `panels/BackgroundPanel.qml` firing a redundant duplicate directory scan on every tab switch.

---

## Fix implemented: `state/FolderCountState.qml`

**Old behavior**: `set(path, n)` did `counts = Object.assign({}, counts); counts[path] = n` synchronously on every single `FolderCounter.counted()` result. QML tracks `counts` as one property (not per-key), so every reassignment invalidated **every** visible row's `FileMeta.metaFor()` subtitle binding (`panels/FileListRow.qml:157`), not just the row whose count actually arrived. Entering a folder with N visible subfolders fires N independent async `FolderCounter.request()` calls (one per row, `panels/FileListRow.qml:124-129`), each completing on its own thread-pool schedule — so N reassignments × (however many visible folder rows) re-evaluations.

**New behavior**: `set()` buffers the result into `_pendingResults` and starts a 16ms one-shot `_flushTimer` if one isn't already running; the timer's `onTriggered` merges everything buffered since the last flush into `counts` in one reassignment. `needsRequest()` was updated to also check `_pendingResults` so a result that's buffered-but-not-yet-flushed doesn't look like "never requested" and trigger a duplicate `FolderCounter.request()`.

**Measured**: a temporary integration-style benchmark (real navigation into a synthetic 60-subfolder directory, since replaced — see the crash section) measured **41 reassignments → 2** for the same 23 resolved results, 3/3 consistent runs, no change in settle time (~210-225ms either way — the 16ms coalescing window is far below the noise floor of the async work itself). The permanent regression test (isolated, no real navigation — see below) measures **30 `set()` calls → 1 reassignment**, deterministically, every run.

**Risk**: Low. Same eventual `counts` content, same LRU-256 eviction, same reactivity contract (subtitles still update, just coalesced within ~16ms — imperceptible). `needsRequest()`'s extra check prevents the one behavior change that mattered (duplicate requests during the buffering window).

**Regression test**: `src/selfcheck/checks/CheckPerformance.qml` — *"FolderCountState.set() coalesces a burst into one reassignment (V1.2 general-perf regression)"*. Calls `FolderCountState.set()` directly with 30 synthetic paths (no real `ListView`, no real `FolderCounter`, no real filesystem navigation — see why below), snapshots and restores the real `counts` cache around itself so it doesn't disturb any other test's cached data. Asserts: nothing flushes synchronously (`reassigns === 0` immediately after the burst), all 30 values are eventually present and correct, and the flush count stays `<= 3` (proving coalescing, not a 1:1 regression).

---

## Discovered and FIXED: a pre-existing, unrelated SEGFAULT

### What happened

The first version of the regression test above drove the fix through a **realistic** path instead of an isolated one: create 60 real subfolders, navigate `sc._content`'s real composition root (real `NavigationController`, real `ListView`, real `FileListRow` delegates) into that directory, and let the real `Backend.FolderCounter` async requests resolve for however many rows the viewport actually made visible (~17-23 of 60, confirmed — `ListView` virtualizes, matching the "bounded by viewport" expectation from the initial survey).

Running the full `--selfcheck` suite with that test in place **segfaulted 100% of the time** (3/3, then reproduced again after changes, consistently) — always **later** in the run, during an unrelated subsequent test, never inside the offending test itself (which always printed its own `[PASS]` first).

### Root-cause work done

**Round 1 (plain build):**
- **`gdb --batch -ex run -ex "thread apply all bt" -ex quit --args ./build/omafiles-standalone --selfcheck`** (launching as a direct child of gdb sidesteps this system's `ptrace_scope=1`, which blocks attaching to an already-running process). Crash: **Thread 1 (main thread)**, inside `QV4::Object::insertMember` → `QV4::Object::internalPut` → `QV4::Runtime::StoreElement::call` — the QML JS engine crashing during a plain property/array store, not inside any of this app's own C++ code. All background threads (thread-pool workers, `QDBusConnection`, `WaylandEventThr`, `QQmlThread`) were idle/waiting at the time, arguing against a simple "two threads touch the same memory at once" race.
- **Isolation 1**: disabled just the new test (kept the fix) → **147/147 clean, 3/3**. The *test's* real-navigation pattern triggers it, not the fix.
- **Isolation 2** (decisive): reverted `FolderCountState.qml` to its pre-fix code, kept the test → **crashed 3/3, identical symptom**. Conclusively pre-existing, unrelated to the fix.
- **Isolation 3**: added navigate-away cleanup at the end of the test → crash persisted, just shifted to a different later test.
- A `gdb`-with-`debuginfod` run of the *unmodified* binary completed with **zero crashes** — misleadingly suggesting a vanishing heisenbug. This turned out to be specific to that one binary/run, not a real property of the bug (see below).

**Round 2 (sanitizer builds — a second `cmake -B build-tsan`/`build-asan` tree, `-fsanitize=thread`/`-fsanitize=address,undefined -g -O1`, CMakeLists.txt itself untouched):**
- **ThreadSanitizer**: reproduced a SEGV, but the report was dominated by races inside `libQt6Core`/`libQt6DBus`/`libdbus-1` — none of which were TSan-instrumented (only this app's own code was built with the flag), so those are noise, not signal. Concluded TSan isn't the right tool here without a fully TSan-instrumented Qt (a much bigger undertaking, not attempted).
- **AddressSanitizer**: reproduced the **exact same crash signature** as the original `gdb` finding (`QV4::Object::insertMember`, writing to a near-null address — `0x38`, `0x58`, `0x1048` across different runs, i.e., a genuine null/near-null pointer write, not heap corruption with garbage values) — **5 times across 5 separate runs**, including with as few as **3 synthetic subfolders** (not just 60), ruling out "concurrency volume" as a requirement.
- **`QV4_FORCE_INTERPRETER=1`** (a real Qt env var that disables the QML JIT) unlocked a **full, deep, mostly-symbolized backtrace** through `gdb`+`debuginfod` on the ASan binary (`ASAN_OPTIONS=handle_segv=0` so `gdb` catches the raw signal instead of ASan's own handler) — the JIT had been hiding most of the call chain behind opaque trampoline frames. This is the key artifact: a **nested nested cascade** —
  `FileOperations::finished` (queued, cross-thread) → an app `onFinished:` handler sets a property → that property's `onChanged:` handler (`QQmlVMEMetaObject::metaCall`) sets *another* property → **that** one's `onChanged:` handler finally does a `something[key] = value` (`QV4::Runtime::StoreElement`) → crash inside `insertMember`.
- Cross-referencing the app's own code against that shape found an exact match: `panels/FileListRow.qml:141-144` —
  ```qml
  Connections {
    target: NavState
    function onRefreshTickChanged() { rowContent._requestCount(true) }
  }
  ```
  `NavState.refreshTick` is a **global** counter bumped by `logic/ActionEngine.qml:229` and `:934` on **any** file operation completing, anywhere in the app — every live `FileListRow` delegate, in every panel, reacts to it, and `_requestCount()` calls `FolderCountState.markPending(path)` → `_pending[path] = true`, a `StoreElement` write matching the crash site exactly.
- Tested the obvious mitigation this suggested — navigate away from the many-subfolder directory (forcing real delegate teardown) before finishing the test, so no stale rows are left reacting to later, unrelated operations — **crash persisted, 3/3**, just shifted to an even earlier later-test. So "leftover live delegates from this one test" is not the full story either; something about the FolderCounter/refreshTick/StoreElement interaction is more fundamental than just test hygiene.

**Round 3 (the actual root cause — direct tracing, not just backtraces):**

The isolation-3 mitigation (navigate away, destroy the delegates) not fixing it was the key clue that this wasn't about MY test's leftover rows specifically — something more structural was wrong. Rather than theorize further, added temporary `SelfCheckOut.line()` traces (deterministic, unaffected by the JIT — see the startup report for why this is the right tool in this release build) directly inside `FolderCountState.markPending()`/`set()`/`_flushTimer` and `FileListRow.qml`'s `_requestCount()`/`onRefreshTickChanged`, then re-ran the ASan repro and read the stdout trace right up to the crash line (each trace line does a real `fflush()`, so nothing is lost even though the crash itself is an immediate abort).

**The crash line was pinpointed exactly**: the last trace line before the SEGV was `markPending BEFORE path=/home/josema/f1` with **no matching `AFTER` line** — the crash is inside `_pending[path] = true` itself, for a path that doesn't correspond to anything on disk (confirmed: `/home/josema/f1` doesn't exist). Grepping for *every* call site of `markPending` (not just the one in `FileListRow.qml` that was already instrumented) turned up a second, unwatched one: **`panels/BackgroundListDelegate.qml:88`** — the delegate used by non-active-tab (and the always-alive, opacity:0 "preload") background panels.

Reading `BackgroundListDelegate.qml`'s `myPath: Utils.entryPath(panelPath, modelData)` next to `BackgroundPanel.qml`'s wiring found the actual bug:

```qml
// panels/BackgroundPanel.qml (before the fix)
delegate: BackgroundListDelegate {
  panelPath: bgPanel.modelData.path || ""   // the TAB's last SAVED path
  ...
}

// meanwhile, the SAME panel's own listing target:
readonly property string effectivePath: index === TabsState.activeTabIndex
  ? NavState.currentPath : (modelData.path || "")   // LIVE for the active slot
onEffectivePathChanged: bgPanel.refreshMe()          // triggers the async re-scan
```

For the **active-slot** panel (the always-alive, opacity:0 panel that preloads whatever the active tab is currently showing, so switching tabs doesn't jump — see its own doc comment), `effectivePath` correctly tracks the *live* `NavState.currentPath`. But `panelPath` — fed straight to every row delegate — used `modelData.path`, the tab's **last explicitly saved** path. Saving only happens at specific points (`TabOps.saveActiveTab()`, called from `switchToTab`/`closeTab`/`newTab`/session-save — grepped all call sites, confirmed: never on a plain `navigateTo()`). So after *any* navigation and before the next save point, `panelPath` (stale) and the panel's actual listed content (live, already showing the new folder's real entries) disagree — a real entry name from the *new* folder gets combined with the *old* saved base path into `Utils.entryPath(oldPath, newEntry)`, a syntactically valid but nonexistent combined path. `FolderCounter.request()` on that path harmlessly returns `n=-1` — but inserting that never-seen-before string as a **brand new key** into `_pending` (`QV4::Object::insertMember`, handling the internal hash table growth for a genuinely new property) is what crashes, apparently a real Qt 6.11.1 QML-engine bug for this specific access pattern (the exact mechanism inside `insertMember` remains unconfirmed — see "Still open" below — but the *trigger condition* is now fully understood and eliminated).

### The fix

`panels/BackgroundPanel.qml` — `panelPath: bgPanel.modelData.path || ""` → `panelPath: bgPanel.effectivePath`. `effectivePath` was already the correct value for *both* cases (identical to `modelData.path` for genuine background tabs; the live `NavState.currentPath` for the active slot) — using it for `panelPath` too keeps the two permanently in lockstep, closing the mismatch window structurally rather than papering over one symptom of it (e.g. clearing stale entries on every navigation would have worked too, but treats the symptom; using the value that was already correct removes the inconsistency itself).

### Verification

- **15-run ASan batch** (background job, `build-asan/` — `-fsanitize=address,undefined -g -O1`) with the fix applied: **0 crashes across all 15** (`DEADLYSIGNAL` appears in none of the 15 stdout logs) — versus 100% (7+/7+) before the fix, across every prior reproduction attempt this session.
- **5 consecutive clean runs** of the normal Release `build/omafiles-standalone --selfcheck`: **148/148 passing every time**, 0 crashes, 0 flakes.
- All temporary diagnostic traces (`SelfCheckOut.line()` calls added to `FolderCountState.qml`/`FileListRow.qml` for this investigation) and the temporary crash-repro selfcheck test were fully removed afterward — confirmed via `git diff` that `FileListRow.qml` is byte-identical to its pre-investigation state (the fix touches only `BackgroundPanel.qml`).
- A dedicated regression test for this specific fix was **not** added: the crash was inherently timing-sensitive to reproduce reliably even *with* the bug present (needed a specific point deep in a long, multi-test run), so a fast, deterministic unit test asserting "no crash" isn't practical, and a test asserting `panelPath === effectivePath` structurally would need new alias plumbing into `BackgroundPanel`/`BackgroundListDelegate` purely for testability with no other benefit. The fix is small, self-evidently correct (both branches of `effectivePath` are what `panelPath` should have meant all along), and covered by the general "the whole suite must not crash" bar every run already enforces.

### Still open (residual, not blocking)

- The literal Qt-engine mechanism inside `QV4::Object::insertMember` that turns "insert a novel string key into a JS object" into a null-pointer write is still not understood at the Qt source level — only the *application-level trigger* (the stale-path mismatch) is confirmed and closed. If this ever resurfaces from a different trigger, the same tracing approach (ASan + `QV4_FORCE_INTERPRETER=1` + `SelfCheckOut.line()` bisection) is the proven playbook.
- Qt version: `qt6-base`/`qt6-declarative` **6.11.1** (CachyOS/Arch current) — worth a quick check against Qt's own bug tracker for known `insertMember` crashes, in case this is a known, already-fixed-upstream issue.
- Not confirmed whether a normal user could hit the *original* symptom in a plain, non-selfcheck session — but since the trigger (navigate, then browse before the tab's path gets saved) is a completely ordinary usage pattern, not a contrived edge case, this was worth fixing regardless of exact real-world hit rate.

---

## Code-quality fixes (follow-up review: "algo que veas mal, innecesario, optimizable")

A separate review pass (own reading + a background sweep of files not yet covered this session) found four things worth flagging. Two were implemented now, at josema's request ("haz el 1 y el 3"); the other two are queued for a later pass.

### 1. `scripts/runtime/list-mounts.sh` retired — native `LocalMounts` (D-Bus)

**Old behavior**: `MountActions.refreshMounts()` launched `list-mounts.sh` (a `ProcessRunner`/`QProcess` subprocess) on every app `open()`, every `UDisksWatcher.devicesChanged()` event (any USB plug/unplug, mount, label change), and after every mount/eject action. The script itself forked `findmnt` **twice** plus `lsblk` **once** (3 subprocesses, each with per-line subshell calls for `basename`/`grep`) to build a TSV that `Utils.parseMounts()` then parsed by hand.

This one was initially misjudged (by me and by a background review agent) as simply an unmigrated leftover — `NetworkMounts.cpp` (the network-mount equivalent) and `UDisksWatcher.cpp` (the change-notification watcher for the *same* subsystem) were both already native, so the shell script looked like the one piece nobody got around to porting. It wasn't: `docs/architecture/ARCHITECTURE.md`'s `scripts/runtime/` contract table had a specific, considered justification — "enumerates **unmounted** removable devices too; `QStorageInfo` only sees already-mounted filesystems, the rest needs `libblkid`/`libudev`". That's a real constraint *for `QStorageInfo`* specifically. Checked with josema before touching it (`AskUserQuestion`) rather than silently overriding a documented decision — went ahead because UDisks2 itself (a D-Bus service `UDisksWatcher` was already talking to for change notifications) exposes exactly that same unmounted-device data via `org.freedesktop.UDisks2.Block`/`.Filesystem`/`.Drive`, without needing `libblkid`/`libudev` at all — a different path to the same goal the architecture doc's reasoning didn't rule out.

**New behavior**: `backend/LocalMounts.{h,cpp}` (new, mirrors `NetworkMounts`'s existing `QML_SINGLETON` pattern exactly) — `LocalMounts::list()` calls UDisks2's `Manager.GetBlockDevices()`, then per block device reads `Block`/`Filesystem`/`Drive` properties over the system D-Bus connection, and reproduces the **exact same filtering** the script had (not new UDisks2-specific filtering like `HintSystem`/`HintIgnore`, which could change real-world behavior the script never had): mounted at `/`, `/mnt/*` (excluding bare `/mnt`), or `/run/media/$USER/*` → shown as mounted; a removable drive with a real filesystem and no mount point → shown as available-to-mount. `MountActions.refreshMounts()` now assigns `Backend.LocalMounts.list()` directly to `MountsState.mounts`, synchronous, matching `refreshNetworkMounts()`'s already-established pattern — no subprocess, no TSV, no `Utils.parseMounts()`.

**Verified against the real system**: `findmnt`/`lsblk` run by hand showed exactly `/` (btrfs, `/dev/nvme0n1p2`) and `/mnt/Almacen` (exfat, `/dev/sda3`) mounted, nothing removable-unmounted present. `LocalMounts.list()` returned **exactly those two entries**, byte-for-byte matching label/path/device/fstype/removable/mounted — confirmed via a temporary debug dump, then via a real GUI launch (screenshot: sidebar's Devices section shows "System (/)" and "Almacen", nothing else, nothing missing).

**Cleanup**: `scripts/runtime/list-mounts.sh` deleted (no longer referenced anywhere); `Utils.parseMounts()`/`Utils.decodeDeviceLabel()` deleted from `shared/Utils.js` (dead code, no other callers — confirmed via grep); `UDisksWatcher.h`'s comment (which named the script as "the single source of truth... kept on purpose") and `ARCHITECTURE.md`/`BACKEND_DESIGN.md`'s contract tables updated to reflect the retirement, matching how `MimeResolver`/`NetworkMounts`'s earlier retirements were documented.

**New regression test**: `src/selfcheck/checks/CheckDevices.qml` — *"Native local mounts listing (LocalMounts, V1.2) includes the root filesystem"*. Asserts the root filesystem (present on every real Linux machine, unlike a specific removable drive which is machine-dependent) is found, labeled `"System (/)"` exactly like the retired script did, with a real `fstype`.

**Risk**: Low-medium. New D-Bus marshaling code (manual `QDBusArgument` iteration for the `aay` `MountPoints` property) is the one genuinely new-and-nontrivial piece; verified correct against live system state rather than only trusting the code by inspection.

**Follow-up, live USB test (same session, josema plugged in a real Ventoy USB stick)**: confirmed the previously-unverified "unmounted removable device" path (`Drive.Removable` + empty `MountPoints`) works correctly — the USB's small unmounted EFI partition (label `VTOYEFI`) appeared correctly as "available to mount". This same test surfaced a **real ordering bug**: `GetBlockDevices()`'s enumeration order is UDisks2's own internal object registration order, unrelated to mount time — the USB's Block objects happened to register before the system disk's, so the sidebar showed the removable drive **above** "System (/)"/"Almacen" instead of below, breaking the sensible grouping the old `findmnt`-then-`lsblk` script naturally produced (mounted-at-boot system drives first, removable media after, not-yet-mounted last).

**Fixed**: `LocalMounts::list()` now explicitly `std::stable_sort`s its output into 4 tiers — `/` first, then other fixed drives, then removable-and-mounted, then removable-and-not-yet-mounted — restoring the same grouping deterministically instead of leaving it to incidental D-Bus object order. Verified live: order is now `System (/)`, `Almacen`, `Ventoy`, `VTOYEFI` — confirmed both via a debug dump matched against the exact array and visually in a real GUI screenshot.

**New regression test**: `src/selfcheck/checks/CheckDevices.qml` — *"LocalMounts.list() orders fixed drives before removable ones (V1.2 ordering regression)"*. Asserts no removable entry ever precedes a fixed one — vacuously (but still meaningfully) true on a machine/CI with no removable drive attached, and a real check when one is.

With this, `LocalMounts` is now live-verified end to end (both halves of the listing logic, plus ordering), not just code-review-confidence.

### 3. `panels/BackgroundPanel.qml` — duplicate refresh on tab switch

**Old behavior**: `effectivePath` and `isBackground` are both derived from the identical condition (`index === TabsState.activeTabIndex`), so switching tabs changed both in the same tick — `onEffectivePathChanged` and `onIsBackgroundChanged` each independently called `refreshMe()`, firing **two** real `dirLister.list()` scans for one tab switch. `_lastRefreshedPath` was already being *written* on every `refreshMe()` call, apparently intended as a dedup guard, but nothing ever *read* it back — dead state.

**New behavior**: `refreshMe(force)` now skips the re-scan when `_lastRefreshedPath === effectivePath` already, unless `force` is passed. The `NavState.refreshTick` handler (which intentionally re-scans the *same* path because its on-disk *content* changed, not its target path) now calls `refreshMe(true)` to bypass the guard — the one caller where "same path as last time" is the expected, correct case. The other three callers (`onEffectivePathChanged`, `onIsBackgroundChanged`, `Component.onCompleted`) are unchanged and now naturally dedup: whichever of the two tab-switch handlers runs second finds `_lastRefreshedPath` already updated by the first, and skips.

**Verified**: `src/selfcheck/checks/CheckPanels.qml`'s existing "Background panel refreshes on content change (non-active tab)" test — which depends on `refreshTick` still forcing a real re-scan — still passes. 5/5 consecutive full-suite runs, 149/149, before and after.

**Risk**: Low. Purely a dedup guard around an already-idempotent operation (re-listing the same path twice was wasteful, never incorrect); the one caller that needs to bypass it does, explicitly.

### Queued for later (not done yet)

- **#2 — `logic/ActionEngine.qml` is a 1585-line monolith**, the one glaring exception to this codebase's otherwise-consistent "small, single-purpose file" discipline (every other `logic/*.qml` file is under ~200 lines and numbers itself as "Nth component extracted from core"). Covers at least seven cleanly-separable concerns (undo/redo, transfer queue, native copy/move/trash batch lifecycle, clipboard/paste, rename/new-file/new-folder, chmod, compress/extract/drag-drop) with clear boundaries already visible from its own function grouping. Largest remaining maintainability target; a real refactor, not a quick fix — queued for its own dedicated pass.
- **#4 — minor duplication in `ActionEngine.qml:716-732`**: `copyPathAbsoluteFor`/`copyPathRelativeFor`/`copyPathUriFor` each recompute the identical `entries.map(e => Utils.entryPath(NavState.currentPath, e))` before calling a different `TerminalResolver` method. Three lines, easy one-line dedup — bundle it with #2 if that's ever tackled, not worth its own pass.

---

## Survey: other candidates (from the initial scan, not pursued further)

**Already fine, ruled out** (confirmed via prior `PHASE38_PERFORMANCE_REGRESSION_REPORT.md` history + current code reading, not re-benchmarked from scratch): C++ `DirectoryModel` scan/sort/signature (O(n) scan threaded off the UI thread, O(1) signature compare, unchanged code path since v0.9.0); `SortState.sortEntries` (Schwartzian transform, already avoids repeated `toLowerCase()`/comparator work per its own comments); `Utils.entriesEqual` (intentional O(n), called once per event, not in a loop); image/PDF thumbnails (already parallel via `QThreadPool` in `ThumbnailProvider.cpp`); `FileOperations` copy/search throughput (multi-GB/s copy, 100k-file search in the ~76ms range per prior benchmarking).

**Worth measuring, not yet done** (lower priority than the fix above, no evidence of a real-world complaint driving them):

- `logic/VideoThumbnails.qml` — video thumbnails are generated strictly serially (one `ffmpegthumbnailer` subprocess at a time via a `thumbBusy` gate), unlike image/PDF thumbnails which are already parallelized in C++. A folder with 30+ videos would show thumbnails trickling in one-by-one. Plausible real win (bounded concurrency, 2-4 in flight, same subprocess script), low risk, not attempted this pass.
- Bulk rename regex (`shared/Utils.js` `bulkRenameNames`) — a user-typed catastrophic-backtracking regex pattern runs synchronously on every preview keystroke with no complexity guard. Edge case (not a default-path regression), cheap to note, not worth a dedicated pass on its own.

**Not investigated at all** (would need their own scoped pass): `SearchWorker.cpp`'s content-search snippet extraction under very deep/wide trees; `NetworkResolver`/`GvfsWatcher` D-Bus round-trip latency on mount enumeration; `PathCompleter.cpp` autocomplete cost on deeply nested paths.

---

## Verification

- **Build**: `FolderCountState.qml`/`BackgroundPanel.qml`'s crash fix and the coalescing regression test are QML/JS-only — no rebuild needed for those. `LocalMounts.{h,cpp}` is new C++ (`CMakeLists.txt` updated, `Qt6::DBus` already linked — no new dependency); built clean, zero warnings, via the normal `build/` tree. A separate, temporary `build-asan/` tree (`-fsanitize=address,undefined -g -O1`, not committed, deleted afterward) was used specifically to reproduce and verify the crash fix; `CMakeLists.txt`'s normal configuration was never touched by that.
- **Selfchecks (normal build)**: 150/150 (147 pre-existing + 3 new — the coalescing test, the `LocalMounts` root-filesystem test, and the ordering test), **5+/5+ consecutive clean runs**, zero crashes, zero flakes.
- **Selfchecks (ASan build, the real test for the crash fix)**: **15/15 runs, zero crashes** (`DEADLYSIGNAL` in none of the 15 logs) — versus 100% reproduction before the fix across every prior attempt this session (gdb, TSan, ASan, with and without the JIT).
- **Regression test (coalescing)**: deterministic — every run reports `reassignments=1 (of 30 set() calls)`, not a range.
- **Crash fix**: isolated to `panels/BackgroundPanel.qml`'s single `panelPath:` line. Confirmed `panels/FileListRow.qml` (touched only for temporary tracing during the investigation) is byte-identical to its pre-investigation state via `git diff`. The bug itself predates this entire session's work (reproduces on the original, untouched `FolderCountState.qml` too).
- **`LocalMounts` fix**: verified against real system state (`findmnt`/`lsblk` run by hand, compared byte-for-byte against `LocalMounts.list()`'s output via a temporary debug dump) and via two real GUI launches (before and after the ordering fix, screenshots both times). Both halves of the listing logic (mounted and unmounted-removable) and the ordering are now live-verified with a real USB stick, not just code-reviewed.
- **BackgroundPanel dedup fix**: the existing `refreshTick`-dependent regression test still passes, confirming the `force=true` bypass works; no new dedicated test added (the fix is a pure efficiency dedup around an already-idempotent operation).
- **Installed application / packaging**: not touched, per standing constraints.

---

## Changed files

| File | Change |
|---|---|
| `state/FolderCountState.qml` | Coalesce `counts` reassignment via a 16ms one-shot `_flushTimer` instead of reassigning synchronously per result. |
| `panels/BackgroundPanel.qml` | Fix the SEGFAULT root cause (`panelPath:` now uses the already-correct `effectivePath`) **and** dedup the tab-switch double-refresh (`refreshMe(force)`). |
| `backend/LocalMounts.h`/`.cpp` | New: native UDisks2 D-Bus mount enumeration, replaces `list-mounts.sh`. Explicit 4-tier `mountRank()` sort (`/`, other fixed, removable-mounted, removable-unmounted) added after a live USB test showed UDisks2's own object-registration order could put a removable drive above the system disk. |
| `logic/MountActions.qml` | `refreshMounts()` calls `Backend.LocalMounts.list()` directly (synchronous), dead `mountsProc` `ProcessRunner` removed. |
| `scripts/runtime/list-mounts.sh` | Deleted (retired, no longer referenced). |
| `shared/Utils.js` | `parseMounts()`/`decodeDeviceLabel()` deleted (dead code, no callers left). |
| `backend/UDisksWatcher.h` | Comment updated — no longer names the deleted script as "the source of truth". |
| `docs/architecture/ARCHITECTURE.md`, `BACKEND_DESIGN.md` | `scripts/runtime/` contract table and retirement list updated to reflect `list-mounts.sh`'s retirement. |
| `CMakeLists.txt` | `backend/LocalMounts.h`/`.cpp` added to the backend target's sources. |
| `src/selfcheck/checks/CheckPerformance.qml` | New isolated regression test for the `FolderCountState` coalescing behavior. |
| `src/selfcheck/checks/CheckDevices.qml` | New regression tests: `LocalMounts.list()` finds the real root filesystem, and never orders a removable entry before a fixed one. |

No other files touched in this pass (the startup-audit files from the previous report are separate, already-described changes on the same branch).

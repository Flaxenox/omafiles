# Test & Build Audit — omafiles

**Repo**: `/home/josema/Projects/omafiles`, branch `v1.0-dev`, HEAD `bf38073a45c8ec7539acf96bf351315e6383230e` (2026-08-15 15:38:29 +0200)
**Date of audit**: 2026-08-16
**Scope**: selfcheck test suite, clean build, PKGBUILD/packaging, bench harness, documentation-vs-reality. Read-only forensic analysis — no source files were modified.

**Naming note**: the task material references "Phase 43.2" terminal/clipboard/keyboard tests. The actual source labels these `(Phase 43 Regression)` / `(BUG-06)` in `src/selfcheck/checks/CheckIntegration.qml:149-202` — there is no "43.2" anywhere in the codebase (`grep -rn "43\.2" .` = zero hits), and unlike BUG-01/02/03/05 in the same file, no `docs/historical/*.md` report exists for "Phase 43" at all. Treated below as "the BUG-06 tests," per the actual source labels. Similarly, "Gemini" does not appear as a git author anywhere in this repo's history (only `Percius04`, `Sebasgl23`, `Sebastián Guardo`); references to a distinct AI-agent identity are not supported by the evidence and are avoided below.

---

## What was actually executed vs. static analysis only

**Actually executed (real commands, real output, captured to log files):**
- Full clean out-of-tree CMake configure + Ninja build (`cmake -S . -B <scratch> -DCMAKE_BUILD_TYPE=Release` + `cmake --build .`), outside the repo.
- `./omafiles-standalone --selfcheck` — the full 85-test suite, run against the freshly built binary reading live QML source from the working tree.
- `git status --short`, `git remote -v`, `git describe --tags`, `git branch --contains`, `git merge-base --is-ancestor` — to verify PKGBUILD version/URL claims.
- `curl` against both the PKGBUILD's GitHub URL and the actual `git remote` URL, to confirm the 404.
- `cmake . -DCMAKE_INSTALL_PREFIX=/usr` re-configure + cache inspection, to empirically reproduce the install-path bug rather than infer it from reading CMakeLists.txt alone.
- `pacman -Qo` against installed Qt6 cmake config files, to verify which system packages actually provide `Qt6::Pdf`/`Qt6::DBus`/`Qt6::Network`/`Qt6::QuickControls2`.
- `bench/perfbench.cpp` compiled and run twice against current `backend/DirectoryModel.cpp`; `measure-ui-guard.qml` and `measure-search.qml` run via the documented invocations; `bench/bench-gate.py --check-gate` run against `~/.local/bin/omafiles`.
- `classify_delta()` from `bench-gate.py` invoked directly (live, current script) against baseline/current value pairs to check its logic.
- `findmnt` on `/tmp` and `~/.cache`, to verify which benchmarks run on tmpfs (RAM) vs. real NVMe.

**Static analysis only (read source, traced call paths, did not execute):**
- All 85 individual selfcheck test bodies were read in full; correctness of their assertions against the *intent* of each test was reasoned about, not independently re-verified by e.g. deliberately breaking the code and re-running.
- `TerminalResolver.cpp`, `Env.cpp`, `KeyboardShortcuts.qml`, `ActionEngine.qml` were read and traced by hand to confirm selfcheck tests call the real production functions (not re-implementations), but no fault-injection was performed beyond what the tests themselves already do.
- All documentation files (README, CHANGELOG, ARCHITECTURE.md, BACKEND_DESIGN.md, DEPENDENCY_GRAPH.md, PROJECT_STATE.md, AGENT_BOOTSTRAP.md, PKGBUILD) were read and cross-checked against `grep`/`find`/`wc -l` results on current source — no execution involved for this part beyond the shared build/selfcheck/bench runs above.
- Claims about `docs/historical/*.md` phase reports (PHASE34, PHASE37, PHASE38, PHASE35, PR2) were treated categorically as unverified self-reports and checked only where a specific number/claim could be cross-referenced against current code or against the bench/selfcheck runs above; the reports were not otherwise re-litigated line by line.

---

## 1. Test Coverage

### 1.1 Suite identity and scale

`src/selfcheck/SelfCheckRegistry.qml` loads 12 check files (`CheckActions`, `CheckDevices`, `CheckFilesystemListing`, `CheckFilesystemOps`, `CheckFilesystemTrash`, `CheckInfrastructure`, `CheckIntegration`, `CheckPanels`, `CheckPerformance`, `CheckPersistence`, `CheckPreview`, `CheckSearch`) in a fixed order and calls `mod.register(sc)` on each. A `Component.status !== Ready` load failure calls `Qt.exit(2)` — fail-fast, no partial run on a QML syntax error.

`SelfCheckRunner.qml` is a hand-rolled, genuinely sequential async runner (no QtTest) — one test in flight at a time, an 8000ms per-test timeout auto-fails hangs. `main.cpp`'s `runSelfCheck` forces `QT_QPA_PLATFORM=offscreen`, sets `OMAFILES_SELFCHECK=1`, and builds deterministic fixtures in a `QTemporaryDir` under `~/.cache` chosen specifically to land on the same filesystem as the real XDG trash — a deliberate, careful design choice for the trash/restore round-trip tests.

**Verdict on the harness itself: legitimate, not theater.** It exercises the real `Omafiles.Backend` QML plugin and real QML component trees via `Qt.createComponent`/`createObject`, not mocked-out stubs of the app.

### 1.2 The 85/85 claim — VERIFIED, not padded

```
CheckActions.qml: 9        CheckFilesystemTrash.qml: 15
CheckDevices.qml: 2        CheckInfrastructure.qml: 10
CheckFilesystemListing.qml: 2   CheckIntegration.qml: 10
CheckFilesystemOps.qml: 20      CheckPanels.qml: 1
CheckPerformance.qml: 5         CheckPersistence.qml: 1
CheckPreview.qml: 8             CheckSearch.qml: 2
TOTAL = 85
```
Verified twice: once by `grep -c "sc\.add(" *.qml` across the 12 files summing to exactly 85, once by actually running the binary:
```
$ ./omafiles-standalone --selfcheck
── selfcheck: 85 passed, 0 failed, 85 total ──
```
This matches README.md's "85/85" claim exactly and is currently, reproducibly true — in contrast to the stale "77/77" figure still checked in at `docs/architecture/DEPENDENCY_GRAPH.md:99` (a leftover from an earlier "Phase 14.D" era that was never regenerated). Every one of the 85 test bodies was read; none is a no-op or tautology — each performs a real assertion against backend state, filesystem state, or signal payloads.

### 1.3 What the suite genuinely proves

The **majority** (65 of 85 tests, across `CheckFilesystemOps`, `CheckFilesystemTrash`, `CheckPerformance`, `CheckPreview`, `CheckSearch`, `CheckPersistence`) test **observable backend/filesystem behavior**: files actually moved/renamed/trashed/restored on disk, byte-accurate progress signals, actual thumbnail files produced, actual search results returned — all via the real C++ backend. Strong points:

- **CheckFilesystemOps.qml (20 tests)** — the strongest file. Covers mkdir/rename/copy/move/delete for files, recursive directories, symlinks (verified via the `.link` property, not just existence), permission preservation, cross-filesystem move (forcing the non-atomic-rename path), cooperative cancellation (verifies *no partial file/dir residue*, i.e. real cleanup, not just that cancellation was accepted), and read-only-directory delete failure.
- **CheckFilesystemTrash.qml (15 tests)** — directory/symlink/Unicode round-trips, same-basename collision handling from different source dirs, restore-over-existing-destination correctly erroring, restore recreating a deleted parent dir.
- **CheckPerformance.qml (5 tests)** — byte-accurate progress verification against a real 32 MiB fixture, plus three cancellation-leaves-no-residue tests (file, directory-tree, cross-fs move) — genuine regression guards against silent-corruption bugs a naive cancel implementation would have.
- **CheckPreview.qml (8 tests)** — real `ThumbnailProvider` PNG/PDF generation, a pinned SHA-1 cache-key regression test, a thorough 4-policy cache-pruning test (orphan/safety/age/size), and syntax-highlighting checked by exact hex color codes.

### 1.4 Blind spots — general

- **CheckPanels.qml is the only test touching rendered-adjacent QML UI** (1 of 85), instantiating a real `BackgroundPanel.qml` but with `hostPanelsRow` stubbed to zero-size so no delegates actually render.
- **The suite could pass in its entirety with the visible UI completely broken.** Nothing creates a real `ApplicationWindow`, renders `panels/ActiveFileList.qml`, `core/MainLayout.qml`, `dialogs/*`, or the command palette/context menu, or dispatches a real `QKeyEvent` through the compositor/window/focus-scope chain. Drag-and-drop, rubber-band selection, the context menu, properties panel UI, bulk-rename UI, chmod dialog UI, and command-palette fuzzy search have **zero** coverage — only their underlying engine calls are indirectly exercised via stubs.
- **CheckDevices.qml's `NetworkMounts.list()` test** (1 of its 2 tests) is, by its own code comment, a smoke test only — checks the return type is array-like, never checks correctness of an actual GVfs mount listing. The shallowest test in the suite by its own admission.
- **CheckInfrastructure.qml's "AppBindings loaded (no side effects under selfcheck)" test** only checks `sc._content !== null` — it does not actually verify that `AppBindings` skipped self-registration side effects (no check that `xdg-mime default` wasn't called, no check of any integrations-version state file). It infers correctness from the existence of a guard in the source rather than observing an absence of side effects. Shallow relative to its name.
- Many of the 85 tests are only independent in bookkeeping, not in actual dependency: `CheckInfrastructure`'s "Composition root creates" test builds a shared `sc._content` object tree reused by 15+ later tests across other files — a single early failure there cascades into many downstream failures, which the flat "85 total" framing obscures.

### 1.5 Deep dive — the BUG-06 / "Phase 43 Regression" tests (`CheckIntegration.qml:149-202`)

**Test 1 — Terminal resolver error path** (lines 150-165): mutates the real process environment via `qputenv` (`Env.set` → `backend/Env.cpp:14-16`), then calls the real, fully synchronous `TerminalResolver::launchTerminal()` (`backend/TerminalResolver.cpp:12-45`). This is **legitimate** — it exercises the real production code path end-to-end and would catch a regression like a removed `emit error(...)` or reordered env restore. Gap: only the *failure* path is tested; the happy path (`process.startDetached()` actually spawning a terminal) has **zero** coverage anywhere in the 85 tests.

**Test 2 — Relative path quoting ("clipboard quoting")** (lines 167-175): traced into `TerminalResolver::copyPathsRelative` → `quoteShell()` → `copyText()`. Critical finding: `copyText()` (`backend/TerminalResolver.cpp:47-53`) emits `copied(text)` then explicitly returns *before* calling `QClipboard::setText()` when `OMAFILES_SELFCHECK=1` — which `main.cpp` sets unconditionally for every selfcheck run, additionally under `QT_QPA_PLATFORM=offscreen`. So **the real clipboard write is permanently, structurally skipped** for the entire duration of every selfcheck run. This test validates the shell-quoting algorithm only, never that text reaches the actual Wayland/X11 clipboard — despite being framed as a "clipboard" test. This is a deliberate, structurally necessary tradeoff (offscreen platform likely has no working `QClipboard`), not an oversight, but it means the test's name overstates its coverage.

**Test 3 — Keyboard shortcut integration** (lines 177-202): confirmed `handlePress()` is the **exact same function** production code wires at `panels/ActiveFileList.qml:204` (`Keys.onPressed`) with real `hostControllers`. So it is not a parallel/fake router. However it is genuinely shallow in three ways:
1. Only 5 of ~30 documented shortcuts are exercised (F2, Delete, Ctrl+C, Ctrl+X, Ctrl+V) — vim navigation, Alt+←/→, Ctrl+Z/Y, Ctrl+T/W/Tab, Ctrl+A/Shift+A/I, Ctrl+H/L, Space, `/`, `s`/`S`, `?` are entirely untested by this "integration" test.
2. It calls `handlePress()` directly with a hand-built event object, **bypassing all real Qt key-event delivery** — a focus-scope bug, a removed `Keys.onPressed` handler, or a modal dialog eating the event first would be completely invisible to this test.
3. It never asserts `event.accepted === true` — cannot detect a regression where the right action fires but the event isn't marked handled (risking double-fire via bubbling in production).

**Net verdict**: Test 1 is a real, end-to-end regression guard. Test 2 is real for the quoting math but permanently and structurally blind to the actual clipboard write. Test 3 exercises the real routing function via the real call site but covers under a fifth of the documented shortcuts and skips the entire Qt event-delivery/focus chain — it could catch a bug *inside* the handler, not a bug that prevents the handler from ever being reached.

### 1.6 Cross-cutting structural finding: two parallel rename implementations, causing real test flakiness risk

Two tests deviate from the suite's otherwise-consistent signal-driven async pattern and use hand-rolled fixed-delay `Timer` polling instead:
- `CheckActions.qml:215-251` "Undo + redo rename (full cycle)" — three sequential 60ms timers (measured actual run time ≈177ms, i.e. always the full fixed duration regardless of when the operation actually completes).
- `CheckFilesystemTrash.qml:181-210` "Trash + restore from symlinked directory" — two sequential 40ms timers (≈90ms actual).

Root cause traced: conflict-resolution rename (`ConflictState.pendingRename` → `runPendingRename(false)`, `logic/ActionEngine.qml:480-497`) does **not** go through `Backend.FileOperations` at all — it builds a literal `mv -f/-n -- <old> <new>` shell string and runs it via a private, unexposed `actionProc` (`ActionEngine.qml:74-92, 279`), so the selfcheck harness has no signal to subscribe to and falls back to a timing guess. `ActionEngine.qml:120`'s own comment confirms: *"Actions still in shell (compress/extract/rename/create): actionProc."* This directly contradicts README.md's "no shell-out where a native call will do" (line 16) and "no longer required: ... `gio` (shell commands)" (line 239) claims, and coexists with a genuinely native `Backend.FileOperations.rename()` used by the plain (non-conflict) rename path and tested cleanly/signal-drivenly in `CheckFilesystemOps.qml:20-31`.

**Practical consequence**: under CPU load (busy CI runner, loaded dev machine), these two fixed-delay tests carry a real risk of reading stale filesystem state before the window elapses — either a false FAIL, or worse, a false PASS on stale-but-coincidentally-matching state.

### 1.7 Test coverage summary table

| Finding | Status |
|---|---|
| 85/85 claim | VERIFIED — by grep count and by live execution |
| Suite currently green | VERIFIED — ran it, full output captured |
| "Phase 43.2" terminology | Not supported by source — actual label is "Phase 43 Regression"/"BUG-06"; no `.2`, no `docs/historical` report exists for it |
| Terminal resolver error-path test | Legitimate, real synchronous production code, real env mutation |
| "Relative clipboard quoting" test | Real for the quoting math; permanently blind to the actual `QClipboard` write (`OMAFILES_SELFCHECK` guard) |
| Keyboard shortcut integration test | Real routing function via real call site, but 5/~30 shortcuts, no real Qt event delivery/focus chain, no `event.accepted` check |
| Rename-undo/redo & symlinked-dir-restore tests | Fixed-delay Timers, not signals — real flakiness risk, caused by a still-shell-out `mv` path contradicting README's "no shell-out" claim |
| Two parallel rename implementations | CONFIRMED — native `FileOperations.rename()` vs. shell `actionProc` (conflict-resolution rename + compress/extract/create) |
| UI/window/input-delivery coverage | Essentially absent — suite proves backend correctness thoroughly, proves almost nothing about rendered UI or real key/mouse delivery |

---

## 2. Build Verification

**This section reports a real, executed build — not a simulation.**

### 2.1 CMake structure

Single `CMakeLists.txt` at repo root (no sub-CMakeLists anywhere). `project(omafiles VERSION 0.9.0 LANGUAGES CXX)`. `find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Pdf DBus Network)` + `pkg_check_modules(GIO REQUIRED gio-2.0)`. Two targets: `omafiles-backend` (shared lib, `qt_add_qml_module`, all 61 `backend/` files listed 1:1, none omitted, none stray) and `omafiles-standalone` (executable, `main.cpp`, depends on the backend target).

### 2.2 Configure output (verbatim, complete)

```
-- The CXX compiler identification is GNU 16.2.1
...
-- Checking for module 'gio-2.0'
--   Found gio-2.0, version 2.88.3
CMake Warning (author) at /usr/lib/cmake/Qt6Core/Qt6CoreMacros.cmake:3565 (message):
  Qt policy QTP0001 is not set: ':/qt/qml/' is the default resource prefix
  for QML modules. ...
  CMakeLists.txt:26 (qt_add_qml_module)
-- Configuring done (1.0s)
-- Generating done (0.0s)
```
Exactly **one** warning: QTP0001 policy unset (CMakeLists.txt never calls `qt_policy(SET QTP0001 NEW)`). Cosmetic, not fatal — indicates the CMake file hasn't been revisited against current Qt6 (6.11.1) policy warnings.

### 2.3 Build output (verbatim, complete — `cmake --build . -j$(nproc)`, 66 lines total)

Full log captured to `/tmp/claude-1000/-home-josema/acecd47b-dab7-4771-bcea-4881a4dfb569/scratchpad/build-full.log`. Representative excerpt:
```
[ 25%] Building CXX object CMakeFiles/omafiles-backend.dir/backend/ProcessRunner.cpp.o
...
[ 92%] Linking CXX shared library qml/Omafiles/Backend/libomafiles-backend.so
[ 92%] Built target omafiles-backend
...
[100%] Linking CXX executable omafiles-standalone
[100%] Built target omafiles-standalone
```

**Result: build succeeded 100%, zero compile errors, zero compile warnings, did not time out.** `grep -in "warning\|error"` over the complete log returns nothing beyond the single configure-time QTP0001 warning.

**Caveat — "zero warnings" does not mean "clean code":** `flags.make` shows `CXX_FLAGS = -O3 -DNDEBUG -std=gnu++17 -fPIC -mno-direct-extern-access` — **no `-Wall`, `-Wextra`, or `-Wpedantic` anywhere in CMakeLists.txt**. Across 61 backend `.cpp` files + `main.cpp`, "zero warnings" mostly reflects that GCC's diagnostics were never turned on, not that the code is warning-clean. No compiler-warning gate exists, so issues like unused variables, sign-compare, or shadowing would be silently invisible in every build, including any CI that just checks build success.

Verified build products: `omafiles-standalone` binary (69,696 bytes, executable), `qml/Omafiles/Backend/libomafiles-backend.so` (721,688 bytes) plus `qmldir`/`.qmltypes`/`.qrc` as expected.

### 2.4 git working-tree state

```
$ git status --short
?? omafiles-0.9.0.tar.gz
```
Only the known untracked build artifact at repo root — nothing else untracked, staged, or modified against `v1.0-dev` HEAD. The pre-existing `build/` directory at repo root was noted but not touched or built into.

### 2.5 `selfcheck` target

Custom target (CMakeLists.txt lines 205-217), **not** part of `ALL` — does not run during a normal `cmake --build .`; must be invoked explicitly (`--selfcheck` flag on the built binary, as done in §1.2 above).

---

## 3. Packaging (PKGBUILD accuracy)

`packaging/arch/PKGBUILD` (25 lines, read in full) has **multiple concrete, build-breaking defects**, empirically confirmed, not inferred:

### 3.1 CRITICAL — source URL 404s
- `url="https://github.com/omafiles/omafiles"`, `source=(...github.com/omafiles/omafiles/archive/v${pkgver}.tar.gz)`.
- Actual `git remote -v`: `origin https://github.com/Percius04/omafiles.git`.
- Verified directly: `curl -o /dev/null -w '%{http_code}' https://github.com/omafiles/omafiles` → **404**; the `Percius04` URL → **200**.
- `makepkg` fails immediately at the download step — this PKGBUILD cannot build at all as written.

### 3.2 CRITICAL — install() paths hardcoded to `$ENV{HOME}`, ignore `CMAKE_INSTALL_PREFIX`/DESTDIR entirely
CMakeLists.txt never calls `include(GNUInstallDirs)` and never references `CMAKE_INSTALL_PREFIX` (`grep` → zero hits). Instead:
```
OMAFILES_DATA_INSTALL_DIR "$ENV{HOME}/.local/share" CACHE PATH ...   (line 123-124)
OMAFILES_QML_INSTALL_DIR  "$ENV{HOME}/.local/lib/qt6/qml" CACHE PATH ... (line 127-128)
OMAFILES_BIN_INSTALL_DIR  "$ENV{HOME}/.local/bin" CACHE PATH ...     (line 157-158)
```
**Empirically reproduced**: re-configured with `-DCMAKE_INSTALL_PREFIX=/usr` (the exact flag the PKGBUILD passes) and inspected the resulting cache — all three paths remained pinned to `/home/josema/.local/...`; `-DCMAKE_INSTALL_PREFIX` had zero effect. Consequence: `DESTDIR="${pkgdir}" cmake --install build` would install everything under `${pkgdir}/home/<build-user>/.local/...`, never under `${pkgdir}/usr/...` — a fundamentally non-functional system package.

### 3.3 HIGH — version/tag mismatch
`pkgver=0.9.0` corresponds to a tag that lives only on `master` (`git branch --contains v0.9.0` → only `master`/`origin/master`; `git merge-base --is-ancestor v0.9.0 HEAD` → not an ancestor). Current HEAD is `v0.9.0-rc2-15-gbf38073` on branch `v1.0-dev` — the PKGBUILD pins a different branch's snapshot than the one under audit.

### 3.4 HIGH — sha256sum unverifiable
64-hex-char, valid format, but since the source URL 404s (§3.1) it cannot correspond to any actual successful download — unverifiable as it stands.

### 3.5 MEDIUM — dependency list problems
- **Missing** a provider for `Qt6::Pdf` (required by CMakeLists.txt line 8). Verified on this system: `Qt6PdfConfig.cmake` is provided by `qt6-webengine`, not any standalone `qt6-pdf` package — a clean chroot with only the listed `depends` would fail `find_package` at configure time.
- **Spurious**: `qt6-5compat` — grepped entire repo for `Core5Compat`/`5compat`/`QtCore5Compat`, zero matches; CMakeLists.txt never requests it. Unused dead weight.
- `qt6-base` (Core/Gui/Network/DBus) and `qt6-declarative` (Qml/Quick/QuickControls2) are correctly listed. `glib2` correctly covers `gio-2.0`.

### 3.6 MEDIUM — license/URL mismatch vs. the repo's own LICENSE and README
- PKGBUILD: `license=('GPL3')`. Actual `LICENSE` file: **MIT**, copyright Percius04. README.md line 283: "MIT — see LICENSE." The PKGBUILD's declared license is simply wrong.
- Same owner-mismatch as §3.1: PKGBUILD points at `github.com/omafiles/omafiles`, README's clone instructions and LICENSE both point at `Percius04`.

### 3.7 build()/package() functions
Structurally conventional Arch packaging boilerplate — the *pattern* is correct, but neutralized by §3.2 and never reached in practice because of §3.1.

**Overall: this PKGBUILD would fail at the very first `makepkg` step (download), and even with source/URL fixed, would produce a non-functional package due to the CMake install-path bug.**

---

## 4. Performance

### 4.1 What's sound and was reproduced live

`bench/perfbench.cpp`, `measure-ui-guard.qml`, `measure-search.qml` are methodologically sound: they call real production entry points (`DirectoryModel::list()`, `DirectoryModel.signature`, `Backend.SearchWorker.search()`) against real files on real disk (`~/.cache/omafiles-perfbench` confirmed via `findmnt` to be `/dev/nvme0n1p2`, real NVMe). Reproduced live, matching `baseline.json` within normal run-to-run noise:
```
perfbench 10k:  listing=25.28ms entries()=2.87ms   (baseline: 25.55/2.88)
perfbench 100k: listing=300.93ms entries()=44.38ms (baseline: 306.38/45.68)
measure-search.qml: Report=3ms/200, 999=78ms/200 (baseline: 3ms, 77ms)
--selfcheck: 85 passed, 0 failed, 85 total — matches §1.2 exactly
```

### 4.2 `bench_file_operations()` in `bench-gate.py` — methodology is broken

It calls `shutil.copy2`/`copytree`/`rmtree` directly from Python — **never** invokes `FileOperations::copy/remove`, `FileOpsPrivate::copyTree/removeTree`, the `QThreadPool` dispatch, the throttled progress-signal emission, the atomic-cancellation check, or the `treeSize()` pre-scan the real app always does. It benchmarks the kernel's file I/O and Python's stdlib, not the app. A regression in the app's own copy/delete threading or progress-marshaling code would produce **zero change** in this number.

It also runs on the **wrong storage medium**: `tempfile.TemporaryDirectory()` with no `dir=` lands on `/tmp`, confirmed via `findmnt` to be RAM-backed `tmpfs`, not disk — directly contradicting `bench/README.md`'s "Hardware baseline: NVMe storage" claim and `PHASE35_PERFORMANCE_BASELINE_REPORT.md`'s explicit "Tested on local NVMe filesystem" line for this exact table. Reproduced: `copy_100mb_ms=30.69 → 3257.93 MB/s` (baseline 32.5ms/3077 MB/s — consistent, but both are tmpfs, not NVMe).

### 4.3 Claims with zero supporting tooling in the repo

Searching the entire tree for benchmark code (`find . -iname "*bench*"`) finds only the 7 files in `bench/`; `docs/benchmarks/` exists but is empty. Yet `PHASE35_PERFORMANCE_BASELINE_REPORT.md` cites specific figures for: Thumbnail Pipeline (§5), Preview Pipeline (§6), several File Operations rows beyond the two shutil-covered ones — "Atomic Rename," "Trash + Restore Round-Trip," "Cooperative Cancellation" (§7, zero grep hits for these terms outside the markdown), Filesystem Watcher Performance (§9), Memory & CPU Profile (§10), and a "Top 10 Measured Bottlenecks" table (§11) labeled "Measured" despite none of its rows appearing in any `bench/` script. These may be real hand-measurements never captured as reproducible tooling, or may be estimated — **from the repo alone there is no way to tell; must be treated as UNVERIFIED**, not "measured" as the section headers claim.

### 4.4 `PHASE38`'s release-recommendation overstates coverage

Its claim that "all hot paths... meet or exceed release performance baselines" names 5 subsystems; only 3 are genuinely exercised by `bench-gate.py`'s actual `run_all_benchmarks()`. "Native content search" is not exercised (the bench only drives the `SearchWorker` fallback tier, not the primary tracker3/plocate index path or the ripgrep content-search tier). "Media metadata extraction" (`backend/MediaInfo.cpp` + 5 per-format files) has zero corresponding tooling.

### 4.5 Two concrete, reproduced bugs in the regression gate (`bench-gate.py`)

- **`classify_delta()`'s baseline==0 blind spot** (line 311-312): short-circuits to `("UNCHANGED", 0.0)` whenever baseline is exactly 0, before computing any real delta. Reproduced live: `classify_delta(baseline=0.0, current=999.0, unit="ms")` → `('UNCHANGED', 0.0)` — a near-1-second regression silently ignored. Checked against `baseline.json`'s actual `ui_guard` block: **3 of 4 UI-guard metrics have baseline exactly 0.0**, meaning the automated gate can structurally never flag a regression in the O(1) content-signature guard for 1k/50k/100k-row directories — the exact invariant this measurement exists to protect.
- **Checked-in `PHASE38` report is not reproducible from current script**: its `rows_10002` row claims status "IMPROVED" for the baseline/current pair (0.001, 0.0), but feeding that exact pair through the live `classify_delta()` now returns `UNCHANGED` (an absolute-noise-floor check added later, `diff_abs=0.001 < 0.005`). The delta percentage matches but the status doesn't — the report was either generated by an earlier, now-diverged script version, or hand-edited.
- **`--threshold` CLI flag is a no-op**: read once (line 495) and used only in the failure print string; the actual pass/fail classification references hardcoded module constants `THRESHOLD_NOISE/WARNING/REGRESSION` directly. Loosening or tightening `--threshold` changes nothing about gate outcome.

### 4.6 Freshness risk

`bench_startup()` prefers `~/.local/bin/omafiles` over a fresh `build/` binary if present. That installed binary's mtime (2026-08-14 22:42:57) is ~17 hours and an unknown number of commits behind HEAD (2026-08-15 15:38:29) — any perf work in that window is invisible to `--compare`/`--check-gate` unless the operator remembers to rebuild+reinstall. No staleness check exists for this binary (unlike `build_perfbench()`, which does check mtime).

### 4.7 Summary

| Tool/claim | Sound? |
|---|---|
| perfbench.cpp, measure-ui-guard.qml | YES — reproduced live |
| measure-search.qml | Sound as far as it goes, but only benches the degraded-mode fallback search tier, not the primary tracker3/plocate path |
| bench_file_operations (copy/delete) | NO — bypasses `FileOperations` entirely (shutil), runs on tmpfs not NVMe despite explicit claims otherwise |
| PHASE35 §5,6,9,10,11 | UNVERIFIABLE — no tooling exists for any of it |
| PHASE38 "all hot paths meet baselines" | OVERSTATED — 2 of 5 named subsystems have zero bench coverage |
| `classify_delta` baseline==0 handling | BUG — disables regression detection for 3/4 ui_guard metrics |
| PHASE38 report vs. live script | MISMATCH on `rows_10002` status |
| `--threshold` flag | NO-OP |
| Startup binary freshness | STALE at time of audit, no staleness guard |

---

## 5. Documentation Accuracy

Docs read in full: README.md, CLAUDE.md, AGENT_BOOTSTRAP.md, CHANGELOG.md, `docs/architecture/{ARCHITECTURE,BACKEND_DESIGN,DEPENDENCY_GRAPH}.md`, `.claude/omafiles/`.

### 5.1 CRITICAL — `AGENT_BOOTSTRAP.md`'s mandatory read order is broken
Instructs reading `.claude/omafiles/{PROJECT_DIRECTOR,WORKFLOW,ROADMAP}.md` first. Verified via `find .claude -type f`: none of these three exist. `.claude/omafiles/DECISIONS/` exists but is an empty directory. Any agent following this file's own literal instructions fails at step 1 — and CLAUDE.md itself delegates the entry point to this file.

### 5.2 CRITICAL — `.claude/omafiles/PROJECT_STATE.md` is a release behind, and self-contradicts current source
Frozen at "Phase 42 / RC2," while README/CHANGELOG declare the shipped state v0.9.0 stable. Checkbox `42.3` ("Intelligent Network Behavior... ephemeral credential handling") is marked unchecked, yet `CHANGELOG.md` line 17 claims this exact feature (`NetworkResolver`) as shipped. Checkbox `42.1` claims `gtk-launch` was replaced by native `MimeResolver` — **false against current code**: `logic/NavigationController.qml:219` (`openWithDefault`, live/reachable, called from `CommandFacade.qml:225`, `BackgroundListDelegate.qml:125`, `ActionEngine.qml:1201`) still shells out via `bash -c` to `xdg-mime query` (twice) and `gtk-launch`.

### 5.3 HIGH — README's "no longer required: xdg-mime... gio (shell commands)" is false for a live code path
`NavigationController.qml:218-220` spawns `bash -c 'id=$(xdg-mime query default ...); gtk-launch "$id" ...'` — a live shell-out to exactly the tools README (line 239) says were eliminated. Not dead code; called from 4 sites. Not documented in README's "Optional dependencies" table either.

### 5.4 HIGH — `DEPENDENCY_GRAPH.md` describes a controller architecture that no longer exists
Graphs 11 `logic/` components (`ArchiveActions`, `BookmarkOps`, `ClipboardOps`, `ConflictActions`, `DeleteOps`, `DragDropOps`, `FileOps`, `OpenWithOps`, `RenameOps`, `SelectionOps`, `SortOps`) that do not exist in the current 14-file `logic/` directory — matching CHANGELOG's own claim that these were consolidated into `ActionEngine.qml`, but the graph was never regenerated despite the doc's own footer giving explicit regeneration instructions. Cross-checked against `core/ControllerRegistry.qml` directly: none of the 11 removed names appear; `CustomActions`/`DirLister`/`SearchBackend` (which do exist) are absent from the graph. Doc header claims "Regenerated 2026-08-09 after Phase 14.D" — at minimum ~29 phases stale. Also contains the stale "77/77" selfcheck count (line 99) refuted in §1.2 above.

### 5.5 HIGH — `ARCHITECTURE.md` names dead files and its own rules are actively violated
- Lists `DeleteOps.qml, RenameOps.qml, ClipboardOps.qml, DragDropOps.qml, FileOps.qml` as `logic/` examples (line 40) — none exist.
- States a "<300 Lines Limit... no monolithic controller merges permitted" rule (line 75). `logic/ActionEngine.qml` measures **1205 lines** (confirmed, largest file in the repo) — 4x the limit, and is precisely the monolithic merge the rule forbids and CHANGELOG celebrates. `NavigationController.qml` (303 lines) also exceeds it.
- States `logic/` never imports `shared/` (line 78-79). `grep -rn '"\.\./shared' logic/*.qml` hits 8 of 14 files (`FileMeta`, `NavigationController`, `PropertiesLoader`, `PreviewLoader`, `ActionEngine`, `CustomActions`, `MountActions`, `VideoThumbnails`) — the majority of `logic/` violates the stated rule.

### 5.6 MEDIUM — `BACKEND_DESIGN.md` self-reports "RC1" status and has a factually wrong roadmap row
Status line says "RC1" while the shipped product is v0.9.0 stable. Roadmap row `6.B MimeDb` says "not done (type detection still extension-based)" — but `backend/MimeResolver.cpp` (lines 6, 104-105) includes `<QMimeDatabase>` and calls `db.mimeTypeForFile(path)` — it *is* done, directly contradicting the doc's own roadmap status for the same work item (and matching README/CHANGELOG's correct claim).

### 5.7 MEDIUM — PKGBUILD disagrees with LICENSE and clone URL
Already detailed in §3.1/§3.6 — `GPL3` vs. actual MIT, and `github.com/omafiles/omafiles` vs. actual `Percius04/omafiles`.

### 5.8 MEDIUM — `ARCHITECTURE.md`'s `backend/` listing is a small non-representative fraction
Lists 12 backend files; actual `backend/` has 61, missing entire subsystems (`Env`, `Detached`, `Notifier`, `MimeResolver`, `TerminalResolver`, `NetworkResolver`, `MediaInfo`+5 formats, `SyntaxHighlighter`+8 languages, `FileOperations_{Copy,Move,Remove,Trash}`) that README's own Architecture section and CHANGELOG separately and specifically describe — so this doc is stale even relative to the project's *other* documentation, not just the code.

### 5.9 LOW findings
- `bench/baseline.json` is version-labeled `v0.9.0-rc1-pre2`, not regenerated for the stable v0.9.0 tag that README's quality-gate section attaches it to.
- Stale in-source comments (`backend/PreviewProvider.h:13-14`, `logic/PreviewLoader.qml:15`, `state/PreviewContentState.qml:24,31`) still reference `ffprobe` for audio metadata; actual implementation (`backend/PreviewProvider.cpp:28-33` → `MediaInfo::extract()`) is fully native C++. Here the *audited* docs (README/CHANGELOG) are correct — it's in-source comments that lag.

### 5.10 Claims verified as TRUE (not stale)
- **85/85 selfcheck** — see §1.2, matches README/CHANGELOG exactly.
- **Performance Regression Gate** — `bench-gate.py --check-gate` runs as described and returns "PASSED" (though see §4 for gate soundness caveats).
- **Top-level directory structure** (`app/`, `core/`, `backend/`, `logic/`, `state/`, `panels/`, `dialogs/`, `shared/`, `scripts/`, `src/selfcheck/`) matches ARCHITECTURE.md.
- **Keyboard shortcuts table** (README lines 132-162) spot-checked against `KeyboardShortcuts.qml` — matches.
- **Native `MimeResolver`** claim — confirmed.
- **LICENSE = MIT** — matches README (contradicted only by PKGBUILD).
- No "Gemini" author/attribution anywhere in `*.md` docs or git history.

---

## Overall verdict

The build is genuinely solid (100% success, real artifacts, real selfcheck pass) and the strongest part of the codebase — filesystem operations, trash/restore, and directory listing/sort — is backed by real, comprehensive, executable tests and real, reproducible benchmarks. The weaknesses cluster in three places: (1) **packaging is currently non-functional** (wrong URL, hardcoded home-directory install paths that ignore `CMAKE_INSTALL_PREFIX`, wrong license, stale version pin); (2) **documentation has drifted significantly behind the actual v1.0-dev source** — architecture docs describe a pre-consolidation controller layout that hasn't existed for ~29 phases, the project's own governance bootstrap file points at three nonexistent files, and several "done" claims (native-only mime handling, no-shell-out architecture) are contradicted by live, reachable shell-out code; (3) **performance reporting materially overstates what's actually measured** — the file-operations benchmark tests Python's stdlib on tmpfs rather than the app's own C++ backend on disk, several whole report sections (thumbnails, preview, watcher, memory/CPU) have no supporting tooling in the repo at all, and the automated regression gate has a bug that silently disables 75% of its own UI-guard regression detection.

All file/line references above point to the current working tree at `/home/josema/Projects/omafiles`, branch `v1.0-dev`, HEAD `bf38073`. No source files were modified during this audit; all builds were performed outside the repository.

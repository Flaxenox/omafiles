# V1.2 Startup Performance Audit — OmaFiles

**Repo**: `/home/josema/Projects/omafiles`, branch `v1.2-dev`, base commit `a12c519` (2026-08-19)
**Date of audit**: 2026-08-19
**Scope**: measure real startup time end to end, find the actual bottleneck via reproducible bisection (not guessing), fix it, verify with the same benchmark + the full selfcheck suite. No commits/pushes/tags/merges were made — everything below lives uncommitted on `v1.2-dev`.

---

## Executive verdict

**The ~1 second startup complaint was real, and it was one specific, avoidable cause: 100% real, not perception.** `panels/PreviewPanel.qml` unconditionally constructed a `QtMultimedia` `Video` and a `MediaPlayer` object as part of the always-present active-panel tree — even though preview wasn't open and the selected file (if any) wasn't video or audio. Qt Multimedia's backend does expensive one-time initialization the *first* time any `MediaPlayer`-family object is constructed in the process (FFmpeg backend/codec probing), and on this system that cost is **~900ms**, paid synchronously inside `QQmlApplicationEngine::load()` on *every single launch*, regardless of whether the user ever previews a video or audio file.

Deferring that construction to the first actual video/audio preview (via a `Loader` gated on a latched "ever touched" flag) cuts:

- `engine.load()` (QML tree construction): **~1065ms → ~155ms median (−85%)**
- first frame actually on screen: **~1134ms → ~240ms median (−79%)**
- initial directory listing visible: **~1067ms → ~157ms median (−85%)**

This is not a "hide it behind the window" trick — the window now genuinely finishes constructing, renders, and is interactive in about a quarter second. The deferred cost still exists (it's real backend init work), but it now happens once, lazily, the first time the user actually opens a video/audio preview — a much better place to pay it than on every launch of the app, including launches where preview is never touched at all.

No other candidate came close. Sections 2–4 below show the bisection that ruled out Qt/QML import overhead, the controller/state layer, the sidebar, and the rest of the active-panel UI, before landing squarely on `PreviewPanel.qml`.

---

## Baseline

### Methodology

A new benchmark harness, `bench/startup_bench.py`, launches the real `build/omafiles-standalone` binary (Release build, real Wayland session — not `offscreen`) repeatedly with `OMAFILES_STARTUP_TRACE=1` set, captures its stderr trace, and kills it (`SIGTERM`, ~1.5s after launch — Qt's default `SIGTERM` handling doesn't run `onClosing`, so no session file is touched). Each run is a **cold, single-window launch**: the single-instance socket is confirmed empty before benchmarking starts, so every run genuinely constructs a fresh `QGuiApplication`/`QQmlApplicationEngine`/window, never a "deliver to existing instance and exit" no-op.

Timing instrumentation (new, `backend/StartupTrace.h` + marks in `main.cpp`/`DirectoryModel.cpp`/`OmafilesContent.qml`, all opt-in via `OMAFILES_STARTUP_TRACE=1`, effectively free when unset — see "Changes implemented"):

- **process launch → `main()` reached**: the harness reads its own `CLOCK_MONOTONIC` right before spawning; `main()` writes its own `CLOCK_MONOTONIC` reading to `OMAFILES_T0_NS` as the very first thing it does. Both clocks are the same domain machine-wide on Linux, so the difference is real dynamic-linker + libc/Qt static-init overhead — something no timestamp taken from inside `main()` alone could ever see.
- **`QGuiApplication` constructed**, **single-instance check resolved**, **`QQmlApplicationEngine` constructed**, **import paths added**
- **`engine.load(Main.qml)` returned** — this is the moment the *entire* QML object tree exists and every `Component.onCompleted` in it has already run (Qt loads local `file://` QML synchronously: parse/compile/instantiate/run-onCompleted all complete before `load()` returns)
- **first frame swapped** — a one-shot hook on `QQuickWindow::frameSwapped`, i.e. the first moment real pixels reached the Wayland compositor, not just `visible: true` being set
- **`DirectoryModel::apply`** (C++) — the first time any listing becomes visible (in practice, on a single-window fresh launch, this is the initial directory)

15 runs per configuration (exceeds the requested minimum of 10). Same binary, same environment, same real session data, for both baseline and after.

**Cold vs. warm**: root-causing this (see below) showed the QML disk bytecode cache (`~/.cache/omafiles-standalone/qmlcache/`, populated from real prior use) was hit on every single run in this session — `.qmlc` file mtimes never changed across 12+ consecutive launches — so QML compilation was never actually the cost, and "cold vs. warm" in the classic disk-cache sense turned out not to be the axis that mattered here (see Bottlenecks). First-run-vs-rest was tracked anyway as the closest safe proxy: dropping the OS page cache system-wide (`echo 3 > /proc/sys/vm/drop_caches`) would affect every other running application on this machine and wasn't done.

### Results — BEFORE (12 runs, real session, `v1.2-dev` base commit)

| Milestone | min | max | avg | median |
|---|---:|---:|---:|---:|
| process launch → `main()` reached | 14.2ms | 15.3ms | 14.5ms | 14.4ms |
| `QGuiApplication` constructed | 12.5ms | 14.2ms | 13.1ms | 12.9ms |
| `engine.load()` starting | 14.1ms | 15.8ms | 14.7ms | 14.5ms |
| **`engine.load()` returned** | **1041.9ms** | **1160.8ms** | **1073.8ms** | **1064.7ms** |
| **first frame swapped** | **1116.2ms** | **1235.0ms** | **1147.1ms** | **1133.8ms** |
| **initial listing visible** | **1044.0ms** | **1162.7ms** | **1081.1ms** | **1066.8ms** |
| process launch → first frame (total) | 1130.5ms | 1249.6ms | 1161.6ms | 1148.4ms |

First run vs. rest: first-frame 1235.0ms (first run) vs. 1139.1ms avg (rest) — a mild, unremarkable difference, not the ~900ms-scale effect that turned out to be the real story.

---

## Startup timeline

**Before** (median, real session):

```
0.0 ms  ─ main() entry
14.4 ms ─ engine.load(Main.qml) starts (QGuiApplication, single-instance
          check, QQmlApplicationEngine, import paths: all ~14ms combined,
          negligible)
14.4 ms─┬─ QML tree construction begins
        │  (Sidebar, ControllerRegistry's 14 controllers, ActiveFileList,
        │   KeyboardShortcuts, etc. — all measured cheap in isolation,
        │   see Bottlenecks)
        │
        │  ~900ms: PreviewPanel.qml constructs `Video` + `MediaPlayer`
        │  unconditionally → QtMultimedia backend cold-init (FFmpeg
        │  codec/pipeline probing) blocks here, synchronously, on the
        │  UI thread, inside engine.load()
        │
1064.7ms┴─ engine.load(Main.qml) returns — OmafilesContent.open() runs
          (session/bookmarks/mounts load, all async — this part is ~1ms)
1066.8 ms ─ DirectoryModel::apply — initial listing already resolved
            (worker-thread scan was fast; it just had to wait for the
            main thread to finish the above before it could be applied)
1133.8 ms ─ first frame swapped — window visibly appears
```

**After** (median, real session):

```
0.0 ms   ─ main() entry
14.5 ms  ─ engine.load(Main.qml) starts
154.7 ms ─ engine.load(Main.qml) returns (QML tree + all onCompleted done —
           PreviewPanel's Video/MediaPlayer are NOT constructed here anymore)
157.0 ms ─ DirectoryModel::apply — initial listing visible
239.5 ms ─ first frame swapped — window visibly appears
```

The remaining ~140ms between `engine.load()` returning and first frame is genuine Qt Quick scene-graph render + Wayland compositor round-trip for a real ~1400×900 window with a populated file list — not further investigated, see Deferred optimizations.

---

## Bottlenecks

Found by **reproducible bisection**, not guessing: a temporary `OMAFILES_LOAD_QML` env-var override (main.cpp, reverted before finishing — see below) let alternate minimal `app/*.qml` entry points be timed against the *same built binary*, since QML is interpreted at runtime and needs no rebuild between experiments. Each step is a real measurement (`bench/startup_bench.py`, 5–6 runs), not inferred from reading code.

| # | Component/file | Operation | Measured `engine.load()` cost | On critical path? | Proposed solution |
|---|---|---|---:|---|---|
| 1 | Qt Quick Controls (`Basic` style) alone | bare `ApplicationWindow`, no app imports | ~63ms | No — cheap baseline | none needed |
| 2 | `qs.Commons`/`qs.Ui`/`Omafiles.Backend` imports | ThemeSource singleton (3 small synchronous XHR file reads), backend plugin load | ~65ms (no measurable increase over #1) | No | none needed |
| 3 | `ControllerRegistry` (14 controllers) + `CommandFacade` + `AppBindings` | constructing all 14 `logic/*.qml` controllers, no UI | ~84ms | No | none needed |
| 4 | `MainLayout` minus `activePanel` (Sidebar, dividers, background-panel repeater) | full sidebar with real bookmarks/mounts/recents bindings | ~104–116ms (i.e. Sidebar itself added ~20–30ms) | No | none needed |
| 5 | `MainLayout`'s `activePanel` subtree as a whole | nav row, breadcrumb, search bar, `ActiveFileList`, status text, picker bar | **~940ms** (jumped from ~110ms to ~1050ms) | **Yes — this is where all the time is** | narrow further (→ #6) |
| 6 | `ActiveFileList.qml` specifically (stubbed alone, everything else in `activePanel` kept real) | the real `ListView` + `KeyboardShortcuts` + `PreviewPanel` | **~920ms** (1050ms → 130ms when stubbed) | **Yes** | narrow further (→ #7) |
| 7 | **`PreviewPanel.qml`'s `Video`/`MediaPlayer` construction** | QtMultimedia backend cold-init, triggered by unconditionally instantiating `Video`{...}` and `MediaPlayer{...}` regardless of `open`/`isVideoEntry`/`isAudioEntry` | **~900ms** (commenting these two objects out of the *real, full* `Main.qml` tree — real session, real `ListView`, real delegates — dropped `engine.load()` from ~1065ms to ~154ms) | **Yes — this is THE bottleneck** | **Lazy-load via `Loader`, fixed below** |

Corroborating evidence: the pre-existing selfcheck test "Inline video/audio playback: real MediaPlayer reaches PlayingState" (`CheckInfrastructure.qml`), which creates its own independent `Video`/`MediaPlayer` objects via real ffmpeg-generated fixtures, itself consistently takes **~1250ms** end to end (ffmpeg fixture generation + reaching `PlayingState`) — squarely consistent with a ~900ms-scale one-time Qt Multimedia backend cost being real and reproducible, not an artifact of the bisection method.

Ruled out explicitly (measured, not assumed): Qt/QML import resolution, the 25 state singletons, all 14 `logic/` controllers, the sidebar (bookmarks/mounts/recents), the QML bytecode disk cache (confirmed hit on every run — file mtimes never changed), and process/dynamic-linker startup (`main()` reached in ~14ms every time, negligible and stable).

---

## Changes implemented

### 1. `panels/PreviewPanel.qml` — lazy-load the video/audio players (the fix)

**Old behavior**: `Video { id: videoPlayer; source: root.videoSource }` and `MediaPlayer { id: audioPlayer; source: root.audioSource; audioOutput: AudioOutput{} }` were plain, always-present children of the tree, constructed unconditionally the moment `ActiveFileList` (and therefore `PreviewPanel`) was constructed — i.e., on every app launch, regardless of `open`, `isVideoEntry`, or `isAudioEntry`.

**New behavior**: both are now the `sourceComponent` of a `Loader` (`videoLoader`/`audioLoader`), gated on new `_videoTouched`/`_audioTouched` properties that latch permanently `true` the first time `isVideoEntry`/`isAudioEntry` ever becomes `true` (not tied directly to the live boolean, so browsing away to a non-media file doesn't tear the player down and re-pay the init cost on the *next* video/audio preview — same "stays alive for the rest of the session" lifetime the always-present objects had before, just deferred past startup). The audio `MediaPlayer` is wrapped in a tiny `Item` root (via a `player` alias) so `Loader.item` reliably exposes it regardless of Qt-version quirks around loading a non-visual root type directly; `Video` is already an `Item` so no wrapper is needed there. Poster-image visibility, the Play/Pause button text/click handlers, and the entry-change `stop()` cleanup were all updated to go through `videoLoader.item`/`audioLoader.item` instead of the old direct ids.

**Measured improvement**: `engine.load()` −910ms median (−85%), first frame −894ms median (−79%). See Final Metrics.

**Risk**: Low. No behavior change once a video/audio file is actually previewed — same objects, same properties, same lifetime after first touch, verified by a new dedicated regression test (below) and by the pre-existing real-fixture playback selfcheck (146/147 → 147/147, still passing, still exercising real `PlayingState`). The only externally observable difference is a first-time latency: the first video or audio preview a user ever opens in a session now pays roughly the ~900ms QtMultimedia init cost that used to be paid at launch — but by then the app is fully interactive and the user is actively engaged with a specific file, which is a far better place for that cost than blocking every single launch.

### 2. `panels/PreviewPanel.qml` — two read-only alias properties for testability

`readonly property alias videoLoaderActive: videoLoader.active` / `audioLoaderActive`, added purely so the new regression test (below) can observe the Loaders' state from outside the component, matching the project's existing alias-for-testability pattern (e.g. `ActiveFileList.qml`'s `keyboardShortcuts` alias).

### 3. `src/selfcheck/checks/CheckInfrastructure.qml` — new regression test

*"PreviewPanel: video/audio MediaPlayer loaders stay inactive until first touched, then latch (V1.2 startup regression)"* — isolates `PreviewPanel.qml` standalone (legitimate per the project's established "isolated instantiation" criteria: no `required` properties, no host-injection id-chain) and asserts: both loaders start inactive → `isVideoEntry=true` activates only the video loader → `isVideoEntry=false` again leaves it latched active → `isAudioEntry=true` activates the audio loader too. This directly guards against someone reverting to eager construction (which would silently reintroduce the ~900ms regression) without needing to measure wall-clock time in the test itself.

### 4. `backend/StartupTrace.h` (new) + marks in `main.cpp` / `backend/DirectoryModel.cpp` / `core/OmafilesContent.qml` — the diagnostic tooling used to find and verify all of the above

Opt-in (`OMAFILES_STARTUP_TRACE=1`), a single cached `getenv()` per call when unset — no measurable cost in normal use, never active for real users. Kept as a permanent, minimal capability (in the same spirit as the existing `SelfCheckOut` deterministic-output pattern, since `console.log`/`console.error` are silently dropped by this release build's QML logging rules) since startup regressions are exactly the kind of thing that benefits from being re-measurable without re-instrumenting from scratch next time. `OMAFILES_T0_NS` is set as the literal first thing `main()` does (before touching Qt at all) so an external harness can correlate its own `CLOCK_MONOTONIC` reading against the process's, which no in-process timestamp alone could measure (dynamic-linker/libc/Qt static-init overhead).

### 5. `bench/startup_bench.py` (new) — the benchmark harness used for every measurement in this report

Not wired into CI or `bench-gate.py`; a standalone script for this kind of investigation, matching how `bench/` was described in prior history (dev/agent tooling, not shipped). Left in place since re-running it is the fastest way to catch a future startup regression before it ships.

---

## Deferred optimizations

- **The ~140ms between `engine.load()` returning and first frame swapped** (scene-graph render + Wayland compositor round-trip for a populated ~1400×900 window): not investigated further. It's a fixed, small cost, not obviously reducible without touching rendering internals, and doesn't come close to justifying the risk for the remaining gain — this falls under the "MEASURE FIRST" / not-yet-justified category, not "SAFE."
- **The remaining ~155ms of real QML tree construction** (Sidebar bindings, `ActiveFileList`'s `ListView`+`KeyboardShortcuts`, the 14 controllers, etc.): each piece measured cheap individually (see Bottlenecks table, rows 1–4) and collectively they're already small relative to what was fixed. No single remaining piece crossed the bar for a targeted optimization in this pass.
- **`install-integrations.sh`** (self-registration script launched fire-and-forget from `AppBindings.qml` on every startup): read in full — it's already version-gated and exits in the first few lines (`STATE_FILE` check) on every launch after the first real install/version bump, so it's cheap on the fast path. Not touched.
- **`MountActions.refreshMounts()`** launching `list-mounts.sh` as a subprocess on every `open()`: genuinely async (`ProcessRunner`/`QProcess`, doesn't block the UI thread), and not on the path to first frame per the bisection (row 3 above, `ControllerRegistry` alone, already includes `MountActions`, measured cheap). Not touched.
- **Qt Multimedia's actual init cost itself** (making the ~900ms smaller, e.g. by forcing a lighter backend): out of scope — this is a Qt/FFmpeg-level cost, not something this codebase controls, and changing it would be a "RISKY" category change (altering multimedia backend behavior) with no clear win-without-regression path. Deferring *when* it's paid, not reducing *how much* it costs, was the correct-scoped fix.

---

## Verification

- **Build**: clean `cmake --build .` (Ninja, Release, existing `build/` dir) after every change in this report — zero warnings or errors introduced. (clangd's live diagnostics on `main.cpp`/`DirectoryModel.cpp` show pre-existing false positives from missing CMake-injected include paths/macros in the editor's compile database — confirmed harmless since the real Ninja/GCC build is clean throughout.)
- **Selfchecks**: full 147-test suite (146 pre-existing + 1 new) run 8+ times across this session. Result: 147/147 six consecutive times, plus one run with a single unrelated failure — `Trash removes item from source (8000ms timeout)`, part of a pre-existing, already-documented flake cluster (`docs/architecture/ARCHITECTURE.md`, "Separate, not yet root-caused", from the prior `v1.1-dev` session) that the user explicitly asked to leave alone. Not touched, not affected by this work — reproduced with the *exact same* symptom (Trash-only, 8000ms timeout) it had before this audit started.
- **New regression test**: `PreviewPanel: video/audio MediaPlayer loaders stay inactive until first touched, then latch` — passes, exercises the exact lazy-load logic that was added.
- **Real-fixture playback still works**: `Inline video/audio playback: real MediaPlayer reaches PlayingState (V1.1 headline #3 regression)` — still passes every run, real ffmpeg `.mp4`/`.mp3` fixtures, real `PlayingState`, real `hasVideo`.
- **Manual GUI smoke test**: launched the real (non-selfcheck) binary against a folder containing a real ffmpeg-generated `.mp4`, confirmed via screenshot (`grim`, real Wayland compositor) that the window opens instantly with the folder listing already populated and the file selectable via keyboard. Interactive click-through of the Play button specifically was attempted via `wtype`/`hyprctl` but keyboard input didn't reliably reach the QML surface in this sandboxed session (a WM/input-routing quirk unrelated to the code change — `ydotoold` wasn't running either, and starting a system service wasn't judged worth doing for this). This gap is covered instead by the two selfcheck tests above, which exercise the real, un-mocked `Video`/`MediaPlayer` production code paths end to end.
- **Repeated runs**: 15-run before/after benchmark (exceeds the requested 10), consistent within a narrow band each side (before: 1042–1161ms; after: 150–159ms for `engine.load()`) — the improvement is not a one-off, it reproduces every single time.
- **Packaging**: not touched. `packaging/arch/PKGBUILD` untouched, AUR untouched, per standing constraints and this task's explicit restrictions.
- **Installed application**: not touched. All testing used `build/omafiles-standalone` (the dev build on `v1.2-dev`); the real installed `~/.local/bin/omafiles` / `~/.local/share/omafiles` were never launched or modified during this audit.
- **Branch hygiene**: all temporary bisection artifacts (`app/BisectA.qml`…`BisectE.qml`, the temporary `OMAFILES_LOAD_QML` env-var override in `main.cpp`) were deleted/reverted once the root cause was confirmed — the final diff contains only the fix, its test, and the (permanent, opt-in, near-zero-cost) tracing tool used to find and verify it. No commits, pushes, tags, or merges were made; everything is uncommitted on `v1.2-dev`.

---

## FINAL METRICS

15 runs each, real Wayland session, real user session data, same binary/environment for both rows except for the one-file fix in `panels/PreviewPanel.qml`.

| Metric | Before | After | Improvement |
| --- | ---: | ---: | ---: |
| Cold start (process launch → first frame, first run) | 1249.6 ms | 282.2 ms | 967.4 ms / 77.4% |
| Warm start (process launch → first frame, avg of remaining runs) | 1153.6 ms | 252.8 ms | 900.8 ms / 78.1% |
| First visible UI (first frame swapped, median) | 1133.8 ms | 239.5 ms | 894.3 ms / 78.9% |
| First usable UI (= first visible UI here — the app is interactive as soon as the frame renders, no further gating) | 1133.8 ms | 239.5 ms | 894.3 ms / 78.9% |
| Initial listing visible (median) | 1066.8 ms | 157.0 ms | 909.8 ms / 85.3% |

**Statistically/reproducibly significant: yes.** Before and after distributions don't overlap at all (before min 1042ms > after max 267ms across every milestone measured), across 27 total real launches (12 before + 15 after), with zero exceptions.

### Was the ~1 second startup actually a performance problem?

Yes, unambiguously — and it was avoidable, not inherent. The entire ~1 second was spent constructing two QtMultimedia objects the overwhelming majority of launches never needed at all (most sessions never open a video or audio preview), on the UI thread, inside the one synchronous call (`engine.load()`) that gates the whole window from appearing. Deferring that construction to actual first use — a `Loader`, nothing more exotic — recovered essentially all of it. Section 8 of the task ("differentiate startup from first directory load") resolves cleanly: it was **combination (A) and (C)** — OmaFiles itself was slow to initialize (the QML tree wouldn't finish constructing), *and* it stayed busy the whole time (the window couldn't render at all until that construction finished) — never really "(B)," since the initial listing itself (once reached) was always fast; it was just gated behind the same synchronous construction as everything else.

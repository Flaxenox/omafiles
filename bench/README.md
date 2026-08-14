# bench/ — performance harness

Reproducible measurement tools for Omafiles' hot paths. They are **not** part of
the app and are never bundled with it; you run them by hand when you want to
measure or investigate performance.

They exist to answer one question with data: *did a change make a hot path
faster or slower?* No optimization should land without a before/after number
from one of these tools.

## What it measures

| File | What it measures |
|---|---|
| `gen-datasets.py` | Generates the test corpora under `~/.cache/omafiles-perfbench/{1k,10k,50k,100k}` — filenames with digits (exercise natural-order sort) and MixedCase (exercise case-folding), some subdirectories, and two symlinks (one valid, one broken). |
| `perfbench.cpp` | The real `DirectoryModel` path (`list()` async → `listed()` signal → `entries()`), separating *listing* time (scan + dispatch + apply) from *conversion* time (building the `QVariantList` the UI consumes). Reports the median of 9 runs, warm cache. |
| `measure-ui-guard.qml` | The **UI-thread** cost of the "did the folder change?" guard (an O(1) content-signature comparison) that replaced the earlier O(n) entry-by-entry compare. |
| `measure-search.qml` | Latency of `SearchWorker` — the native recursive name-search fallback used when no system index is available. |

Dataset paths are hardcoded in the `.qml` / `.cpp` sources to
`~/.cache/omafiles-perfbench/`, so `gen-datasets.py` must be run first.

## Requirements

- Qt 6 development files (`Qt6Core`, `Qt6Qml`) and `pkg-config`.
- A C++17 compiler (`g++`).
- `qml6` (the Qt Quick runtime) for the QML harnesses.
- Python 3 for `gen-datasets.py`.
- A configured CMake/Ninja build tree under `build/` (the C++ bench links
  against the compiled backend and its generated MOC source).

## Running the benchmarks

```sh
# 1) Generate the datasets (~161k files under ~/.cache/omafiles-perfbench/)
python3 bench/gen-datasets.py

# 2) C++ listing benchmark (build against the compiled backend)
cd build
g++ -std=c++17 -O2 -fPIC -I../backend -I. \
  $(pkg-config --cflags Qt6Core Qt6Qml) \
  ../bench/perfbench.cpp ../backend/DirectoryModel.cpp \
  $(find . -name moc_DirectoryModel.cpp) \
  $(pkg-config --libs Qt6Core Qt6Qml) -o perfbench
./perfbench

# 3) QML harnesses
#    Gotcha: without these two env vars, qml6 swallows console.log when
#    stderr is not a tty, and the harness prints nothing.
QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
  qml6 -I ~/.local/lib/qt6/qml bench/measure-ui-guard.qml
QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
  qml6 -I ~/.local/lib/qt6/qml bench/measure-search.qml
```

The harnesses run **offscreen** (`QT_QPA_PLATFORM=offscreen`): this measures real
CPU and memory times but not on-screen composition/frame time, which requires an
interactive graphical session and a frame profiler.

When you are done, remove the corpus (it is large):

```sh
rm -rf ~/.cache/omafiles-perfbench
```

## Reproducing a measurement

For a stable, comparable number:

1. Run on a warm cache (run the same benchmark twice; use the second result) so
   you measure code, not disk I/O.
2. Use `perfbench.cpp`'s median-of-9 output rather than a single run.
3. Compare the same dataset size before and after your change; report both
   numbers and the delta.
4. Keep the invariants green around any performance change:
   `omafiles --selfcheck` and `qmllint` on the touched QML.

## Reference Baseline (v0.9.0)

Hardware baseline: Linux x86_64, NVMe storage, Qt 6.5+.

### 1. `perfbench` (DirectoryModel C++, median of 9 runs, warm cache)

| Directory Size | Row Count | Listing Time (Scan + Sort + Apply) | `entries()` Conversion | Total Latency |
|---|---|---|---|---|
| `1k` | 1,002 | 2.21 ms | 0.34 ms | 2.55 ms |
| `10k` | 10,002 | 25.56 ms | 2.80 ms | 28.36 ms |
| `50k` | 50,002 | 135.38 ms | 13.55 ms | 148.93 ms |
| `100k` | 100,002 | 302.76 ms | 44.78 ms | 347.54 ms |

### 2. `measure-ui-guard.qml` (UI-Thread Content Signature Guard)

| Directory Size | 1,000 Signature Checks | Per-Call Latency | Lazy Read |
|---|---|---|---|
| `1k` – `100k` | ≤ 1 ms | < 0.001 ms | 0 ms |

### 3. `measure-search.qml` (SearchWorker Native Recursive Search on 100,000 files)

| Query | Results | Truncated | Search Latency |
|---|---|---|---|
| `"Report"` | 200 | Yes | 3 ms |
| `"img"` | 200 | Yes | 3 ms |
| `"999"` | 200 | Yes | 79 ms |
| `"Folder_0000"` | 2 | No (full tree walk) | 77 ms |

## Where results live

Recorded benchmark results, performance audits, and surrounding documentation
are maintained in the internal maintainer docs (`PHASE35_PERFORMANCE_BASELINE_REPORT.md`).
This directory ships the runnable tooling and reference baselines so anyone
can reproduce and compare measurements.


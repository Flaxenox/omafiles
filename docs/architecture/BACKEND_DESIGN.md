# C++ backend design (current state)

Regenerated 2026-08-17 (architectural-audit P1-5) to describe the backend
**as it exists**, not as a migration plan. The original phase-by-phase
migration plan (Phase 5 through 16, "how do we get from bash scripts to a
shared C++ module") is preserved for historical reference at
`docs/historical/BACKEND_DESIGN_PHASE5-16_PLAN.md` — that migration is
complete; this document replaces it as the canonical reference.

---

## 1. What it is

`backend/` compiles to a single shared library exposed to QML as one module,
`Omafiles.Backend` (`qt_add_qml_module`, see `CMakeLists.txt`). The Qt6
standalone frontend (the only frontend — see `ARCHITECTURE.md`, "What was
tried and abandoned") loads it by import path rather than linking it in
directly, which is a leftover of when a second (Quickshell) frontend also
needed to load the exact same `.so`; that requirement is gone, but the
by-import-path loading stayed because it works and there's no reason to
change it.

Design principles that still hold:

1. **QML describes the interface; C++ talks to the operating system.** No
   presentation logic in C++; no hand-rolled `QProcess`/`stat`/JSON parsing
   left in QML for anything performance- or correctness-sensitive.
2. **`logic/` imports `Omafiles.Backend` directly.** No adapter layer (see
   `ARCHITECTURE.md` on the retired `services/` proxy).
3. **Async by default.** Nothing callable from QML may block the UI thread
   except cheap, purely in-memory queries (`Env.get`, `existingPaths`,
   `totalSize`, `octalModes`, `cacheKey`).
4. **One class per `.h`/`.cpp` pair**, with large classes split by concern
   into `_Copy`/`_Move`/`_Remove`/`_Trash` (`FileOperations`),
   per-language (`SyntaxHighlighter`), or per-format (`MediaInfo`) files
   sharing one header — see Phase 41 in `ARCHITECTURE.md`'s "Phase 43"
   section for why this split pattern is the one to imitate.
5. **Every backend type with a live worker thread, process, or queued
   delivery back to the UI thread follows the `Life`+mutex lifetime pattern**
   described in `ARCHITECTURE.md`'s "Asynchronous ownership, cancellation,
   and lifetime model" section. This is not optional decoration — three of
   the four types that needed it were shipping with a real, confirmed
   use-after-free until the 2026-08-17 P0 concurrency pass. Read that
   section, not just this one, before adding a new async backend type.

---

## 2. Catalog of backend types

Grouped by concern. All are registered under the single `Omafiles.Backend`
URI; split into multiple URIs only if the type count grows enough to
justify it (currently ~30 types, still comfortably one module).

### Process, environment, persistence
| Type | Form | Backing |
|---|---|---|
| `ProcessRunner` | element | `QProcess`, request/response |
| `ProcessWatcher` | element | `QProcess` monitor mode (line-buffered streaming) |
| `Env` | singleton | `qEnvironmentVariable`/`qputenv` |
| `Detached` | singleton | `QProcess::startDetached` (fire-and-forget launches) |
| `Notifier` | singleton | desktop notifications |
| `JsonStore` | singleton | `QFile` + `QJsonDocument`, atomic write (temp file + rename) |

### Filesystem
| Type | Form | Backing | Lifetime pattern required |
|---|---|---|---|
| `DirectoryModel` | element | `QDirIterator`/`QFileInfo`, `QFileSystemWatcher` | ✅ `Life`+mutex (reference implementation — `scan()`/`scanMany()` are `static`) |
| `FileOperations` | `QML_SINGLETON` | worker thread per operation | ✅ `Life`+mutex + per-operation cancellation token (P1-4) |
| `SearchWorker` | element | `QThreadPool` worker, generation-counter cancellation | ✅ `Life`+mutex, generation counter is `shared_ptr`-owned (P0) |
| `FolderCounter` | singleton | async recursive count | — |
| `PathCompleter` | singleton | sync path completion | — |
| `UDisksWatcher` | singleton | D-Bus UDisks2 hotplug | — |
| `NetworkMounts`, `NetworkResolver` | singleton | GVfs mount enumeration/auth (GIO) | — |

### Preview / media
| Type | Form | Backing | Lifetime pattern required |
|---|---|---|---|
| `ThumbnailProvider` | `QML_SINGLETON` | `QThreadPool` worker + disk cache | ✅ `Life`+mutex (added 2026-08-17 — previously had **none**) |
| `PreviewProvider` | singleton | text preview reads | — |
| `SyntaxHighlighter` (+ per-language files) | element | native syntax highlighting | — |
| `MediaInfo` (+ per-format files) | singleton | audio/video metadata | — |

### Resolution
| Type | Form | Backing |
|---|---|---|
| `MimeResolver` | singleton | `QMimeDatabase` + XDG default-app resolution (replaces the retired `open-with-list.sh`) |
| `TerminalResolver` | singleton | terminal emulator discovery + launch, clipboard path copy |

---

## 3. Threading model

- The UI thread never does disk I/O that can take meaningfully long.
- Listing, search, thumbnails, and file operations dispatch to
  `QThreadPool::globalInstance()`; results are delivered back via
  `QMetaObject::invokeMethod(..., Qt::QueuedConnection)`.
- **Cancellation is a token, not a thread kill.** Two flavors exist, both
  `shared_ptr`-owned and operation/generation-scoped (never a plain shared
  member — see `ARCHITECTURE.md`):
  - a boolean flag (`FileOperations`, checked between chunks/tree entries);
  - a generation counter (`SearchWorker`, `DirectoryModel`; a result that
    arrives for a superseded generation is silently discarded).
- **Delivery is gated by a `Life`+mutex guard**, acquired via a `shared_ptr`
  copy taken *before* dispatch, wrapping the `invokeMethod` call itself (not
  merely the deferred functor's body) — see `ARCHITECTURE.md` for the full
  rule and the concrete mistake it was written to prevent.
- Every backend object that owns a live process or thread must be safe to
  destroy while that work is still in flight. This is verified, not just
  claimed: `bench/` and the selfcheck suite include lifetime-stress
  regression tests, and the three P0 use-after-frees were originally
  confirmed and later re-verified fixed with a standalone AddressSanitizer
  harness (documented in `docs/audits/P0_CONCURRENCY_REMEDIATION_REPORT.md`,
  reproduction command included there).

---

## 4. `scripts/runtime/` boundary

See `ARCHITECTURE.md`'s `scripts/runtime/` contract table for the current,
justified list. The rule for adding backend types vs. keeping a script: if
`QFileInfo`/`QMimeDatabase`/`QStorageInfo`/a small QProcess wrapper can do it
without linking a large native library (`libarchive`, `libblkid`,
`libavformat`, ...), it belongs in `backend/`, not in a new script.
`MimeResolver`, `NetworkMounts`, and `LocalMounts` are the most recent
examples of scripts retired this way (`open-with-list.sh`,
`list-network-mounts.sh`, `list-mounts.sh` -- the last one via UDisks2
D-Bus calls, not `libblkid`/`libudev`, since the running UDisks2 service
already exposes unmounted removable devices too).

---

## 5. Packaging boundary

`CMakeLists.txt` installs the backend `.so` + `qmldir` + `.qmltypes` to
`OMAFILES_QML_INSTALL_DIR` (default `~/.local/lib/qt6/qml`, override-able via
`-D` at configure time — this is what `packaging/arch/PKGBUILD` overrides to
`/usr/lib/qt6/qml` for a real system package; see
`docs/audits/P0_REMEDIATION_REPORT.md`, P0-5, for the exact flags and a
verified clean-`DESTDIR`-install reproduction). `main.cpp::resolveResourceDir()`
tries, in order: the source tree (dev workflow), the installed data dir
(`OMAFILES_DATA_INSTALL_DIR`, baked in at compile time), then
`$XDG_DATA_HOME/omafiles` at runtime — so a real end-user installation, which
never had the source tree, correctly falls through to the installed
resources without any of this being conditional on where the binary happens
to run from.

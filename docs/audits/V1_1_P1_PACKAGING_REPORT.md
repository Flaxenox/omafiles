# v1.1 P1: Packaging & Release Readiness

Baseline: `v1.1-dev`, starting from commit `57bee1a` (the P0 trash-freeze
hotfix, already on `master`/`v1.1-dev`; `v1.0-dev` was deleted by request
during this session — `v1.1-dev` is now the sole dev line).

---

## Post-P0 sanity audit — result

Performed first, as instructed, before any packaging work.

**Finding (real, fixed):** `logic/ActionEngine.qml`'s `restoreFromTrash()`
and `confirmDelete()`'s permanent-delete branch both build their native
call from `TrashState.trashInfo[name]`, and both used to silently drop any
name with no matching entry (`if (!info) return` / a `.filter()` that just
excludes it). Before the P0 fix, `TrashState.trashInfo` was always
populated synchronously in the same tick as the file listing, so this path
was unreachable in practice. After the fix, `NavState.currentPath` flips to
`Paths.trashDir` **synchronously** (`NavigationController._goToPath`) while
`TrashState.trashInfo`/`entries` only catch up once the now-async
`requestTrashInfo()` resolves (both land together, gated on the same
`onTrashInfoReady` — verified by re-reading the current `DirLister.qml`,
not assumed) — so there's a real window, e.g. rapidly re-entering Trash,
where "are we in Trash" can say yes before the shared `TrashState.trashInfo`
map has caught up for some or all items. Acting in that window used to be a
silent no-op with zero feedback.

**Fix:** both call sites now `Backend.Notifier.notify("Trash info is still
loading — try again in a moment")` instead of silently returning — same
established pattern used ~30 other places in this exact file. Also
corrected an inaccurate inline comment in `DirLister.qml` that claimed rows
render before their metadata (they don't; both are gated together — the
real gap is `currentPath` vs. everything else, as described above).

**Also considered and explicitly not changed:** `TrashState.trashInfo` is
deliberately never cleared on leaving Trash — confirmed via its own
existing doc comment (`state/TrashState.qml`), which references a real,
previously-fixed flicker bug from clearing it. A theoretically-possible
"stale same-name entry from a previous trash generation" edge case remains
(low probability, requires a specific same-named-file-trashed-twice
sequence); redesigning the shared-state model to close it would exceed
"use the existing architecture, don't redesign it," and the confirmed,
common-path regression above is fixed. Flagged here, not fixed, matching
this project's own established practice of being explicit about
intentionally-deferred edge cases rather than silently ignoring them.

**Regression test added:** `CheckFilesystemTrash.qml`, "Restore/permanent-
delete no-op safely when TrashState.trashInfo lacks the entry" —
deterministically strips one real entry from the shared map (rather than
racing real async timing, which would be flaky) and asserts no exception
and, more importantly, that the trashed file is verifiably untouched
afterward (via `existingPaths()`), proving the guard actually prevents the
native call rather than merely swallowing an error from a bad path.

**Full checklist result:**

| Dimension | Result |
|---|---|
| Ownership/lifetime | Clean — reuses `FileOperations`'s existing `m_life`/mutex guard verbatim |
| Thread safety | Clean — no shared mutable state touched from the pool-thread work |
| Signal delivery | Clean — `Qt::QueuedConnection` via `QMetaObject::invokeMethod`, matches audited pattern |
| Stale results | One real issue found and fixed (above); cross-instance staleness already guarded by `requestId` |
| Cancellation/navigation races | Guarded by `_dirMode`/`_trashReqId`; the one gap found is the fix above |
| Destruction during the async request | Clean — C++ `Life` guard + QML `Connections` auto-disconnects with its parent |
| No UI-thread FS work remains | Confirmed by code review and by the P0 regression test staying green |
| No regression in restore/permanent-delete | One found, fixed, regression-tested; all pre-existing restore/delete selfchecks still pass |

**Verdict: clean (after the one fix above).** Proceeded to P1.

---

## P1 findings and fixes

### 1. `packaging/arch/PKGBUILD`

| Item | Before | Finding | After |
|---|---|---|---|
| `pkgver` | `1.0.0` | The `v1.0.0` git tag predates the P0 trash-freeze fix (merged to `master` afterward) — packaging against it today would ship the exact freeze this whole cycle exists to fix | `1.0.1` |
| `source=`/checksum | Stale **0.9.0** tarball hash, mislabeled as `1.0.0`'s | No `v1.0.1` tag exists yet — computing a real hash is impossible, and the task explicitly forbids inventing one | URL updated to `v1.0.1`; `sha256sums` replaced with an intentionally-invalid placeholder (`0000...TODO`, not hex-valid) so `makepkg` fails loudly instead of silently accepting unverified or mislabeled content — see "Remaining blockers" |
| `depends` | `qt6-base qt6-declarative qt6-5compat qt6-webengine glib2 zip unzip` | `qt6-5compat` unused — grepped the whole QML tree for `Qt5Compat`/`QtGraphicalEffects`, zero hits. `python-gobject` **missing**: `install-integrations.sh` runs automatically on first launch (not opt-in) and installs 3 D-Bus services that all `from gi.repository import Gio, GLib` — without it, self-registration as default file manager silently fails | Dropped `qt6-5compat`; added `python-gobject`. Every remaining entry cross-checked against the actual linked libraries via `pacman -Qo` on this machine, not assumed |
| `optdepends` | **absent entirely** | README documents 7 optional packages with specific fallback behavior; PKGBUILD declared none of them | Added, verbatim matching README's table |
| `makedepends` | `cmake ninja qt6-tools` | `qt6-tools` provides `assistant/designer/linguist/lrelease/lupdate/qdbus` — none used; the QML tooling (`qmltyperegistrar`/`qmlcachegen`/`qmllint`) it might be confused for ships in `qt6-declarative`, already a dependency (confirmed via `pacman -Qo`) | Dropped |
| `build()`/`package()`/install paths | Correct | `OMAFILES_{BIN,DATA,QML}_INSTALL_DIR` overrides and `DESTDIR` staging verified correct by an actual `DESTDIR` install (see below), not re-derived from reading alone | Unchanged |

### 2. `scripts/install-integrations.sh`

**Root cause:** `RES_DIR` (the location the generated `.desktop`/D-Bus
`Exec=` lines point at) was hardcoded to `${XDG_DATA_HOME:-$HOME/.local/share}/omafiles`
unconditionally. Correct for the historical manual-install-only workflow;
wrong — and a stray write into `$HOME` — for a real system package under
`/usr` or any other prefix, where `Exec=` would then point at a per-user
path that was never populated, silently breaking "open folder"/"show in
file manager"/the FileChooser portal entirely.

**Fix:** `SELF_RES` (already computed from `BASH_SOURCE[0]`, i.e. the
script's own actual, currently-running location) is exactly the answer for
*any* real install, regardless of prefix — `cmake --install` places this
same script alongside the rest of the resource tree, so wherever it ends up
running from **is** the correct stable location. The one exception is
running straight from an *uninstalled* dev/build checkout, detected by the
presence of `CMakeLists.txt` (which `install()` never copies — it only
copies `core/logic/state/panels/dialogs/shared/app/src/scripts/assets`,
never the repo root). No new abstraction: one `if [[ -f ... ]]` replacing a
wrong hardcoded assumption, with the dev-checkout fallback behavior kept
identical to before.

**Verified with a real, isolated test** (see Packaging verification below),
not just read — both branches:
- Running from a `DESTDIR`-staged `/usr/share/omafiles` tree: generated
  `Exec=` correctly points at that real location.
- Running from the actual dev checkout: generated `Exec=` still falls back
  to the historical per-user copy, unchanged.

### 3. `APP_VERSION`

**Root cause:** confirmed absent, as the prior audit
(`P2_6_FINAL_1_0_SCOPE_AUDIT.md`) already flagged — no `Q_PROPERTY`,
`Q_INVOKABLE`, or `app.setApplicationVersion()` call existed anywhere.

**Fix — single authoritative source, no second manually-maintained
string:**
- `CMakeLists.txt`: `project(omafiles VERSION 1.0.1 ...)` is the one place
  the version is written by hand. `target_compile_definitions` threads it
  through as `APP_VERSION="${PROJECT_VERSION}"` to both `omafiles-backend`
  and `omafiles-standalone` — the exact same mechanism already used for
  `OMAFILES_SOURCE_DIR` etc., not a new pattern.
- `backend/Env.h`/`.cpp`: added `Q_INVOKABLE QString version() const`,
  returning `QStringLiteral(APP_VERSION)`. Reused the existing `Env`
  singleton (already the "ask the backend a small fact" QML entry point)
  rather than adding a new singleton class + `qmldir` registration for one
  field.
- `main.cpp`: added `app.setApplicationVersion(QStringLiteral(APP_VERSION))`
  next to the existing `setApplicationName` call.
- `README.md` (2 lines) and `CHANGELOG.md` (new entry) updated to `1.0.1`
  for consistency — not a broad rewrite, the two existing static version
  mentions plus one new changelog entry.

**Consistency verified, not assumed:** `strings -e l` (UTF-16LE, matching
Qt's internal `QString` encoding — a plain ASCII `strings` grep found
nothing, which is a real gotcha worth noting) on the actual `DESTDIR`-built
binary and backend `.so` both show the literal string `1.0.1`. The new
selfcheck test below independently confirms it from the QML side.

---

## Packaging verification

**A real `DESTDIR` package install was performed** (not just read/assumed):

```
cmake -S . -B build-pkgtest -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DOMAFILES_BIN_INSTALL_DIR=/usr/bin \
  -DOMAFILES_DATA_INSTALL_DIR=/usr/share \
  -DOMAFILES_QML_INSTALL_DIR=/usr/lib/qt6/qml
ninja -C build-pkgtest
DESTDIR=<fakepkgdir> cmake --install build-pkgtest
```

— i.e. exactly PKGBUILD's `build()`/`package()`, with the same flags.

Verified:
- **Installed paths**: binary at `<fakepkgdir>/usr/bin/omafiles`; backend
  plugin (`.so` + `qmldir` + `.qmltypes`) at
  `<fakepkgdir>/usr/lib/qt6/qml/Omafiles/Backend/`; full QML resource tree
  (`core/logic/state/panels/dialogs/shared/app/src/scripts/assets`) at
  `<fakepkgdir>/usr/share/omafiles/`; icons under
  `<fakepkgdir>/usr/share/icons/hicolor/...`. No `CMakeLists.txt` present in
  the installed tree (confirms the install-integrations.sh fix's own
  detection signal is real, not just theoretically sound).
- **Python integration helpers**: all 3 `dbus-*.py` scripts present,
  executable (`-rwxr-xr-x`, permissions preserved via
  `USE_SOURCE_PERMISSIONS`).
- **Desktop integration**: `install-integrations.sh` run directly against
  the `DESTDIR`-staged tree, with `HOME`/`XDG_DATA_HOME`/`XDG_CONFIG_HOME`/
  `XDG_STATE_HOME` all pointed at an isolated fake home (never josema's
  real one — verified before/after via `diff`, zero difference). Generated
  `.desktop` and all 3 `.service` files' `Exec=` lines correctly point at
  `<fakepkgdir>/usr/share/omafiles/scripts/...` — the real, staged
  location — not the old, wrong per-user fallback. Confirmed the dev-tree
  fallback path is unchanged by running the same script from the actual
  repo checkout (has `CMakeLists.txt`): `Exec=` correctly still points at
  the per-user copy, matching historical behavior exactly.
- **QML version exposure**: confirmed both via the binary/`.so` string
  extraction above and via the new selfcheck test (next section).
- **No writes to `$HOME`/outside `DESTDIR`**: the build and install steps
  themselves wrote nothing outside `<fakepkgdir>`; `xdg-mime default`
  (invoked by `install-integrations.sh`) correctly wrote into the isolated
  `$XDG_DATA_HOME` rather than josema's real `~/.config/mimeapps.list`
  (diffed before/after, identical). Caveat, stated plainly: this
  verification is about the *packaging* process itself. The app's own
  *runtime* self-registration (writing `.desktop`/D-Bus service files under
  the real user's `$HOME`) is expected, correct, per-user behavior by this
  project's own design (no-root, self-registering on first launch) — not
  something this task changes or should change.
- **Correct prefix handling**: verified for `/usr` specifically (matching
  PKGBUILD); the `install-integrations.sh` fix itself is prefix-agnostic
  by construction (derives from `SELF_RES`, not a hardcoded prefix list),
  so this generalizes to "arbitrary `CMAKE_INSTALL_PREFIX`" without needing
  a fix-per-prefix — the one thing not independently re-tested for a THIRD,
  different arbitrary prefix beyond `/usr` and the default `$HOME/.local`.

**A real AUR build was not performed** — `makepkg` requires a real,
downloadable, checksummed source tarball, which doesn't exist yet (no
`v1.0.1` tag). The `DESTDIR` install above is the closest reproducible
equivalent: it exercises the exact same `cmake`/`ninja`/`DESTDIR`
`install()` machinery `makepkg` would invoke via `build()`/`package()`,
just against the local working tree instead of a downloaded+verified
tarball. This is the documented limitation the task anticipated.

---

## Regression coverage added

Two small, targeted tests — not inflating the count for its own sake:

1. `CheckInfrastructure.qml`: "Backend.Env.version() exposes a real
   semver-shaped version" — regex-validates the format rather than
   asserting a hardcoded string (which would just be a second manually-
   maintained version to keep in sync).
2. `CheckFilesystemTrash.qml`: the post-P0 sanity-audit test described
   above.

`install-integrations.sh`'s path fix was deliberately **not** given a new
selfcheck test — the existing selfcheck test for this script explicitly
avoids running it for real (it mutates real `xdg-mime`/D-Bus state,
documented as inappropriate for the selfcheck harness); the real,
isolated `DESTDIR` verification above is a stronger, more direct check
than a unit test could provide, so adding one would duplicate coverage
rather than add protection.

---

## Final verification

- Clean build (fresh `build-final/`, `-DCMAKE_BUILD_TYPE=Debug`): no
  warnings from any changed file.
- Full selfcheck suite: **127/127** (125 pre-existing + 2 new). One
  transient run showed 3 unrelated timeouts/failures in pre-existing Trash
  tests (`Backend.FileOperations.trash`/`restoreByOrigPath` calls that
  don't touch any of this session's changed code paths); **3 immediate
  re-runs came back 127/127 clean each time**. This matches this project's
  own previously-documented, accepted Trash-test flakiness
  (`P2_7_FINAL_FIXES_REPORT.md`: "could not be reproduced deterministically
  ... verified only by volume of clean runs") rather than anything newly
  introduced here — flagged for transparency, not chased further.
- Real `DESTDIR` package install + isolated `install-integrations.sh`
  verification: see above.
- Post-P0 Trash regression verification: the P0 freeze regression test
  (`Trash navigation stays responsive when a mount's stat() is slow`) and
  all pre-existing real-UI-path Trash tests remained green throughout every
  run in this session.
- `git status`/`git diff --stat`: 12 files changed, all directly load-
  bearing for this task (post-P0 fix: `logic/ActionEngine.qml`,
  `logic/DirLister.qml`; P1 packaging: `CMakeLists.txt`, `backend/Env.h`,
  `backend/Env.cpp`, `main.cpp`, `packaging/arch/PKGBUILD`,
  `scripts/install-integrations.sh`, `README.md`, `CHANGELOG.md`, two
  selfcheck files). `docs/audits/PR7_CONFLICT_AUDIT.md` and
  `docs/audits/V1_1_FEATURE_INVENTORY.md` remain untracked, untouched, not
  committed, as before. No new/unrelated files left behind (`build-debug/`,
  `build-pkgtest/`, `build-final/` all removed after use); the temporarily
  swapped `~/.local/lib/qt6/qml/Omafiles/Backend/` production plugin was
  restored to its exact pre-session state (byte-for-byte, `diff`-verified).

---

## Remaining blockers before an actual AUR release

1. **A real `v1.0.1` git tag must be cut** against the current `master`
   (which now includes the P0 trash-freeze hotfix and this packaging work)
   before `PKGBUILD` can be completed — this is a deliberate release
   action, not performed as part of this audit, matching how `v1.0.0`'s tag
   was handled in this same project's history (staged ahead of time, cut
   as a separate, explicit step).
2. Once that tag exists, regenerate the real `sha256sums` against its
   actual tarball (same procedure already used once for `v1.0.0`:
   `gh api repos/Percius04/omafiles/tarball/v1.0.1 | sha256sum`) and replace
   the intentionally-invalid placeholder in `PKGBUILD`.
3. Submit to AUR (`packaging/arch/PKGBUILD`/`.SRCINFO` — no `.SRCINFO`
   exists in-tree yet; generating and committing one, or generating it at
   submission time via `makepkg --printsrcinfo`, is a normal part of the
   AUR submission step itself, not something this audit needed to produce
   ahead of a real tag existing).
4. Not a blocker, but worth deciding deliberately: whether to also update
   `AUR_READINESS`-style documentation once actually submitted (this repo's
   `docs/historical/PHASE40_AUR_PUBLICATION_REPORT.md` was previously
   flagged by a forensic audit as rehearsal documentation that didn't match
   reality at the time — worth avoiding that mistake twice by only writing
   a "published" report once the AUR submission is genuinely live).

No other release blockers were found. The trash-freeze P0 is confirmed
resolved and hardened; packaging infrastructure is now correct for any
install prefix and has a single, consistent version source across
CMake/C++/QML/`PKGBUILD`; the only remaining gap is procedural (cutting the
tag), not a code defect.

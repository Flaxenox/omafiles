# OmaFiles v1.0.1 — Release Report

Tag `v1.0.1` created and pushed. This document records exactly what was
tagged, what the real checksum is, and — critically — what this release
does and does **not** contain, since a real gap was found between it and
the packaging work already done on `v1.1-dev`.

---

## 1. Release source verification

- **Branch**: `master` (not `v1.1-dev`), as required.
- **Commit tagged**: `8ecdb800f12d375dd400fa58f8fc7cc983b96902` —
  `fix(trash): make trash-root discovery async, fixes real UI freeze on
  Sidebar->Trash` — the P0 trash-freeze hotfix
  (`docs/audits/V1_1_P0_TRASH_FREEZE_REPORT.md`).
- `master` matched `origin/master` exactly at the time of tagging (no local
  divergence).
- `v1.1-dev`'s working tree (uncommitted at the time) was **not** included
  in the release — confirmed by direct inspection of the tagged commit's
  content (`git show master:<file>`), not assumed.

**Version-consistency check — result: inconsistent, by design (see §5).**
`master@8ecdb80`'s own `CMakeLists.txt` still declares
`project(omafiles VERSION 1.0.0 ...)`. The `1.0.1` version this release is
tagged and packaged as exists only in the tag name, the `CHANGELOG.md`
entry, and `packaging/arch/PKGBUILD`'s `pkgver` — **not** inside the
tagged source tree's own build-system version declaration. This was found
during verification, surfaced to josema before proceeding, and the decision
(documented in §5) was to tag `master` exactly as-is and treat this as a
scoping choice for `1.0.1`, not a defect to silently work around.

---

## 2. The tag

| Field | Value |
|---|---|
| Name | `v1.0.1` |
| Type | Annotated (`git cat-file -t v1.0.1` → `tag`) |
| Target commit | `8ecdb800f12d375dd400fa58f8fc7cc983b96902` |
| Tag object | `8939cf72702a8b4ff2c095ef640544769a6142d9` |
| Message | `OmaFiles 1.0.1 - Trash freeze hotfix` |
| Pushed | Yes — `origin/v1.0.1` (confirmed via `git ls-remote`; explicitly confirmed with josema first, since pushing wasn't blanket-authorized and was needed specifically to fetch the real GitHub archive for the checksum in §3) |

---

## 3. Source tarball & checksum

**Source URL** (exactly matching `PKGBUILD`'s `source=` line):
`https://github.com/Percius04/omafiles/archive/v1.0.1.tar.gz`

**Real SHA256**: `97978f01887d412ca4b521fbe6001af80a73ba23bc00e05dadbad68b42c9af67`

Verified carefully, not assumed:
- Fetched via **three** distinct methods to cross-check: the GitHub API
  tarball endpoint (`gh api repos/.../tarball/v1.0.1`), the plain archive
  URL with `refs/tags/` (`archive/refs/tags/v1.0.1.tar.gz`), and the exact
  URL `PKGBUILD` actually uses (`archive/v1.0.1.tar.gz`).
- **Found a real gotcha**: the API endpoint produces a **byte-different**
  archive (different top-level directory naming convention:
  `Percius04-omafiles-<short-sha>` vs. `omafiles-1.0.1`), with a different
  SHA256 (`630d446d...`) despite identical decompressed content. The two
  plain-archive URLs (`archive/v1.0.1.tar.gz` and
  `archive/refs/tags/v1.0.1.tar.gz`) are byte-identical
  (`cmp` confirmed) and share the one hash recorded above. Using the API
  endpoint's hash in `PKGBUILD` would have made every real `makepkg`
  download fail checksum verification, despite both artifacts being
  "correct" in a content sense — the task's own explicit warning ("must
  correspond to the actual source= URL") was directly validated by this.
- Manually inspected the tarball's contents: top-level dir `omafiles-1.0.1/`
  (matches `${pkgname}-${pkgver}` that `PKGBUILD`'s `build()`/`package()`
  `cd` into), `CMakeLists.txt` inside confirms `VERSION 1.0.0` (§1's
  finding, independently re-confirmed from the actual downloaded artifact).

---

## 4. `PKGBUILD` changes

Only the checksum was substantively changed by this task (the rest —
`pkgver=1.0.1`, dependency/optdepends lists, `build()`/`package()`, install
paths, `CMake` arguments — was already done and verified in the prior P1
packaging pass, `docs/audits/V1_1_P1_PACKAGING_REPORT.md`, and is
re-confirmed correct below):

```diff
-sha256sums=('0000000000000000000000000000000000000000000000000000000000TODO')
+sha256sums=('97978f01887d412ca4b521fbe6001af80a73ba23bc00e05dadbad68b42c9af67')
```

(plus an updated comment recording where the hash came from and the known
`CMakeLists.txt` version mismatch, so a future reader doesn't have to
re-derive it).

Re-verified against the actual downloaded/built source, not just re-read:
- `pkgver=1.0.1` ✓.
- `source=` resolves to the real `v1.0.1` tag (§3).
- Checksum matches exactly — **`makepkg` itself validated this** (§5; a
  mismatch would have hard-failed the build).
- `depends`/`optdepends`: confirmed present and correct in the built
  package's own `.PKGINFO` (`pacman -Qip`) — `qt6-base`, `qt6-declarative`,
  `qt6-webengine`, `glib2`, `zip`, `unzip`, `python-gobject`; all 8
  `optdepends` entries matching README's table.
- Install paths / `CMake` arguments: confirmed via the actual package file
  listing (`pacman -Qlp`) — binary at `/usr/bin/omafiles`, backend plugin
  at `/usr/lib/qt6/qml/Omafiles/Backend/`, full resource tree at
  `/usr/share/omafiles/`, icons at `/usr/share/icons/hicolor/...`.

---

## 5. Real package build (`makepkg`)

`makepkg` **is available** on this machine and was used for a full, real
build — not simulated:

```
$ makepkg -f
```

in a clean directory containing only `PKGBUILD` (forcing a genuine fresh
download rather than reusing any locally cached source).

**Result: succeeded end to end**, exit 0. Every stage ran for real:
source download (from the real, now-public `v1.0.1` tag) → checksum
verification (would have hard-failed on any mismatch — didn't) →
`cmake`/`ninja` build → `package()` → `.PKGINFO`/`.BUILDINFO`/`.MTREE`
generation → `omafiles-1.0.1-1-x86_64.pkg.tar.zst` produced.

Verified from the real build artifacts:
- **Installed file layout**: full listing above (§4), matches expectations
  exactly.
- **Python D-Bus integrations**: `dbus-app-open.py`, `dbus-filechooser.py`,
  `dbus-filemanager1.py` present under `/usr/share/omafiles/scripts/`,
  executable (`-rwxr-xr-x`, preserved through the whole pipeline).
- **Desktop integration**: `install-integrations.sh` present, executable.
  **Not** re-run live for this specific check (already isolated-tested
  against a `/usr`-staged tree in the prior P1 pass) — this source tree is
  the **old**, pre-P1-fix version of that script (§1's documented gap:
  `master@8ecdb80` predates the path fix), so re-running it here would only
  re-demonstrate the already-known, already-accepted limitation, not new
  information.
- **`/usr` paths**: confirmed via `pacman -Qlp` — everything under `/usr`,
  nothing elsewhere.
- **No `$HOME` modification**: `find ~/.local/share/omafiles
  ~/.config/omafiles ~/.local/state/omafiles -mmin -5` immediately after
  the build returned nothing — confirmed empty, not assumed.
- **No files escaping the package staging root**: `makepkg`'s own fakeroot
  containment plus the `$HOME` check above both confirm this; the one
  warning `makepkg` itself raised — "El paquete contiene referencias a
  $srcdir" for `omafiles-backend_qml_module_dir_map.qrc` — is a pre-existing
  Qt/CMake `qt_add_qml_module` build artifact (present before any change in
  this session, unrelated to this task's edits) that embeds the ephemeral
  build path as a string inside a `.qrc` resource-map file. Not a
  security/correctness issue (nothing reads it at runtime to locate
  anything — the actual `.so`/`qmldir`/`.qmltypes` are unaffected), but
  worth a future, separate, minimal fix (likely a relative-path tweak in
  `qt_add_qml_module`'s output settings) — flagged here, not fixed, as it's
  unrelated to releasing `1.0.1`.

**This is a real, complete verification** — not the closest-reproducible
fallback the task anticipated for the case `makepkg` might be unavailable.

---

## 6. AUR readiness audit

Reviewed the final `PKGBUILD` as an AUR maintainer would, against the real
built package's own metadata:

| Check | Result |
|---|---|
| `pkgname` | `omafiles` — matches the project, lowercase, no illegal characters ✓ |
| `pkgver` | `1.0.1` — matches the tag (`v` prefix correctly stripped) ✓ |
| `pkgrel` | `1` — correct for a first package of this `pkgver` ✓ |
| `source` | Resolves to a real, public, tagged GitHub archive ✓ |
| `sha256sums` | Valid, real, verified by an actual `makepkg` run ✓ |
| Runtime deps | Correct and complete, including the previously-missing `python-gobject` ✓ |
| `optdepends` | Present, matches documented fallback behavior ✓ |
| `makedepends` | Minimal and correct (`cmake`, `ninja` — the unnecessary `qt6-tools` was already dropped) ✓ |
| `package()` | Correct `DESTDIR` staging, verified by a real build ✓ |
| `license` | `MIT` — matches the repo's actual `LICENSE` (`unzip -p` confirms one exists in the tarball) ✓ |
| `arch` | `x86_64` only — matches; no known reason it couldn't build on `aarch64` too, but that's unverified/untested, not a blocker for `x86_64`-only AUR submission |
| Install paths | Standard `/usr` FHS-compliant layout, no per-user assumptions baked into `PKGBUILD` itself ✓ |
| Desktop file / icons | Generated at first-launch by `install-integrations.sh`, not pre-installed by the package — this is a deliberate design choice (self-registering, no root, reversible), not an AUR-policy violation, though it does mean `namcap` may flag "no .desktop file in the package" — worth anticipating in the AUR description, not a defect |
| Integration helpers | Present, executable, correct dependency declared |
| No dev-tree assumptions | The one that mattered (`install-integrations.sh`'s hardcoded path) is **not yet fixed in this specific tagged source** — see §1/§7 |
| `.SRCINFO` | **Missing** — does not exist in-tree; `makepkg --printsrcinfo > .SRCINFO` needs to be run at actual submission time (normal AUR practice, not something to pre-generate speculatively) |

**Verdict: the `PKGBUILD` itself is technically buildable and correct for
what it claims to package.** The one real caveat is not a `PKGBUILD` defect
— it's that what it packages (the `v1.0.1` tag) is deliberately narrower
than the full state of `v1.1-dev`'s packaging-readiness work. See §7.

---

## 7. What this release does and does not contain — read this before publishing

**Contains:** the P0 trash-freeze fix. This was the critical, user-visible
bug (a real UI freeze, reproduced live with a genuine user click and a
gdb-confirmed backtrace) and is the entire reason this hotfix exists. Fully
fixed, regression-tested, verified.

**Does NOT contain** (these live only on `v1.1-dev`, uncommitted at the
time of this report):
- `install-integrations.sh`'s path fix — a `/usr`-installed `v1.0.1`
  package would still hit the pre-existing bug where "open folder"/"show in
  file manager"/the FileChooser portal silently break, because `Exec=`
  paths get generated pointing at `$HOME/.local/share/omafiles` instead of
  the real `/usr/share/omafiles` install.
- `APP_VERSION` exposure to QML — `Backend.Env.version()` does not exist in
  this tagged source; nothing in the running app can report its own
  version at runtime.
- The post-P0 sanity-audit fix in `ActionEngine.qml` (Restore/permanent-
  delete silently no-op-ing if acted on before `TrashState.trashInfo`
  catches up) — a narrow, low-probability race, but real.
- `CMakeLists.txt`'s own version bump (§1).

This was a deliberate scoping decision, confirmed with josema before
tagging: `v1.0.1` is the trash-freeze hotfix only, kept minimal and
low-risk as a patch release; the packaging-quality work moves forward as
part of `v1.1-dev`'s own development instead of being backported here.

---

## 8. `v1.1-dev` is unaffected

- `v1.1-dev` was not moved, merged, retagged, or touched by any of this
  task's git operations.
- Only `PKGBUILD`'s checksum line was edited on `v1.1-dev`'s working tree
  (§4) — **not committed**, consistent with this session's established
  practice of leaving packaging-audit work staged for an explicit commit
  decision. `git status` on `v1.1-dev` after this task shows the same
  files as before, `PKGBUILD` now additionally modified.
- No push of `v1.1-dev` or `master` was performed — only the `v1.0.1` tag
  itself was pushed, and only after explicit confirmation.

---

## Remaining action before AUR submission

**One real blocker, and it's a scope/timing decision, not a technical
one:** decide whether to submit `v1.0.1` to AUR as-is (hotfix-only, with
the known `install-integrations.sh`/`APP_VERSION` gaps documented above),
or fold `v1.1-dev`'s packaging fixes into a subsequent tag first (e.g. a
`v1.0.2`, or wait for a `v1.1.0`) before the first-ever AUR submission —
since first impressions on AUR are hard to walk back, submitting the
already-more-correct packaging might be worth the small delay. Either way,
the remaining **mechanical** steps are: generate `.SRCINFO`
(`makepkg --printsrcinfo > .SRCINFO`), and run the actual `aur` git-repo
push (`ssh aur@aur.archlinux.org`) — neither performed here, per this
task's explicit "do NOT publish to AUR."

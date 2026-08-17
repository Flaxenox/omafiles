# Release Preparation Report — 1.0.0

**Date:** 2026-08-17
**Scope:** release preparation only, on top of the `FINAL_RELEASE_AUDIT.md` verdict (READY TO FREEZE 1.0-DEV). No new audit performed, no features added, no architecture changed, no unrelated production code touched. Not committed, not pushed, not tagged.

---

## Release version

**1.0.0**, bumped from 0.9.0.

Not an arbitrary choice: `packaging/arch/PKGBUILD`'s own pre-existing comment (written during the P0 forensic audit, before this pass) already said *"FIXME: regenerate once a v1.0 tag matching these fixes is cut"* — the project's own packaging metadata already anticipated this exact version target. Combined with the explicit request to add "the missing 1.0 entry" to `CHANGELOG.md`, this pass bumped the version consistently everywhere it's authoritatively declared, rather than only writing a changelog entry with no matching version metadata.

---

## Files changed (this pass)

| File | Change |
| --- | --- |
| `CHANGELOG.md` | New `## [1.0.0] - 2026-08-17` entry (see below) |
| `CMakeLists.txt` | `project(omafiles VERSION 0.9.0 ...)` → `VERSION 1.0.0` |
| `packaging/arch/PKGBUILD` | `pkgver=0.9.0` → `1.0.0`; `zip`/`unzip` added to `depends`; `sha256sums`' `FIXME` comment updated to reflect it's still the old tarball's hash |
| `README.md` | Both `v0.9.0` mentions → `v1.0.0`; selfcheck count `85` (stale, predating even the prior audit's `117` fix) → `124`; `zip`/`unzip`/`p7zip`/`unrar` added to the Optional Dependencies table |

**Also removed** (hygiene, not a "change" to any tracked file): five completely empty, untracked, orphaned directories (`docs/benchmarks/`, `docs/decisions/`, `docs/packaging/`, `docs/release/`, `docs/testing/`) dated 2026-08-15, never populated, invisible to `git status` (git doesn't track empty directories) but visible via `git clean -ndx`. Verified each had zero contents (`find -mindepth 1` returned nothing) before removing with `rmdir`, which only succeeds on genuinely empty directories — no risk of data loss.

**Not touched:** `omafiles-0.9.0.tar.gz` (untracked stray build artifact in the repo root, filename now doubly stale) — flagged, not deleted, since it predates this session and wasn't created by this work; a human should confirm before removing it.

**Carried forward from the prior final-release-audit pass** (already modified before this pass started, unrelated to release-prep work, listed for completeness): `core/AppBindings.qml` (the self-registration path fix) and `src/selfcheck/checks/CheckInfrastructure.qml` (its regression guard), plus the full P0–P2.8 body of work across `core/`, `logic/`, `state/`, `panels/`, `dialogs/`, `app/qml_modules/`, `src/selfcheck/`, and `docs/architecture/`.

---

## Packaging

**`zip` and `unzip` added to `packaging/arch/PKGBUILD`'s `depends`.** Verified against actual code before changing anything, not added for convenience: `logic/ActionEngine.qml`'s `compressSelected()` hardcodes `zip -r -q` with no alternative format — every Compress action needs `zip`. `extractHere()` needs `unzip` specifically for the `.zip` branch, which is the same format Compress produces — meaning a complete, ordinary "compress then later extract your own file" workflow needs `unzip` too. Neither has a fallback (confirmed by reading the actual `runAction`/`actionProc` failure path: no `zip`/`unzip` on `$PATH` means a shell command-not-found, reported as a generic failure notification, not a graceful degradation) — unlike `p7zip`/`unrar`, which are only needed for the optional `.7z`/`.rar` extraction branches and were deliberately left out of `depends`, staying in the README's Optional Dependencies table instead.

**`install-integrations.sh`'s XDG assumption reviewed, not changed.** The script hardcodes `${XDG_DATA_HOME:-$HOME/.local/share}/omafiles` as its resource directory — which is *correct* for the manual `~/.local` install method the README documents and that 100% of current real installs use (no AUR package has been published yet), and would only be *wrong* for a true `/usr`-prefix system-package install. Classified as: **AUR-specific packaging issue, harmless until AUR packaging actually happens** — not a 1.0 blocker, since the 1.0 release as documented and shipped today doesn't depend on it being correct for that case. Not fixed, per the explicit "only if genuinely required" instruction; flagged for whoever prepares the actual AUR submission.

**`sha256sums` intentionally left as a placeholder.** It's still the 0.9.0 tarball's hash — there is no `v1.0.0` tag yet to hash (tagging is explicitly out of this task's scope), so a "real" value can't be computed. The `FIXME` comment was updated to say so explicitly rather than leaving a silently-wrong-looking value with a comment that no longer quite matched (`pkgver` now already says `1.0.0`, so the old comment's "once a v1.0 tag... is cut" read as if it hadn't happened yet, which could be misread as still-pending version bump rather than still-pending tag).

---

## Changelog

**Confirmed added:** `## [1.0.0] - 2026-08-17` in `CHANGELOG.md`, above the existing `## [0.9.0] - 2026-08-15` entry (which was left untouched — a correct historical record, not something to edit). Organized by category, matching the categories requested: filesystem operations & concurrency safety, archive handling, custom keybindings, architectural cleanup, bug fixes, regression coverage, and packaging. Built strictly from what this session's own audit trail (`docs/audits/P0*` through `P2_7*`, plus the `FINAL_RELEASE_AUDIT.md`) actually documents as completed and verified — no invented features, no claims beyond what those reports substantiate. The 85→124 selfcheck growth figure is taken directly from the existing 0.9.0 changelog entry's own "85/85" claim, not asserted independently.

---

## Version consistency

Every authoritative version source checked:

| Source | Before | After | Action |
| --- | --- | --- | --- |
| `CMakeLists.txt` `project(... VERSION ...)` | 0.9.0 | **1.0.0** | Updated |
| `packaging/arch/PKGBUILD` `pkgver` | 0.9.0 | **1.0.0** | Updated |
| `README.md` (intro line + Status section) | v0.9.0 (×2) | **v1.0.0** (×2) | Updated |
| `CHANGELOG.md` | no 1.0 entry | **`[1.0.0]` entry added** | Updated |

**Explicitly identified and left alone** (verified as a different concept or a correct historical record, not blindly replaced):

- `CMakeLists.txt:28`, `qt_add_qml_module(... VERSION 1.0 ...)` — the `Omafiles.Backend` **QML import module version** (`import Omafiles.Backend 1.0`), a completely separate versioning axis from the app release version. QML module versions are conventionally kept low/stable regardless of app version; changing it would be a real (if minor) API-surface change to every QML file that imports the backend, entirely out of scope for a version-string release-prep pass.
- `docs/architecture/DEPENDENCY_GRAPH.md`'s "95/95 as of this writing" — a timestamped record of one specific past verification event.
- `CMakeLists.txt:154`'s "`v0.9.0-rc1`" comment, `bench/README.md`'s "`v0.9.0-rc1-pre2`" baseline label, and every "0.9.0" mention inside `docs/historical/` and `docs/audits/` — all correct, dated historical references. Rewriting history to say "1.0.0" where the event actually happened under a 0.9.0 label would make the record less accurate, not more.
- `docs/architecture/ARCHITECTURE.md`'s "1186 lines" `ActionEngine.qml` note — unrelated to version numbers at all; not touched this pass either (already assessed as not misleading in the prior audit).

---

## docs/audits

**Included.** Verified directly with `git archive HEAD --format=tar | tar -t`, the actual mechanism GitHub uses to build release tarballs respecting `.gitattributes export-ignore` — `docs/audits/` is **not** excluded (the exclude list is `AGENT_BOOTSTRAP.md`, `CLAUDE.md`, `.claude/`, `bench/`, `scratch/`, checked directly, not assumed). Every prior-session audit doc already committed (`SECURITY_AUDIT.md`, `MONOLITH_AUDIT.md`, `FULL_BUG_MATRIX.md`, etc.) already ships in release tarballs under this exact mechanism today. This is a mechanically-confirmed, multi-release-old precedent, not a guess — so the new P2.x/final-audit/release-prep documents follow the same fate by leaving `.gitattributes` untouched, consistent with "if the existing project convention is that audit reports belong in the repository, leave them alone."

---

## Validation

- **Build:** clean, fresh build directory, default flags — 55/55 targets, 0 errors, 0 warnings. Confirmed the version bump doesn't break CMake configuration (`project(omafiles VERSION 1.0.0 ...)` configures and builds identically to before).
- **Selfcheck:** **124/124**, confirmed on 5 consecutive runs after the release-prep changes. Unchanged from the prior audit's count — none of this pass's changes (version strings, `CHANGELOG.md`, `PKGBUILD` metadata, empty-directory removal) touch any code path a selfcheck exercises, so an unchanged count is the expected, correct result, not an oversight.
- **Packaging:** re-verified end to end since `PKGBUILD` changed — a fresh production-path build (`OMAFILES_BIN_INSTALL_DIR=/usr/bin` etc., matching the now-updated `PKGBUILD` exactly), `DESTDIR` install to an isolated fakeroot, and the **staged binary itself launched from that fakeroot** and run through the full selfcheck suite: 124/124. `packaging/arch/PKGBUILD` itself re-checked with `bash -n` (valid syntax).
- **Diff review:** full `git status`/`git diff` re-inspected after all release-prep changes — every change traced to an intentional, explained edit; no accidental modifications found.

---

## Final release tree

### INTENDED FOR 1.0-DEV

**Production source:** `README.md`, `CMakeLists.txt`, `app/qml_modules/qs/Ui/CursorSurface.qml`, `core/AppBindings.qml`, `core/CommandFacade.qml`, `core/ControllerRegistry.qml`, `core/DialogLayer.qml`, `core/OmafilesContent.qml`, `dialogs/ShortcutsHelp.qml`, `logic/ActionEngine.qml`, `logic/ArchiveBrowser.qml`, `logic/KeyboardShortcuts.qml`, `logic/KeybindingResolver.qml`, `logic/NavigationController.qml`, `logic/TabOps.qml`, `panels/BackgroundListDelegate.qml`, `panels/FileListRow.qml`, `state/ArchiveState.qml`, `state/KeyboardDefaults.qml`, `state/Paths.qml`, `state/qmldir`.

**Tests:** `src/selfcheck/SelfCheckRegistry.qml`, `src/selfcheck/SelfCheckRunner.qml`, `src/selfcheck/checks/CheckActions.qml`, `src/selfcheck/checks/CheckInfrastructure.qml`, `src/selfcheck/checks/CheckIntegration.qml`, `src/selfcheck/checks/CheckKeybindings.qml`, `src/selfcheck/checks/CheckPanels.qml`, `src/selfcheck/checks/CheckPreview.qml`.

**Documentation:** `CHANGELOG.md`, `docs/architecture/ARCHITECTURE.md`, `docs/architecture/DEPENDENCY_GRAPH.md`, and (per the confirmed-included `docs/audits/` policy) `docs/audits/P2_3_ARCHIVE_EXTRACTION_REPORT.md`, `P2_4_ALTERNATING_ROWS_REPORT.md`, `P2_5_CUSTOM_KEYBINDINGS_AUDIT.md`, `P2_5_CUSTOM_KEYBINDINGS_IMPLEMENTATION_REPORT.md`, `P2_6_FINAL_1_0_SCOPE_AUDIT.md`, `P2_7_FINAL_FIXES_REPORT.md`, `FINAL_RELEASE_AUDIT.md`, and this document.

**Packaging:** `packaging/arch/PKGBUILD`.

### REMAINING OUTSIDE 1.0-DEV (not part of this tree's changes)

- `omafiles-0.9.0.tar.gz` — untracked stray artifact; recommend manual removal or a `.gitignore` entry before commit, but not touched here.
- A `git tag v1.0.0` and the corresponding GitHub release / tarball — explicitly the next, separate step.
- `PKGBUILD`'s real `sha256sums` value — can only be computed once the `v1.0.0` tag exists.
- An AUR submission — separately gated on the `install-integrations.sh` XDG fix, which itself is gated on someone actually doing that packaging work.
- The empty `docs/benchmarks/decisions/packaging/release/testing/` scaffolding directories — removed as hygiene, were never tracked, so there's nothing further to do about them.

---

## Final answers (as requested)

1. **Exact version:** 1.0.0.
2. **Exact files changed this pass:** `CHANGELOG.md`, `CMakeLists.txt`, `packaging/arch/PKGBUILD`, `README.md` (plus removal of 5 empty untracked directories — no tracked-file impact).
3. **Exact release dependencies (Arch, `depends`):** `qt6-base`, `qt6-declarative`, `qt6-5compat`, `qt6-webengine`, `glib2`, `zip`, `unzip` (new this pass: `zip`, `unzip`).
4. **`docs/audits/` included:** yes — confirmed via `git archive`, matches established multi-release precedent, `.gitattributes` left unchanged.
5. **Final selfcheck result:** 124/124, 5/5 consecutive clean runs.
6. **Build result:** clean, 0 errors, 0 warnings, fresh build directory.
7. **Packaging result:** clean — production-path `DESTDIR` build re-verified after the `PKGBUILD` change, staged binary launched from its own fakeroot, 124/124.
8. **Still requiring a decision before commit:** whether to delete or gitignore `omafiles-0.9.0.tar.gz` (flagged, not acted on); nothing else outstanding.
9. **Ready for the separate commit → push → PR → master operation: yes.**

Not committed. Not pushed. Not tagged. Not merged.

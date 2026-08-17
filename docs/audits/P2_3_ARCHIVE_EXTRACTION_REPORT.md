# P2.3 — Archive Browsing Extraction Report

**Date:** 2026-08-17
**Scope:** extract archive browsing (list/enter/open inside `.zip`/`.7z`/`.rar`/tar without extracting) out of `logic/ActionEngine.qml`, per the extraction candidate identified in `docs/audits/P2_1_ACTIONENGINE_SHARED_AUDIT.md` §6. Only this extraction — nothing else was extracted, split, or opportunistically cleaned up.

## Result

**SUCCESSFUL EXTRACTION.**

`logic/ArchiveBrowser.qml` now owns archive browsing end to end. `ActionEngine.qml` has zero remaining archive-browsing code and zero reference to `ArchiveBrowser`. Every real caller (`NavigationController`, `TabOps`, `CommandFacade`) was updated to the new component. Behavior was verified unchanged both by an updated/expanded selfcheck suite (105/105, repeated 10× clean) and by live on-screen interaction (enter → descend → up → up-and-exit, through the actual running app, actual keyboard/mouse input, actual zip file).

---

## 1. The production path, traced before touching anything

**Detection:** `ActionEngine.isArchive(entry)` (pure predicate over `Utils.extOf` + `FileTypeConfig.tarExt`) and `ActionEngine.isIso(entry)` (separate, unrelated — ISO mounting).

**Entry:** `NavigationController.enter(entry)` — on a non-archive-mode double-click/Enter on a file, if `actionEngine.isArchive(entry)` it called `actionEngine.enterArchive(realPath)`. `enterArchive()` cleared selection, set `ArchiveState.{inArchive:true, archivePath, archiveSubPath:""}`, and called `refreshArchiveListing()`.

**Listing:** `refreshArchiveListing()` reset scroll (`list.contentY = list.originY`) and launched `Backend.ProcessRunner` `archiveListProc` against `scripts/runtime/list-archive.sh <archivePath> <archiveSubPath>` — a bash script that shells out to `unzip -Z1`/`7z l`/`unrar lb`/`tar tf` depending on extension and prints one depth-level, NUL-delimited (`name\0isDir\0`)*. `archiveListProc.onFinished` parsed that into `NavState.entries`, called `list.positionViewAtBeginning()`, and reselected row 0.

**Navigating inside the archive:** `NavigationController.enter(entry)`, when `ArchiveState.inArchive` was already true, branched *inline* (not by calling a named function): a folder row mutated `ArchiveState.archiveSubPath` directly and called `actionEngine.refreshArchiveListing()`; a file row called `actionEngine.openFileInArchive(entry)`.

**Opening a file inside the archive:** `openFileInArchive(entry)` extracted *only that member* to a SHA-1-keyed cache path under `~/.cache/omafiles/archive-open/` via a shell one-liner (`unzip -p`/`7z x -so`/`unrar p`/`tar xf -O`, redirected with `rm -rf -- outDir && mkdir -p -- outDir && ...` — the P0-3 symlink-safety fix from the forensic audit), then on success called `navController.openWithDefault(outPath)` from `archiveOpenProc.onFinished`.

**Leaving the archive:** two different real paths, doing two different things —
- `NavigationController.goUp()`, inline: if at the archive root, called `actionEngine.exitArchive()` (resets `ArchiveState`, then explicitly calls `navController.refresh()` to re-list the real directory the archive lives in, since `NavState.currentPath` never changes while browsing an archive); otherwise ascended one path segment and called `refreshArchiveListing()`.
- `NavigationController._goToPath(path)`, inline: **any** real navigation (bookmark, back/forward, tab switch, editing the path by hand) reset the three `ArchiveState` properties directly, **without** calling `refresh()` — because `_goToPath()` was already about to list somewhere else itself, so an intermediate re-list of the archive's parent would have been pure waste.

**Errors:** `list-archive.sh` has no real error-signaling path — it always exits 0. An unsupported/corrupt archive silently produces an empty listing (verified by inspection, see §8). `openFileInArchive`'s `archiveOpenProc.onFinished` did check `result.exitCode` and called `Backend.Notifier.notify(...)` on failure.

**State involved:** `state/ArchiveState.qml` (`inArchive`, `archivePath`, `archiveSubPath`) — already the single source of truth; `state/NavState.qml` (`entries`, the archive listing masquerading as a directory listing); `state/SelectionState.qml` (`selectOnly`).

**Callers beyond `NavigationController`, found by tracing, not assumed:**
- `logic/TabOps.qml`: `saveActiveTab()` read `ArchiveState.*` into a per-tab snapshot (read-only, not part of the extraction); `_restoreTabArchive(tab)` wrote `ArchiveState.*` directly and called `actionEngine.refreshArchiveListing()` on tab switch/close — the *only* thing `TabOps` used `ActionEngine` for.
- `core/CommandFacade.qml`: `actionEngine.isArchive(entry)` (palette + context menu gating for "Extract here"), `ArchiveState.inArchive` (archive-mode command filtering, path-segments/breadcrumb rendering for the fake archive "path").
- `logic/Persistence.qml`, `core/OmafilesContent.qml`: `ArchiveState.inArchive` read-only guard on `startDirWatch` (don't watch a real path while browsing a fake one).
- `logic/PropertiesLoader.qml`, `logic/SearchOps.qml`: `ArchiveState.inArchive` read-only guard, feature disabled while in archive mode.

\* `scripts/runtime/list-archive.sh` was **not modified** — see §8 for a pre-existing, unrelated bug found (not fixed) while writing the empty-archive regression test.

---

## 2. Extraction boundary — re-verified, not assumed

The P2.1 audit's hypothesis (archive browsing never touches `runAction`/`pushUndo`/the native-batch machinery) was re-checked directly against the current file before moving anything: confirmed true. It is also the only block in `ActionEngine.qml` with its own two `Backend.ProcessRunner`s and its own `state/` singleton (`ArchiveState`) not shared with any mutation path.

What the trace in §1 added to the P2.1 hypothesis: the boundary in the *pre-extraction* tree was not actually clean — `NavigationController.qml` (subdir descend/ascend, silent exit) and `TabOps.qml` (tab-switch restore) both reached *around* `ActionEngine` to mutate `ArchiveState` directly with three slightly different inline recipes, rather than going through named functions. A mechanical "move these 6 functions verbatim" extraction would have left that leakage in place — not a real boundary, just a relocated one. See §3 for how this was closed.

---

## 3. The new component

**Name:** `logic/ArchiveBrowser.qml` (matches the name used throughout the P2.1 audit's own proposal and the task's own dependency-direction example).

**Public API** (9 functions, all on the archive-browsing domain only):

| Function | Replaces | Notes |
|---|---|---|
| `enter(path)` | `enterArchive(path)` | Fresh entry from a real archive file, always at archive root. |
| `enterSubdir(name)` | inline in `NavigationController.enter()` | **New** — centralizes the descend-one-level write to `archiveSubPath` that used to be inline in the caller. |
| `openFile(entry)` | `openFileInArchive(entry)` | Byte-for-byte identical body, including the P0-3 symlink-safety comment and logic. |
| `up()` | inline in `NavigationController.goUp()` | **New** — ascend one level, or call `exit()` if already at the archive root. |
| `exit()` | `exitArchive()` | Explicit exit; still calls `navController.refresh()`. |
| `forceExit()` | inline in `NavigationController._goToPath()` | **New** — silent reset, no refresh (the caller is about to list somewhere else itself). |
| `refresh()` | `refreshArchiveListing()` | Re-list current position; scroll reset + the two `ProcessRunner`s. |
| `restore(archivePath, archiveSubPath)` | inline in `TabOps._restoreTabArchive()` | **New** — tab-switch restoration, one call instead of 3 property writes + a bare `refreshArchiveListing()`. |
| `isArchive(entry)` | `isArchive(entry)` | Byte-for-byte identical body. |

**Deliberately not moved:** `isIso(entry)`. ISO mounting (`logic/MountActions.qml`, `udisksctl` loop-mount) is a different mechanism entirely — it only ever sat next to `isArchive()` because both answer "can this file be entered like a folder," not because they share any implementation. Moving it would have been scope creep beyond "the archive-browsing responsibility."

**Inputs:** `list` (the active `ListView`, for `contentY`/`originY`/`positionViewAtBeginning()` — exactly the same two call sites `ActionEngine` used, nothing added), `navController` (for `openWithDefault()` and `refresh()`).

**Outputs:** none returned directly — like the code it replaced, it communicates via `ArchiveState`/`NavState`/`SelectionState` writes, which is the established `state/`-as-source-of-truth pattern this codebase already uses everywhere else (`ActionEngine` communicates the same way).

**State ownership:** `ArchiveState` stays the single source of truth, unmodified, still declared in `state/`. `ArchiveBrowser` is now its sole *writer* for real archive-browsing operations. `TabOps.saveActiveTab()` and `CommandFacade`'s several `ArchiveState.inArchive` checks still *read* it directly — reading a `state/` singleton is not the coupling this extraction targets (every other controller in this codebase reads `state/` directly too); *writing* it from three different files with three different inline recipes was, and that's what got centralized.

---

## 4. Real callers updated (production code)

| File | Change |
|---|---|
| `logic/NavigationController.qml` | New `property Item archiveBrowser: null`. `refresh()`, `_goToPath()`, `enter()`, `goUp()` now call `archiveBrowser.*` instead of inline `ArchiveState` mutation or `actionEngine.*`. `actionEngine` property kept (still needed for `isIso()`). |
| `logic/TabOps.qml` | `property Item actionEngine: null` → `property Item archiveBrowser: null` (its *only* use of `actionEngine` was the archive-restore call — `TabOps` now has zero remaining references to `ActionEngine`). `_restoreTabArchive()` is now a one-line call to `archiveBrowser.restore(...)`. |
| `core/CommandFacade.qml` | New `property var archiveBrowser`. Both `actionEngine.isArchive(...)` call sites → `archiveBrowser.isArchive(...)`. `actionEngine.isIso(...)` unchanged. |
| `core/ControllerRegistry.qml` | New `ArchiveBrowser { id: archiveBrowser; list: registry.list; navController: navController }` block + `readonly property alias archiveBrowser`. `TabOps`'s binding switched from `actionEngine: actionEngine` to `archiveBrowser: archiveBrowser`. `NavigationController`'s block gained `archiveBrowser: archiveBrowser`. `ActionEngine`'s block lost its now-dead `list: registry.list` binding. |
| `core/OmafilesContent.qml` | New `readonly property alias archiveBrowser: registry.archiveBrowser` (for selfcheck/dialog reach, mirroring `actionEngine`/`navController`) + wired into the `CommandFacade` instantiation. |
| `logic/ActionEngine.qml` | Archive block removed (see §5). Dead `property Item list: null` removed (its only two uses were both inside the removed code). |

---

## 5. What was removed from `ActionEngine.qml`

`enterArchive()`, `exitArchive()`, `refreshArchiveListing()`, `openFileInArchive()`, `isArchive()`, the `archiveListProc`/`archiveOpenProc` `Backend.ProcessRunner`s, and the now-dead `property Item list: null` (verified zero remaining uses by grep before removing). Replaced with a single explanatory comment pointing at `logic/ArchiveBrowser.qml`.

**Kept, deliberately:** `isIso()` (different domain, see §3); the 12 `if (ArchiveState.inArchive) return` guards scattered through `requestDelete`/`copySelected`/`cutSelected`/`startRename`/etc. — these *read* `ArchiveState.inArchive` to refuse running while browsing an archive, they don't own it, and refusing to mutate during archive browsing is `ActionEngine`'s own concern, not archive browsing's.

`ActionEngine.qml`: 1258 → 1186 lines (net of this extraction plus the small explanatory comment left behind).

**Stale comments corrected as part of this same pass** (all in the archive/file-type domain this extraction touches directly, found by grep while verifying no dissolved-file references survived): `state/ArchiveState.qml`'s header (previously said it "completes the archive browsing block of `logic/ActionEngine.qml`" — corrected 2026-08-17 same day, now says it's owned by `ArchiveBrowser`), `src/selfcheck/checks/CheckPreview.qml`'s cache-key comment (said "the extraction cache (ArchiveActions)" — a dissolved Phase-43 filename that had survived the P2.1 comment sweep because it lacked the `.qml` suffix my earlier grep matched on).

---

## 6. Tests

**Existing selfchecks:** 99 → 105 (99 pre-existing + 6 new). All 99 pre-existing checks pass unmodified in behavior; two of them **had to be updated for the new call surface** (they called `ActionEngine`'s archive functions directly, which no longer exist):
- `"Archive browsing: enter zip, list, navigate subfolder, exit (P0-1 regression)"` (`CheckActions.qml`) — updated to call `c.archiveBrowser.*`, and improved to use the new `enterSubdir()` (the real UI path a folder click takes) instead of poking `ArchiveState.archiveSubPath` by hand, which the test previously had to do because no such function existed yet.
- `"openFileInArchive: pre-planted symlink at the cache path is not followed (P0-3 regression)"` (`CheckIntegration.qml`) — same call-site update, symlink-safety assertion itself untouched.

**New archive tests** (all against the real composition root, `sc._content`, never an isolated `Qt.createComponent()` fragment):

| Test | Covers |
|---|---|
| Nested subdirs, `up()` ascends one level at a time, `exit()` only at true root | Basic + "nested directories" edge case; the new `up()`/`enterSubdir()` functions specifically |
| Many entries (40), spaces, Unicode filenames list correctly | "many entries," "filenames with spaces," "Unicode filenames" edge cases |
| Empty archive doesn't crash or hang, `exit()` still clean | "empty archive" edge case — see §8 for the pre-existing quirk this documents rather than asserts as correct |
| Invalid/corrupt archive lists empty without crashing, `exit()` still clean | Error handling edge case |
| Real `navigateTo()` while `inArchive` force-exits silently | The new `forceExit()` function specifically (a real bookmark/back-forward/tab-switch/edit-path click all funnel through this same path) |
| Tab switch saves and restores archive position | The new `restore()` function specifically — **zero prior coverage existed for `TabOps._restoreTabArchive()` at all**, confirmed by grep before writing it |

**Repeated runs:** 10× consecutive full-suite runs, 105/105 clean every time, zero flakes.

**Live, on-screen verification** (real app launched, real `ydotool` mouse/keyboard input, real zip file on disk): double-click a `.zip` → entered correctly (breadcrumb + listing); selected `subdir/` → Enter → descended correctly (breadcrumb + `inner.txt` listing); Backspace → ascended one level (back at archive root, still inside the zip — confirmed `up()` does not over-exit); Backspace again → exited cleanly to the real directory. Zero QML warnings in the app's log across the whole sequence. Ctrl+L re-verified working (address field still solid, unaffected — confirms this pass didn't regress the P2.1/P2.2 work). Marquee-select and delete-confirmation were **not** re-driven live in this pass: neither was touched by this extraction, both already have selfcheck coverage against the real objects they changed in the prior P2.1/P2.2 pass, and both are part of the 105/105 passing suite — re-clicking through them live would have re-verified unchanged code, not this change.

**ASan:** not applicable — **zero C++/backend files were touched** in this extraction. `ArchiveBrowser.qml` calls the exact same `Backend.ProcessRunner`/`Backend.ThumbnailProvider`/`Backend.Notifier` APIs `ActionEngine.qml` already called, unchanged. ASan concurrency status is unaffected and unchanged from the last verified-clean run (P0 concurrency pass).

**Clean build:** `ninja: no work to do` (no C++ changed; this is a pure-QML move, picked up live from the source tree as this whole session's dev workflow has established).

**DESTDIR install:** verified — `cmake --install` with a scratch `DESTDIR` places `logic/ArchiveBrowser.qml` correctly under `.../omafiles/logic/`, via the existing plain `install(DIRECTORY core logic state panels dialogs shared app src ...)` rule (no `CMakeLists.txt` change needed — it installs whole directories, not an enumerated file list).

---

## 7. Behaviour comparison

Every scenario in the task's "preserve behaviour exactly" list was checked, either by an updated/new selfcheck or live interaction: normal directory navigation (unaffected, untouched code path), archive detection (`isArchive` byte-identical), archive browsing enter/list (selfcheck + live), nested archive paths (selfcheck: 2-level nesting, up-chain; live: 1-level), leaving archives both ways — explicit `up()`-at-root and silent `forceExit()` on real navigation (both have dedicated new selfchecks), back navigation within an archive (`up()` ascend-without-exit selfcheck), selection (unaffected — `SelectionState.selectOnly` calls unchanged), copy/extract behaviour (`extractHere`/`runPendingExtract`/`compressSelected` untouched, still in `ActionEngine.qml`, still gated by the same `ArchiveState.inArchive` guards, not touched by this extraction and not tested further here since nothing about them changed), errors (invalid-archive selfcheck; `openFile`'s `Notifier.notify` on non-zero exit unchanged), empty archives (new selfcheck, see §8 for the honest caveat), many entries (new selfcheck, 40+ files), filenames with spaces and Unicode (new selfcheck), unusual archive names (not specifically tested — no evidence any code path treats the *archive's own* filename specially beyond `Utils.extOf`, which was already covered by the existing multi-format test suite in `CheckFilesystemTrash.qml`/elsewhere).

**No UX change.** No new feature. No redesigned archive support. The only user-visible thing that changed is nothing — this is a pure ownership move, confirmed by diffing the moved function bodies against their originals (identical except the 3 new centralizing functions, which replace inline code that was already there, just relocated and named).

---

## 8. A pre-existing bug found, not fixed (in scope discipline, not an oversight)

While building the "empty archive" regression test, `scripts/runtime/list-archive.sh` was found to mishandle two distinct empty-archive cases, **neither related to this extraction and neither touched by it**:
- A genuinely empty `.zip`: `unzip -Z1` prints the diagnostic `Empty zipfile.` to **stdout** (not stderr), which the script's `2>/dev/null` doesn't catch — it gets parsed as a fake filename.
- A genuinely empty `.tar`: `tar tf` prints the archive's own `./` root entry, which the script's parser turns into a bogus single `"."` directory row instead of zero entries.

Both were verified directly against the unmodified script (`git blame`/diff confirms this session touched neither `list-archive.sh` nor its git history). Fixing either is outside this task's explicit "preserve behaviour exactly... this is strictly an ownership refactor" scope — the empty-archive selfcheck asserts the *extraction* didn't change this behavior (`entries.length <= 1`, documented in-test as a known quirk), not that the behavior is correct. Flagged here for a future, separate, dedicated fix.

---

## 9. Phase 43 comparison

**What caused the Phase 43 regression** (per `ARCHITECTURE.md`'s own section, re-verified this session): 11 previously-separate files were merged into `ActionEngine.qml` in one unreviewed commit with no phase report, dropping the `property Item list: null` convention every sibling controller followed — archive browsing threw a `ReferenceError` on every open, undetected for a full day because zero selfcheck exercised that path.

**Why this extraction avoids every one of those failure modes:**
- **Reviewed, documented, one commit's worth of scope.** This report exists; the P2.1 audit that identified the candidate exists; nothing here is an unreviewed drive-by.
- **The exact prior failure mode is structurally impossible to repeat here**, because it's the same fix applied symmetrically: `ArchiveBrowser` receives `list: registry.list` explicitly in `ControllerRegistry.qml`, the same convention `NavigationController`/`TabOps`/`SearchOps` already use — and this report's own selfcheck update (§6) is *named after* the P0-1 regression specifically to keep testing for it.
- **New selfcheck coverage was added *for this exact code* before any risk of it going untested again** — six new tests plus two updated ones, run 10× repeated, zero flakes, before this report was written.
- **It moves in the opposite direction from Phase 43.** Phase 43 merged 11 heterogeneous files into one. This extracts exactly one homogeneous, independent responsibility out of one file, leaving the genuinely-coupled remainder (delete/clipboard/rename/chmod/drag-drop/compress, all funneling through the shared `runAction`/`pushUndo`/native-batch guard state) untouched and co-located, because splitting *those* would recreate the Phase-43-shaped mistake at a smaller scale.

**Are the new boundaries real, or renamed wrappers?** Real. `ArchiveBrowser` does not call into `ActionEngine` for anything, and `ActionEngine` does not call into `ArchiveBrowser` for anything — the edge between them is gone, not indirected. It does not become a generic `*Ops.qml` (it has exactly one domain, 9 functions, no dispatch table), not a wrapper around `ActionEngine` (zero remaining reference either direction), not a forwarding layer (every function does its own real work — state writes, `ProcessRunner` calls — nothing here just relays to another component), not a duplicate state machine (`ArchiveState` is untouched, still the single owner of the data), and not a second `CommandFacade` (it exposes operations, not a `paletteCommands()`-style action-list builder).

**Dependency count — honest accounting, not spin.** The total edge count did not dramatically shrink: `ArchiveBrowser <-> NavigationController` (2 edges) replaces what was `ActionEngine <-> NavigationController`'s archive-specific portion (the rest of that edge, e.g. `isIso()`, remains). `TabOps -> ArchiveBrowser` (1 edge) *replaces* `TabOps -> ActionEngine` outright — `TabOps` now has **zero** edges to `ActionEngine`, a genuine, measurable coupling reduction, not just a relabeling. `CommandFacade -> ArchiveBrowser` (1 edge, `isArchive`) sits alongside the still-necessary `CommandFacade -> ActionEngine` (for `isIso` and everything else `CommandFacade` calls `ActionEngine` for). What changed more than the edge count is **cohesion**: archive browsing's edges are now isolated in a 177-line file with one domain, instead of interleaved with 1000+ lines of unrelated delete/rename/chmod/clipboard logic in `ActionEngine.qml`. That is the actual goal stated at the top of this task — "simpler, not merely smaller" — and line count alone (1258 → 1186, a 6% reduction) undersells what actually improved.

---

## Remaining `ActionEngine` responsibilities

**Confirmed: nothing else was extracted opportunistically.** `ActionEngine.qml` still owns, unchanged: undo/redo stack (`pushUndo`/`undoLast`/`redoLast`), shell action dispatch (`runAction`/`chainCmds`/`cancelAction`), native batch dispatch (`_runNative`/`_batchNext`/`_finishNative`/the P1-1/P1-2 `_batchCompleted` tracking), delete/trash, clipboard, rename/new-file/new-folder, bulk rename, chmod, symlink creation, drag-and-drop, compress/extract, and `isIso()`. All twelve `ArchiveState.inArchive` guard checks (reads, not writes) remain exactly where they were. No conflict-check deduplication was attempted (the P2.1 audit's "extract-safe but low value" §1–2 note about the 8 near-identical `existingPaths()` blocks was not acted on in this pass — out of scope for "archive extraction only").

## Deferred work — explicit confirmation

- **Alternating row colors:** deferred. `shared/CursorSurface.qml` untouched.
- **Bulk rename:** deferred. Untouched.
- **Error-message overhaul:** deferred. Untouched.
- **`-Wall -Wextra`:** deferred. Untouched.
- **CursorSurface.qml:** untouched, per explicit instruction.
- **`m_cancelled` / undo-redo timing gap:** untouched, per explicit instruction.
- **P0/P1 fixes:** untouched — no `backend/*.cpp` file was touched in this pass.
- **Debian feedback unrelated to archives:** untouched.
- **Broad `shared/` cleanup:** untouched (`shared/` was not touched at all in this pass).
- **Further `ActionEngine` splitting beyond archive browsing:** not done, and per §9's dependency-count section, not recommended without the same kind of explicit review this extraction got.

---

## Files changed

```
 core/CommandFacade.qml                    |   5 +-
 core/ControllerRegistry.qml               |  10 +-
 core/OmafilesContent.qml                  |   2 +
 docs/architecture/ARCHITECTURE.md         |  22 ++-
 docs/architecture/DEPENDENCY_GRAPH.md     |  37 ++++-
 logic/ActionEngine.qml                    |  94 +-----------
 logic/ArchiveBrowser.qml                  | 177 ++++++++++++++++++ (new file)
 logic/NavigationController.qml            |  22 +--
 logic/TabOps.qml                          |   7 +-
 src/selfcheck/checks/CheckActions.qml     | 233 ++++++++++++++++++++++++++++--
 src/selfcheck/checks/CheckIntegration.qml |   6 +-
 src/selfcheck/checks/CheckPreview.qml     |   7 +-
 state/ArchiveState.qml                    |  12 +-
 13 files changed
```

No file outside this list was modified. `omafiles-0.9.0.tar.gz` (untracked, pre-existing, unrelated) was left untouched.

## Verification

```
$ git status --short
 M core/CommandFacade.qml
 M core/ControllerRegistry.qml
 M core/OmafilesContent.qml
 M docs/architecture/ARCHITECTURE.md
 M docs/architecture/DEPENDENCY_GRAPH.md
 M logic/ActionEngine.qml
 M logic/NavigationController.qml
 M logic/TabOps.qml
 M src/selfcheck/checks/CheckActions.qml
 M src/selfcheck/checks/CheckIntegration.qml
 M src/selfcheck/checks/CheckPreview.qml
 M state/ArchiveState.qml
?? logic/ArchiveBrowser.qml
?? omafiles-0.9.0.tar.gz
```

**No commit was made.**

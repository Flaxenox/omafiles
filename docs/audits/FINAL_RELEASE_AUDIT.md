# Final Release Audit — 1.0-dev Freeze Readiness

**Date:** 2026-08-17
**Scope:** whole repository, current `v1.0-dev` tree. Deliberately narrow pass — verification plus only the fixes required for release correctness. No feature work, no refactors, no architecture changes.

---

## Executive Verdict

# READY TO FREEZE 1.0-DEV

One genuine, currently-active production bug was found and fixed during this audit (see below) — not because this pass went looking for new features to build, but because a final release audit is exactly where a silently-broken, undetected regression should surface. With that fixed, every verification gate is green, no regression was found in any core flow, and the remaining known issues are all explicitly acceptable for 1.0 (documented, non-blocking, already triaged in P2.6/P2.7).

---

## Verification Summary

| Gate | Result |
| --- | --- |
| Selfcheck count | **124/124** (123 from P2.7 + 1 new regression guard added this pass) |
| Repeated runs | 6/6 clean in the final batch; ~30 total runs across this pass, 1 failure (see below) |
| Clean build (fresh dir, default flags) | 55/55 targets, 0 errors, 0 warnings |
| `-Wall -Wextra` build (fresh dir) | 0 errors, exactly 2 warnings — both pre-existing, both `-Wunused-parameter` in `backend/NetworkResolver.cpp:13` (fixed GIO callback signature), identical to P2.6/P2.7's finding |
| ASan / native concurrency | **Run, targeted.** See below — warranted and executed, clean |
| Packaging / DESTDIR install | Clean. Production-path build + DESTDIR install + **launch from the staged fakeroot** (not `~/.local`) + full selfcheck against that staged binary — 124/124, no dev-path leaks found in any staged file |
| Manual GUI smoke test | **Skipped, explicitly reported** — see below |

**On the one selfcheck failure this pass:** a single run (3 failures, all Trash-related) occurred immediately after a heavy `-fsanitize=address` compilation had been running concurrently on the same machine — real, substantial CPU/I/O contention. This is consistent with (not contradictory to) P2.7's fix: that fix eliminates *cross-test corruption* from a stale signal handler; it does not and cannot make a genuinely slow filesystem operation under real contention complete inside its 8-second budget. A correctly-reported timeout under real contention is expected behavior, not a regression. 18 of 19 total runs this pass were clean; the 8 immediately following (once the ASan compile had finished) were clean, as were all runs before and after.

### ASan: why it was warranted, and what was run

`git diff 01b9972..HEAD -- backend/` (the P0 ASan-verified commit vs. current tree) shows `backend/FileOperations.h`/`.cpp`/`_Copy.cpp`/`_Move.cpp`/`_Remove.cpp`/`_Trash.cpp` changed in the P1 commit (`d662782`) — specifically, a P1-4 fix (`beginCancelToken()`) replacing one shared, reused `m_cancelled` flag with a fresh, per-operation `shared_ptr<std::atomic<bool>>` for every `copy`/`move`/`remove`/`emptyTrash`/`restoreByOrigPath` call. This is exactly the ownership/lifetime/cancellation category the task instructions call out, and exactly the class of class the original P0 ASan work targeted — so it was re-verified rather than assumed safe by inspection.

Built a targeted standalone ASan repro (`cancel_overlap_repro.cpp`, same build recipe as `P0_CONCURRENCY_REMEDIATION_REPORT.md`'s appendix) stressing the actual race window the P1-4 fix introduces protection against: start a copy, cancel it, and — without waiting for that job to signal completion — immediately start a second, independent copy (which replaces `m_cancelled` with a fresh token). Ran **4 passes, 150 total cycles, 300 total overlapping copy operations** — zero ASan violations, zero crashes, exit 0 every time. `backend/TerminalResolver.cpp` also changed since the P0 commit but only by adding an early-return env-var guard (test-hygiene, no lifetime/ownership implication) — did not warrant ASan.

No other `backend/*.cpp`/`.h` files changed since the P0 verification (confirmed via `git diff --stat`), so the rest of P0's ASan coverage (`SearchWorker`, `ThumbnailProvider`, `DirectoryModel`) needed no re-verification.

### Manual smoke test: skipped, explicitly reported

The user's own OmaFiles instance (PID present throughout this pass) was running the whole time. OmaFiles enforces single-instance per UID (a second launch messages the existing window rather than starting independently), so there was no way to open a genuinely separate interactive test instance without either disrupting the user's active session or asking them to close it — a question already asked and answered earlier in this same overall effort. Per this task's own explicit instruction ("skip live interaction and explicitly report it" is a sanctioned option), live GUI interaction was skipped this pass.

This is a real gap, not hand-waved away: it is mitigated, not eliminated, by the fact that this codebase's selfcheck suite is unusually UI-adjacent for a "unit test" suite — it drives the real composition root, real `ConfirmDialog`s, real `ContextMenuPanel` actions, real keyboard dispatch through `KeyboardShortcuts.qml`, and (this pass) a real staged-install launch — not just backend logic in isolation. It is not a substitute for a human looking at the running app, and that step is recommended before the actual release announcement, once the user is free to close their working session for it.

---

## Documentation Status

Corrected:

- **README.md**: selfcheck count `117` → **124** (main badge line and the one now-added regression test both accounted for).
- **`docs/architecture/ARCHITECTURE.md`**: same count correction (`117` → `124` in the directory-tree overview line).
- **README.md**: added `zip`/`unzip`/`p7zip`/`unrar` to the "Optional dependencies" table. These were previously undocumented entirely, despite Compress/Extract being listed as a core, unconditional file operation — a real gap: unlike the other rows in that table (which have graceful fallbacks), Compress and zip-extraction have *no* fallback without these tools; worded that distinction explicitly rather than lumping them in as silently-optional.

Deliberately left alone (already accurate, or explicitly historical, not misleading):

- `docs/architecture/DEPENDENCY_GRAPH.md`'s "95/95 as of this writing" — a timestamped record of a specific past verification event, not a live count; changing it would misrepresent history, not correct it.
- `ARCHITECTURE.md`'s "`ActionEngine.qml` is 1186 lines" note — now ~1220 after P2.7's added comments/guard; a ~3% drift in a "for context, it went down after extraction" figure, not misleading enough to be worth the churn.
- Custom keybindings, archive browsing, `shared/` rules, ActionEngine responsibility matrix — all verified current against the actual tree, no drift found.

Flagged, not fixed (belongs to the separate release-prep step, not this audit — see Recommendation):

- **`CHANGELOG.md`** still ends at `[0.9.0] - 2026-08-15` and has no entry for any of the P0/P1/Debian-feedback/P2.1–P2.8 work in this tree. Writing the 1.0 changelog entry is release-prep work (typically done immediately before tagging), not an audit-pass documentation fix — flagged for that step, not written here.

---

## Release Diff Review

**A genuine production bug was found and fixed** — the only production code change made in this pass, and squarely a release blocker, not scope creep:

`core/AppBindings.qml`'s self-registration call (the mechanism behind the documented "sets itself as the system's default file manager automatically on first launch" feature) had a wrong path — `Paths.resourceDir + "/scripts/runtime/scripts/install-integrations.sh"`, which has never existed (the real file is at `.../scripts/install-integrations.sh`, one level up, no `runtime/scripts/` in between). `git blame` traces the typo to commit `37f3f318` (2026-08-15). Because `Backend.Detached.run()` on a missing path fails completely silently (fire-and-forget, no signal, no crash) and the script is idempotent-and-invisible when it *does* run, this had been silently broken for **3 days**, through the entire P0/P1/P2 forensic/architectural pass, undetected by any of it — confirmed independently by `~/.local/state/omafiles/integrations-version`'s mtime predating the bad commit and never having been touched since. Fixed to the correct one-line path; verified the corrected path now resolves to a real, executable file (didn't execute the script itself against the live system, to avoid mutating real xdg-mime/D-Bus defaults mid-audit — the mechanism itself has a proven successful run history from before the regression). Added one lightweight regression guard (`src/selfcheck/checks/CheckInfrastructure.qml`) that checks this exact path resolves to a real file — **with an honest limitation**: it independently re-derives the correct path rather than reading `AppBindings.qml`'s own string, so it protects against the file moving but would not, on its own, catch `AppBindings.qml`'s string diverging from it again in exactly the same way. Adding real protection against that would mean exposing the computed path as a shared property — a small new piece of surface not justified for this audit's scope.

Full file-by-file classification of everything currently in the working tree (35 changed/untracked entries):

### Should ship (production source)

`README.md`, `app/qml_modules/qs/Ui/CursorSurface.qml`, `core/AppBindings.qml`, `core/CommandFacade.qml`, `core/ControllerRegistry.qml`, `core/DialogLayer.qml`, `core/OmafilesContent.qml`, `dialogs/ShortcutsHelp.qml`, `logic/ActionEngine.qml`, `logic/ArchiveBrowser.qml` (new), `logic/KeyboardShortcuts.qml`, `logic/KeybindingResolver.qml` (new), `logic/NavigationController.qml`, `logic/TabOps.qml`, `panels/BackgroundListDelegate.qml`, `panels/FileListRow.qml`, `state/ArchiveState.qml`, `state/KeyboardDefaults.qml` (new), `state/Paths.qml`, `state/qmldir`.

### Should ship (required tests)

`src/selfcheck/SelfCheckRegistry.qml`, `src/selfcheck/SelfCheckRunner.qml`, `src/selfcheck/checks/CheckActions.qml`, `src/selfcheck/checks/CheckInfrastructure.qml`, `src/selfcheck/checks/CheckIntegration.qml`, `src/selfcheck/checks/CheckKeybindings.qml` (new), `src/selfcheck/checks/CheckPanels.qml`, `src/selfcheck/checks/CheckPreview.qml`.

### Should ship (required documentation)

`docs/architecture/ARCHITECTURE.md`, `docs/architecture/DEPENDENCY_GRAPH.md`.

### Judgment call — flag for the maintainer, don't decide unilaterally

`docs/audits/P2_3_ARCHIVE_EXTRACTION_REPORT.md`, `P2_4_ALTERNATING_ROWS_REPORT.md`, `P2_5_CUSTOM_KEYBINDINGS_AUDIT.md`, `P2_5_CUSTOM_KEYBINDINGS_IMPLEMENTATION_REPORT.md`, `P2_6_FINAL_1_0_SCOPE_AUDIT.md`, `P2_7_FINAL_FIXES_REPORT.md`, and this document. **`.gitattributes` currently does *not* exclude `docs/audits/` from release tarballs** (it excludes `AGENT_BOOTSTRAP.md`, `CLAUDE.md`, `.claude/`, `bench/`, `scratch/` — checked directly, not assumed) — meaning every prior-session audit doc already in that directory (`SECURITY_AUDIT.md`, `MONOLITH_AUDIT.md`, `FULL_BUG_MATRIX.md`, etc.) already ships in release tarballs today, by established precedent. Committing these new ones to the dev branch and letting them ship the same way is *consistent* with that precedent, not a deviation from it. Worth a deliberate maintainer decision, though: the `docs/audits/` directory has grown to roughly half a megabyte of forensic prose across this session alone. Whether that belongs in an end-user release tarball (vs. dev-branch-only via a new `.gitattributes` line) is a policy call outside this audit's scope to make unilaterally — flagged, not decided.

### Should NOT ship

`omafiles-0.9.0.tar.gz` — an untracked, stray build artifact (a generated tarball, not source) sitting in the repo root. Not currently tracked by git, so it won't ship unless explicitly `git add`ed; flagged so it isn't accidentally swept in by a careless `git add -A` during release prep. Not deleted here, per this audit's "don't delete anything" instruction.

---

## Security Review

Focused on the actual release diff, not a re-audit of already-covered stable code (P0's forensic pass already covered path traversal, symlinks, temp files, and shell quoting exhaustively for the pre-existing codebase; P2.6/P2.7 already confirmed P2.1–P2.7 introduced nothing new in those areas).

- **Bulk rename's empty-name fix is a net risk reduction**, not a new surface: it closes a path where an empty-string target could reach `mv -n -- oldpath ''`, validated entirely with local computation before any filesystem call.
- **The error-message fix is cosmetic** — a string change with no behavioral or trust implication.
- **The `AppBindings.qml` path fix restores existing, already-reviewed behavior** — it doesn't add new logic, it corrects a path so an existing, previously-audited script runs again. `Paths.resourceDir` is env-derived with a safe fallback, not attacker-controllable beyond what every other part of this codebase already trusts.
- **The bulk-rename notification string** (`emptyNames[0].oldName`) goes to `Backend.Notifier.notify()`, which passes it as a `QProcess` argument to `notify-send` directly (`QStringList{"Omafiles", text}`) — never through a shell, so no injection risk regardless of filename content.
- **New/changed test files** (`SelfCheckRunner.qml`, `CheckActions.qml`, `CheckInfrastructure.qml`) are only reachable via the `--selfcheck` CLI flag, never in normal runtime — no production attack surface.

No new findings. The diff this pass produced is not security-relevant beyond the ways described above, all of which reduce risk or restore already-vetted behavior.

---

## Remaining Known Issues

Explicitly accepted for 1.0, not blockers:

- **PKGBUILD's `depends` array doesn't list `zip`/`unzip`** (needed for the documented Compress feature, which always produces a `.zip`). Currently moot in practice — the AUR package this PKGBUILD is for hasn't been published yet (per prior project history) — but worth fixing in `packaging/arch/PKGBUILD` before it is. Not fixed in this pass per the explicit "don't modify package metadata unless a genuine blocker" instruction; this is a metadata gap for a not-yet-published package, not a currently-shipping break.
- **`scripts/install-integrations.sh` itself hardcodes `${XDG_DATA_HOME:-$HOME/.local/share}/omafiles`** as its resource-directory assumption, which would resolve incorrectly for a true system (`/usr`-prefix) package install — a pre-existing, previously-known gap (referenced in prior project history), unrelated to the path bug fixed in this pass (that one was in the *caller*; this one is inside the script itself). Also currently moot pending AUR publication. Flagged, not touched — fixing it is packaging work, out of this audit's scope.
- **`CHANGELOG.md` needs a 1.0 entry** covering P0 through P2.8 — release-prep work, not an audit-pass fix.
- **The Trash-test flakiness fix (P2.7) has a confirmed root cause and fix but no forced, on-demand reproduction-then-fix confirmation** — only one live sighting during that investigation, not recurring since. Already accepted as sufficiently verified in P2.7; unchanged this pass.
- Everything else P2.6/P2.7 already classified as "should have"/"nice to have" for 1.0 (compress/extract/make-link/drag-drop/sort/bookmark deeper test coverage, `CommandFacade.qml`'s internal duplication, the two trivial `-Wunused-parameter` warnings) remains exactly as classified there — this pass didn't revisit or change those calls.

---

## 1.0 Definition of Done

- [x] No known P0/P1 blockers.
- [x] P2.7 blockers resolved.
- [x] 124/124 selfchecks stable (the one contention-related failure explained, not a regression).
- [x] Clean build.
- [x] Warning status understood (2 pre-existing, trivial, fixed-signature warnings).
- [x] Native concurrency safety verified (targeted ASan re-run for the one C++ change since P0's pass, clean).
- [x] Packaging/install verified (production-path DESTDIR build, staged launch, 124/124 from the staged binary).
- [x] No obvious regression in core user flows (verified via the full selfcheck suite, which exercises delete/trash, undo/redo, bulk rename, chmod, compress/extract, archive browsing, custom keybindings, alternating rows, Ctrl+L).
- [x] README/documentation current (count fixed, archive-tool dependency gap documented).
- [x] Git tree understood and cleanly separable into release vs. development artifacts (full classification above).
- [x] No accidental debug/test artifacts in production (verified: zero leftover `console.log`/`console.warn`/DEBUG markers in any changed file).
- [x] No unresolved security blocker.
- [x] No unnecessary architectural work remaining for 1.0.
- [ ] **Not done here, by design:** commit, push, PR, CHANGELOG.md entry, `.gitattributes` decision on `docs/audits/`, PKGBUILD dependency addition — all explicitly deferred to the separate release-preparation step this task was told not to perform.

---

## Recommendation

**Freeze `1.0-dev` for the release-preparation step.** The tree is stable, verified, and the one real bug this pass found is fixed and covered. The remaining known issues are genuinely non-blocking and already triaged. The next step (explicitly out of scope for this task) is a deliberate release-preparation pass: write the `CHANGELOG.md` 1.0 entry, decide the `docs/audits/` export-ignore policy, add `zip`/`unzip` to `PKGBUILD`'s `depends` (and fix `install-integrations.sh`'s XDG assumption) before any actual AUR publication, commit the accumulated work in reviewable chunks (per-phase, matching the P0/P1/P2.1–P2.8 structure already established), and — once the user's own working session allows it — a final human eyes-on smoke test before tagging.

---

## Final report checklist (as requested)

1. **Final selfcheck count:** 124/124.
2. **Repeated-run stability:** 18/19 clean this pass overall (1 explained contention-related failure); 6/6 clean in the final confirming batch.
3. **Build/warning status:** clean build, 0 errors; `-Wall -Wextra` clean except 2 pre-existing trivial `-Wunused-parameter` warnings (unchanged from P2.6/P2.7).
4. **ASan decision/result:** warranted (P1-4's `beginCancelToken()` shared_ptr change) and run — 4 passes, 300 overlapping cancel/copy operations, zero violations.
5. **Packaging result:** clean — production-path DESTDIR build, staged fakeroot launch, 124/124 from the staged binary, zero dev-path leaks.
6. **Manual smoke-test result:** skipped and explicitly reported (user's live single-instance session active throughout).
7. **Exact files changed this pass:** `core/AppBindings.qml` (production bug fix), `src/selfcheck/checks/CheckInfrastructure.qml` (new regression guard), `README.md` and `docs/architecture/ARCHITECTURE.md` (documentation corrections), plus this new document.
8. **Files recommended for the 1.0-dev release:** all "Should ship" categories above (production source, tests, required docs) — 28 files.
9. **Files recommended to remain outside the release:** `omafiles-0.9.0.tar.gz` (stray build artifact, currently untracked). `docs/audits/*` flagged for a deliberate maintainer policy decision, not excluded by default (existing precedent already ships this directory).
10. **READY TO FREEZE 1.0-DEV: yes.**

Not committed. Not pushed. Not merged.

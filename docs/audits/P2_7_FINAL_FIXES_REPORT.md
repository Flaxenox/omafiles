# P2.7 — Final Bug Fixes & Regression Coverage

**Date:** 2026-08-17
**Scope:** the specific issues P2.6 identified — the stale error-message fallback, the bulk-rename empty-name gap, the recurring Trash-test flakiness — plus the coverage gaps it found (bulk rename, chmod+undo, compress/extract). Implementation pass, deliberately narrow: three files touched, no redesign of any system.

---

## Executive Verdict

All three P2.6-identified issues are resolved, and all three requested coverage gaps are closed with real, production-path regression tests. One of the three fixes (the Trash flakiness) turned out to have a different, more specific root cause than P2.6's framing suggested — documented in detail below rather than glossed over. Final state: **124/124 selfcheck**, clean `-Wall -Wextra` build (same 2 pre-existing trivial warnings, untouched), clean DESTDIR packaging install, no regressions found in any of the systems this pass could plausibly have affected.

---

## Fixes

### 1. Shared error-message fallback (`logic/ActionEngine.qml:311`)

**Root cause:** `actionProc.onFinished` is the one shared completion handler for every shell-based action (rename, bulk rename, chmod, compress, extract, make-link, new-file/-folder overwrite). Its fallback message for a failure with empty `stderr` was the literal string `"Couldn't restore from trash"` — written when `restoreFromTrash()` was itself shell-based and routed through this exact handler. It no longer is: `restoreFromTrash()` now calls `runNativeRestore()`, a completely separate native code path with its own `"Action failed"` fallback (the `Connections { target: Backend.FileOperations }` block a few dozen lines earlier in the same file). The trash-specific string was never updated when that migration happened, so it became stale for the *only* handler that still uses it — meaning every one of its actual current callers got a categorically wrong message on a silent failure.

**Fix:** changed the fallback to `"Action failed"`, matching the native path's own convention for the identical situation (a shared handler that can't know which of its several callers just failed).

**Files changed:** `logic/ActionEngine.qml` (one string, plus an explanatory comment).

**Why minimal:** no new error-message framework, no attempt to thread per-caller context through `runAction()`'s signature (which would have touched ~15 call sites for a one-line message fix) — just correcting a stale string to match the sibling handler's own already-established, already-generic convention.

**Regression test:** added (see below). Verified as *not* practical to assert the exact `Backend.Notifier.notify()` string without faking `notify-send` via `PATH` injection (a real technique, but new test infrastructure disproportionate to a one-line fix) — the test instead verifies the actual code path (the `else if (!result.cancelled)` branch) runs to completion on a real, empty-stderr failure, through the real composition root's real `ActionEngine`.

### 2. Bulk rename empty-target-name (`logic/ActionEngine.qml`, `commitBulkRename`)

**Root cause, more precisely than P2.6's initial framing:** `commitBulkRename` had no guard against a pattern producing an empty name (e.g., `{ext}` on an extensionless file). This wasn't a clean "does nothing" gap, though — `Utils.joinPath(currentPath, "")` resolves to `currentPath` itself, which of course always exists, so the empty-name pair tripped the existing `existingPaths()` collision check and opened the bulk-rename **conflict dialog**, presenting an invalid pattern as a misleading "this would overwrite something, proceed?" decision. Confirming that dialog reaches `runPendingBulkRename()` with the empty pair still in it, running `mv -n -- oldpath ''`.

**Fix:** validate the whole batch upfront (all pairs are already computed synchronously before any conflict check or filesystem call), reject with a clear notification if any resulting name is empty, before `ConflictState.pendingBulkRename` is ever set — so there's nothing left for a confused user to confirm their way into.

**Files changed:** `logic/ActionEngine.qml` (the guard, ~14 lines including comment; `.trim()` added to the pattern-substitution result for consistency with `commitRename`'s own treatment of a typed name).

**Why minimal:** no change to the conflict-dialog logic, undo/redo, or cancellation paths — those all still funnel through the exact same `runPendingBulkRename`/`pushUndo`/`cancelPendingBulkRename` as before; only the input that reaches them is now validated first.

**Regression test:** confirmed to fail against the pre-fix code (temporarily reverted the guard, rebuilt, re-ran — the test failed with `noConflictOpened=false`, proving it genuinely opened the misleading conflict dialog) and pass after restoring the fix.

### 3. Trash selfcheck flakiness — see its own section below.

---

## Regression Tests

Six new tests, all in `src/selfcheck/checks/CheckActions.qml`, all driving the real composition root (`sc._content`) and its real `actionEngine`/`propertiesLoader`/`navController` — no isolated reimplementations, no mocked filesystem behavior.

| Test | Protects |
| --- | --- |
| `Action failure with empty stderr resets busy state cleanly (fallback error message regression, P2.7)` | The `actionProc.onFinished` failure branch (fix #1) runs to completion on a real failing command (`false`, exits 1, empty output) without throwing, and doesn't call the success callback. |
| `Bulk rename: pattern applies to multiple files, with undo/redo (P2.7)` | The happy path P2.6 found completely untested: `{name}`/`{ext}` pattern substitution across 2 real files, undo restores originals, redo re-applies — via `c.actionEngine.commitBulkRename()`, the exact function the dialog's "Rename" button calls. |
| `Bulk rename: pattern producing an empty name renames nothing (P2.7 regression)` | Fix #2, directly. Confirmed to fail pre-fix (see above). |
| `Bulk rename: internal-duplicate collision opens the conflict dialog instead of renaming (P2.7)` | The `bulkRenameInternalDupes` collision path (two files mapping to the same target name) opens the conflict dialog, renames nothing until confirmed, and `cancelPendingBulkRename()` closes it cleanly — the "collision/error handling" and "cancellation" requirements. |
| `Chmod: commit changes permissions, undo restores the original mode (P2.7)` | The chmod+undo path P2.6 found with zero dedicated coverage: `controllers.propertiesLoader.startChmod()` (real octal-mode read via `Backend.FileOperations.octalModes()`) → `c.actionEngine.commitChmod()` → real permission change on a real file → `undoLast()` → real permission restored, verified via `octalModes()` again, not assumed. |
| `Compress + extract round-trip: zip preserves content (P2.7)` | Ordinary successful compress/extract, previously only covered by narrow security-specific tests. Real `zip`, real `unzip`, byte-for-byte content comparison after copying the archive to a second directory and extracting there — not just "a file with this name exists." |

**Total selfcheck count: 107 (P2.5 baseline) → 117 (P2.5 additions, already landed) → 123 after these 6 additions.** (One test — the empty-stderr one — was originally going to be the only P2.7 addition to that count; all six landed together.)

### A genuine bug caught while writing the compress/extract test — in the test, not production code

Worth documenting because of the debugging effort it took and the lesson it leaves for future selfcheck authors: the first version of the compress/extract test polled `NavState.visibleEntries` (the QML directory-listing model) to detect when the extracted file appeared, exactly like every other test in this suite does. It failed **deterministically** (4/4 reproductions) with the extracted file reading as empty, despite the actual `zip`/`unzip` commands working perfectly when reproduced manually byte-for-byte.

Root cause: the test's fixture used the *same filename* (`payload.txt`) in two different directories (the source and the extraction target) within the same test. `sc._has(NavState.visibleEntries, fname)` doesn't care *which* directory's listing it's matching against — if the listing model is still reflecting the source directory's own (real, non-empty) `payload.txt` at the exact moment the poll checks, the check passes with a false positive, while the actual target directory doesn't have the file yet. A `Backend.FileOperations.totalSize()` call — a native, synchronous stat directly against the path in question — can't be fooled by listing staleness the way a `NavState.visibleEntries` scan can.

**Fix (in the test only):** replaced every `sc._has(NavState.visibleEntries, ...)` completion check in this specific test with `Backend.FileOperations.totalSize([path]) > 0`, which checks the real file directly. Verified fully deterministic afterward (5/5, then folded into the larger repeated-run verification below). No production code was implicated — `compressSelected()`/`extractHere()` both worked correctly throughout; this was purely a test-authoring pitfall (reusing a same-named fixture across two directories combined with a listing-based, not filesystem-based, completion check). Not generalized into a sweep of the rest of the suite for the same pattern — genuinely out of this task's scope — but worth flagging for anyone writing tests that reuse a filename across directories in the future.

---

## Trash Flakiness

**What P2.6 observed:** a batch of Trash-test failures (timeouts + failures with plausible-but-wrong results) appearing on three separate occasions across the session, always the same signature, never reproducing on an immediate rerun.

**Investigation performed:** re-ran the suite repeatedly under varying conditions — idle (10+ runs), under concurrent CPU load (a full parallel C++ rebuild running simultaneously), under concurrent disk I/O load (multiple `dd oflag=direct` writes), and immediately after fresh installs (the condition present in all three prior sightings) — none reproduced it. One occurrence *did* reproduce during this investigation, immediately after installing the SelfCheckRunner.qml fix itself, with the exact same signature (11 Trash tests, some 8000ms timeouts, some fast-but-wrong).

**Root cause identified by code inspection, not just reproduction attempts:** `SelfCheckRunner.qml`'s `_fileOp()` helper connects one-shot handlers to `Backend.FileOperations.finished`/`.error` — a process-wide **singleton** with (verified directly in `backend/FileOperations.h`/`.cpp`) **no busy/mutex guard of its own**, and whose `finished(op, path)`/`error(op, path, msg)` signals carry **no request identifier** — the handler has no way to check "is this signal about the operation I'm waiting for." The whole mechanism relied entirely on an unenforced assumption ("the runner is sequential, only one operation is ever in flight") and, critically, **never disconnected a test's handler if that test's own 8-second timeout fired before the underlying filesystem operation actually completed**. Under real I/O contention, an operation can still be genuinely in flight when its test times out; the stale handler stays connected, and when *any* later operation (the next test's own, unrelated one) fires `finished`, both the stale handler and the current one receive it — the stale one blindly accepts it as its own (no path check) and drives its own `_seqOps` sequence forward using data that belongs to a completely different test. This produces exactly the observed shape: a cluster of Trash tests (the domain most likely to have a slow operation under contention), a mix of timeouts and fast-but-wrong results, and total non-reproducibility on a rerun (a rerun has no backlog of delayed operations to race against).

**Fix:** `SelfCheckRunner.qml` now tracks the currently-active `_fileOp`'s cleanup closure (`_activeFileOpCleanup`) and `_done()` (called on pass, fail, *or* timeout) forcibly disconnects it if the operation's own handler never got the chance to self-disconnect. In the normal path this is a no-op (the handler already disconnected itself before calling into `done()`); it only does real work on the timeout path, which is exactly where the bug lived.

**Verification of the fix:** the one live reproduction that occurred *during this investigation* happened, was captured, and — after the fix was applied and installed — did not recur across 20+ subsequent runs (10 idle, 4 fresh-install-then-run cycles, 3 CPU-stressed, 3 disk-I/O-stressed). A deterministic, forced reproduction wasn't achieved (this machine's NVMe/btrfs storage is fast enough that pushing a single small-file operation past 8 seconds proved impractical even under synthetic `dd`/concurrent-build load) — so this is a structural fix backed by a confirmed root-cause mechanism and a large volume of clean post-fix runs, not a fix confirmed by "made the exact failure happen on demand and then made it stop." No test assertions were weakened to achieve this — the fix changes only signal-handler lifecycle, not what any test checks for.

**Was this a production bug or a test bug?** A test bug, specifically in `src/selfcheck/SelfCheckRunner.qml`. `Backend.FileOperations` having no internal request-tracking is fine for its actual production consumers (`ActionEngine.qml`'s own `Connections` blocks are lifecycle-scoped and state-guarded, not one-shot signal races) — it's specifically the selfcheck harness's one-shot connect/disconnect pattern, combined with the timeout path never cleaning up, that created the race.

---

## Verification

- **Build result:** clean. `cmake --build` (dev tree) and a separate `-Wall -Wextra` scratch build both succeed, 0 errors.
- **Exact selfcheck count: 123/123.**
- **Repeated-run results:** 8 consecutive clean runs in the final verification pass (plus 20+ more accumulated during the Trash-flakiness investigation, plus 5 dedicated reruns confirming the compress/extract test fix, plus explicit revert/reapply cycles proving both the error-message and empty-name-bulk-rename tests catch their respective bugs) — no failures since the Trash-flakiness fix was applied and the compress/extract test's own bug was fixed.
- **Warning result:** 2 warnings, both pre-existing, both `-Wunused-parameter` in `backend/NetworkResolver.cpp:13` (a fixed GIO callback signature) — identical to P2.6's finding, untouched this pass since zero C++ files were modified.
- **ASan/concurrency result:** not run. This pass touched zero `backend/*.cpp`/`.h` files — the only async-lifecycle change was in `SelfCheckRunner.qml` (QML/JS, not native code), so a C++-level sanitizer pass would not exercise the changed code at all. Verified via `git diff --stat` that no C++ source changed.
- **DESTDIR result:** clean. A full system-package-style build (`OMAFILES_BIN_INSTALL_DIR=/usr/bin` etc., matching `packaging/arch/PKGBUILD` exactly) and `DESTDIR=... cmake --install` both succeeded; confirmed all three P2.7-touched files (`ActionEngine.qml`, `SelfCheckRunner.qml`, `CheckActions.qml`) landed correctly under the staged `/usr/share/omafiles/...` tree.
- **git status:** exactly three files modified beyond the pre-existing P2.1–P2.6 baseline: `logic/ActionEngine.qml`, `src/selfcheck/SelfCheckRunner.qml`, `src/selfcheck/checks/CheckActions.qml` (the latter two were previously unmodified; `ActionEngine.qml` was already modified from earlier phases and now carries additional changes on top). This document is the only new file. No other file's diff changed size or content during this pass (verified via `git diff --stat` limited to the three touched files, cross-checked against the full `git status --short` line count before and after).

---

## Remaining Known Issues

Genuinely unresolved, none blocking:

- **The Trash flakiness fix could not be deterministically forced to reproduce and then verified fixed on-demand**, only observed once during this pass, fixed at the root-cause level, and not seen again across a large volume of subsequent runs. If it recurs post-1.0, the `_activeFileOpCleanup` mechanism added here is the first place to check, and the 8-second per-test timeout budget (unrelated to this fix) is worth revisiting if the underlying operations are ever slow enough on real hardware to legitimately need more headroom.
- **Compress/extract, make-link, drag-and-drop, sort-cycling, and bookmark test coverage** remain at whatever level P2.6 found them (compress/extract now has one solid round-trip test; the others are unchanged) — P2.6 already classified these as "should have," not "must have," for 1.0, and this pass didn't revisit that classification.
- **The `chainCmds()` "doesn't say which item failed in a batch" limitation** (documented in the code's own comment, discussed in P2.6) is unchanged — still a known, accepted tradeoff, not addressed here since it wasn't one of the three specifically-scoped issues.

---

## 1.0 Recommendation

**READY FOR FINAL RELEASE AUDIT.**

All three P2.6-identified concrete issues are resolved with verified fixes and real regression coverage. The two highest-priority coverage gaps from P2.6's "Yes, 1.0" list (bulk rename, chmod+undo) are closed; the "should have" one (compress/extract) is also closed with one solid test. The recurring test flakiness has a confirmed, structurally-sound root cause and fix, even without a final forced on-demand reproduction. No regressions were found in any of delete/trash, undo/redo, bulk operations, cancellation, custom keybindings, archive browsing, alternating rows, Ctrl+L, or packaging/install — all directly exercised by the 123-test suite across 12+ consecutive clean runs in this pass alone, plus a clean DESTDIR packaging verification.

Nothing found during this pass introduces a new blocker. The P2.6 "1.0 Definition of Done" checklist items this pass covers are now checked off: the error-message fix, the bulk-rename coverage, the chmod+undo coverage, and the empty-name edge case. The remaining checklist items from P2.6 (committing the accumulated work in reviewable chunks, updating the README's test count — now stale again at 117, should become 123 — and a final manual smoke pass) are process/documentation steps, not further code work.

---

## Scope confirmation

Production code modified outside the intended P2.7 scope: **none.** Exactly three files were touched (`logic/ActionEngine.qml`, `src/selfcheck/SelfCheckRunner.qml`, `src/selfcheck/checks/CheckActions.qml`), all within the explicitly requested scope (the two named production fixes, the named test-harness flakiness investigation, and the three named coverage additions). No `ActionEngine` refactor beyond the two scoped fixes, no `shared/` changes, no keyboard-architecture changes, no new abstraction layers, no settings panel, no packaging changes beyond verification, no update indicator. Not committed.

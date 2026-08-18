# PR #7 Conflict Audit — Investigation + Resolution

**Date:** 2026-08-17
**Scope:** originally a read-only investigation of why PR #7 (`v1.0-dev` → `master`) conflicts (sections below, unchanged from the original pass — no files were modified, no commits were made during that investigation; every command used was read-only). A separate, later task then acted on this investigation's recommendation — see **Resolution** at the end for what was actually done, verified, and pushed.

---

## Executive Summary

PR #7 conflicts for two structurally different reasons, not one:

1. **`master` is simply behind `v1.0-dev` on 11 files** (6 `backend/FileOperations*` files, `logic/ActionEngine.qml`, `packaging/arch/PKGBUILD`, `panels/ActiveFileList.qml`, `panels/FileListRow.qml`, `shared/MarqueeCatcher.qml`). `master` received an earlier, **incomplete** copy of the P0 forensic-audit fix (missing hundreds of lines of regression-test additions that exist in `v1.0-dev`'s copy of the same fix) and never received the P1/Debian-feedback/P2.1–P2.8 work at all. These are ordinary content conflicts caused by real, overlapping — but one-sided-superset — edits. Not a disagreement; `v1.0-dev`'s version is verified to be a strict superset/newer revision in every case checked.
2. **`master` has a deliberate policy commit that deletes the entire `src/selfcheck/` test suite** (10 files) **and `bench/`**, titled *"chore: strictly remove dev/agent files from stable branch"* (`25ee1bb`, 2026-08-15). `v1.0-dev` not only kept that suite, it is built entirely around it — the whole 1.0.0 verification story (124/124 selfchecks, the final release audit, the release-prep validation) depends on `src/selfcheck/` existing. This is a genuine **policy conflict**, not a git mechanics problem: does the 1.0.0 release ship the test suite on `master`, or does `master`'s existing "no dev/agent files" convention override that? This is the one part of this investigation that needs a human decision, not just a merge strategy.

Nothing about the conflict threatens data loss **if handled correctly** — every piece of `v1.0-dev`'s work still exists, intact, on the `v1.0-dev` branch and in the pushed release commit `c039a64`. The risk is entirely in *how* the conflict gets resolved, not in the current state of anything.

---

## Branch divergence

Merge base: `dd1107f` (`chore(changelog): Add RC1 fixes to v0.9.0`, the last commit both branches share).

### Commits unique to `master` (5)

| SHA | Date | Message |
| --- | --- | --- |
| `f8ecfbd` | 2026-08-17 | `fix: resolve P0 forensic audit findings (data integrity, symlink security, packaging, concurrency UAFs)` |
| `93164ec` | 2026-08-15 | `chore(pkg): update PKGBUILD sha256 for marquee hotfix` |
| `d344fd2` | 2026-08-15 | `fix(marquee): use dynamic row height instead of hardcoded 32px` |
| `b4fe670` | 2026-08-15 | `chore(pkg): update PKGBUILD sha256 for final v0.9.0 tarball` |
| `25ee1bb` | 2026-08-15 | `chore: strictly remove dev/agent files from stable branch` |

### Commits unique to `v1.0-dev` (4)

| SHA | Date | Message |
| --- | --- | --- |
| `c039a64` | 2026-08-17 | `release: 1.0.0` (this session's release-prep commit) |
| `d662782` | 2026-08-17 | `fix: P1 architectural hardening, Debian Sid feedback fixes, P2.1 cleanup` |
| `01b9972` | 2026-08-17 | `fix: resolve P0 forensic audit findings (data integrity, symlink security, packaging, concurrency UAFs)` |
| `bf38073` | 2026-08-15 | `fix(marquee): use dynamic row height instead of hardcoded 32px` |

**Same commit messages, different content, same date.** `master`'s `f8ecfbd` and `v1.0-dev`'s `01b9972` share an identical message and were authored the same day — but diffing their actual patches shows `v1.0-dev`'s version contains ~500 additional lines across `CheckActions.qml`, `CheckFilesystemOps.qml`, `CheckIntegration.qml`, `CheckPreview.qml`, and `CheckSearch.qml` (the regression tests proving each P0 fix) that `master`'s version doesn't have. `master`'s marquee commit (`d344fd2`) and `v1.0-dev`'s (`bf38073`) are, by contrast, **byte-identical patches** (confirmed with `diff`, zero output) — that one really is the same change applied twice on parallel history, no discrepancy at all.

---

## Conflicting files

Computed with `git merge-tree origin/master origin/v1.0-dev` (read-only; no working-tree or ref changes).

| File | `master` change | `v1.0-dev` change | Conflict significance |
| --- | --- | --- | --- |
| `backend/FileOperations.h` | Has the P0 fix (shared `shared_ptr<atomic<bool>>` flag). Does **not** have the P1-4 fix. | P0 fix + P1-4's `beginCancelToken()` (per-operation cancellation tokens). | Low risk — `v1.0-dev` is a strict superset; `master`'s side is simply older. Re-verified this session with a targeted ASan stress test (300 overlapping operations, 4 passes, zero violations). |
| `backend/FileOperations.cpp`, `_Copy.cpp`, `_Move.cpp`, `_Remove.cpp`, `_Trash.cpp` | Same as above (P0 only, uses the shared flag) | Same as above (P0 + P1-4) | Same — `v1.0-dev` supersedes. |
| `logic/ActionEngine.qml` | P0-level state only (308 diff lines vs. `v1.0-dev`) | P0 + P1 (`_batchCompleted` tracking) + P2.1 (stale-comment fixes) + P2.3 (archive-browsing extracted out) + P2.7 (bulk-rename/error-message fixes) | Low risk — large diff, but every increment is additive/corrective work already individually audited (`docs/audits/P2_1`, `P2_3`, `P2_7`). No sign master diverged with an *independent* fix to the same problem. |
| `panels/ActiveFileList.qml`, `panels/FileListRow.qml` | P0-level only | + P2.4 alternating-row-color support | Low risk — additive UI feature on top of the same P0 base. |
| `shared/MarqueeCatcher.qml` | Still imports `../state` directly, calls `SelectionState.*` directly (the pre-P2.1 shape) | P2.1's fix: injected `marqueeTarget` property, no direct `state/` import (resolves a documented `shared/` layering-contract violation) | Low risk — `master` simply never received the P2.1 architectural fix. |
| `packaging/arch/PKGBUILD` | `pkgver=0.9.0`; **has a real, verified `sha256sum`** for the (corrected) 0.9.0 tarball URL, with a comment noting a since-fixed wrong-repo-URL bug; no `zip`/`unzip` in `depends` | `pkgver=1.0.0`; `zip`/`unzip` added to `depends`; `sha256sum` is still an explicit 0.9.0-era placeholder (this session's own `FIXME`, honestly labeled) | **Worth noting, not worrying about:** `master`'s sha256 value is real, but it's a hash *for the 0.9.0 tarball* — irrelevant either way once `pkgver` moves to 1.0.0, since a 1.0.0 release needs a freshly computed hash regardless of which branch's old value "wins." No functional loss either direction. |
| `src/selfcheck/*` (10 files: `SelfCheckRegistry.qml`, `SelfCheckRunner.qml`, and 8 `checks/*.qml` files) | **Deleted entirely** (`25ee1bb`, "strictly remove dev/agent files from stable branch") | Actively developed — this is where all 124 selfchecks live, including every P0/P1/P2 regression test | **This is the real decision point.** A modify/delete conflict, not a content conflict: git can't auto-resolve "one side deleted this, the other kept editing it," and won't guess which intent should win. |

`core/ControllerRegistry.qml` was touched by both sides but **auto-merged cleanly** (no conflict) — flagged here only because it's easy to assume everything P0/P1/P2-related conflicts; it doesn't.

---

## Release impact

**Nothing about `v1.0-dev`'s work is at risk of being lost right now.** The release commit `c039a64` and everything before it on `v1.0-dev` is intact, pushed, and unaffected by any of this — `git merge-tree` is read-only and changed nothing. The risk is entirely prospective and entirely about *how* someone resolves this conflict:

- **If the merge is resolved by blindly accepting `master`'s side** for the content conflicts, the P1-4 cancellation-token fix, the P2.1 `shared/` contract fix, the P2.3 archive extraction, the P2.4 alternating rows, and the P2.7 bug fixes would all be silently reverted — a real, severe loss, since every one of those was individually audited and verified this session.
- **If the merge is resolved by blindly accepting `master`'s side** for the modify/delete conflicts (i.e., re-deleting `src/selfcheck/`), the entire 124-test verification suite this whole release's "124/124, 5/5 clean runs, ASan-verified" claims are built on would vanish from the merged result — while the CHANGELOG and PR description would still be making those claims. That would be a real, self-contradicting state to ship.
- **If the merge is resolved by accepting `v1.0-dev`'s side everywhere** (the recommended default for the 11 content conflicts, and the position this report leans toward for the selfcheck suite too — see below), nothing verified this session is lost, and `master` gains everything `v1.0-dev` already has.

---

## Should anything on `master` actually go into 1.0.0?

Checked deliberately, not assumed:

- **The two PKGBUILD sha256 bump commits** (`93164ec`, `b4fe670`) are pure maintenance for the *0.9.0* tarball's hash. Superseded by the version bump to 1.0.0 regardless of merge direction — nothing to preserve from these specifically.
- **`f8ecfbd`'s P0 fix** is a strict subset of what `v1.0-dev` already has (same fix, missing the regression tests) — nothing to pull in that isn't already present in fuller form.
- **`d344fd2`'s marquee fix** is byte-identical to `v1.0-dev`'s own `bf38073` — already present, nothing to pull in.
- **`25ee1bb`'s "remove dev/agent files" policy** is the one commit that represents genuine, deliberate intent for `master` specifically — and it's exactly the one this report can't resolve unilaterally. It predates all of the P0–P2 work (2026-08-15, before the forensic audit even started) and was written when `master` was meant to be a stripped, purely-user-facing distribution branch. Whether that policy should still apply once `master` is about to become the 1.0.0 release branch — with its release notes explicitly built on the selfcheck suite's existence — is a call this report flags rather than makes.

**Conclusion: nothing on `master` needs to be pulled into 1.0.0 beyond what a clean merge already brings in mechanically** (there is no independent `master`-only improvement being overlooked). The only open question is whether `master`'s *deletion* policy should be honored going forward.

---

## Recommended strategy

**Option B — merge `master` into `v1.0-dev`, then push the resulting merge commit.**

Why, evaluated against all four options:

- **Option A (rebase `v1.0-dev` onto `master`)** — rejected. `v1.0-dev` is already pushed with an open PR; a rebase would rewrite all 4 of `v1.0-dev`'s unique commits (including the already-reviewed release commit `c039a64`) to new SHAs, requiring a force-push to update the remote branch — explicitly against this session's constraints, and disruptive to the open PR's review state regardless of who's constraining what. No mechanical advantage over Option B that would justify that cost — the conflict set resolves the same way either way.
- **Option B (merge `master` into `v1.0-dev`)** — recommended. Creates one new, ordinary, additive merge commit on `v1.0-dev`. Doesn't touch or rewrite any existing commit, including `c039a64`. Resolves all 21 conflicting files in one reviewable commit. Once pushed (a normal, non-force push — the existing remote `v1.0-dev` is still an ancestor), PR #7 becomes cleanly mergeable without ever touching `master` directly.
- **Option C (resolve directly on the release branch)** — not meaningfully different from B in outcome, but worse in traceability: with 21 files involved and one deliberate cross-branch policy question in the mix, an actual `git merge` (which records both parent commits and is trivially re-inspectable later) is more honest about what happened than ad-hoc file-by-file edits that would look, in history, like ordinary feature commits rather than a conflict resolution.
- **Option D (recreate the PR differently)** — not warranted. The branch history is diverged but fully explicable (confirmed above, commit by commit); nothing about it is broken or corrupt in a way that makes the current PR unsuitable.

---

## Exact resolution plan (for the next, separate task — not performed here)

**The 11 content conflicts:** take `v1.0-dev`'s side (`git checkout --ours` per file, in merge terms) for all of `backend/FileOperations.h`, `backend/FileOperations.cpp`, `backend/FileOperations_Copy.cpp`, `backend/FileOperations_Move.cpp`, `backend/FileOperations_Remove.cpp`, `backend/FileOperations_Trash.cpp`, `logic/ActionEngine.qml`, `panels/ActiveFileList.qml`, `panels/FileListRow.qml`, `shared/MarqueeCatcher.qml`. Verified above that `v1.0-dev`'s version is a strict superset/newer revision in every one of these, not a genuine alternative.

**`packaging/arch/PKGBUILD`:** take `v1.0-dev`'s side (`pkgver=1.0.0`, `zip`/`unzip` in `depends`, the honest 0.9.0-tarball `sha256sums` placeholder with its `FIXME`). Master's real sha256 is for the wrong version and would need recomputing regardless.

**The 10 `src/selfcheck/` files (the policy question):** this report's lean, stated plainly — **keep `v1.0-dev`'s side** (i.e., the suite stays), because the 1.0.0 release's own release notes, CHANGELOG entry, and both audit reports already make specific, numbered claims ("124/124 selfchecks," "ASan-verified," "5/5 clean runs") that would become unverifiable and untestable in perpetuity if the suite is deleted at the exact moment those claims ship. But this is explicitly the one part of this plan that should be confirmed by the user before being acted on, since it means implicitly overriding `master`'s own prior, deliberate policy commit rather than mechanically resolving a code disagreement. If `master`'s policy is confirmed to still be intended even for 1.0.0, the alternative (re-delete `src/selfcheck/` as part of the merge resolution) is mechanically straightforward too — it just needs to be a decision, not a default.

**New files added on `v1.0-dev` with no `master` counterpart** (`logic/ArchiveBrowser.qml`, `logic/KeybindingResolver.qml`, `state/KeyboardDefaults.qml`, `src/selfcheck/checks/CheckKeybindings.qml`, `core/PathCompletionField.qml`, and every `docs/audits/*.md` from P2.1 onward) — these don't conflict at all (git adds them cleanly); no decision needed.

---

## Release safety

**The release commit `c039a64` itself is fully intact.** Nothing in this investigation read, modified, or risked it — it remains exactly as pushed, and `v1.0-dev`'s working tree (verified again at the start of this task) is clean with no local changes. The 1.0.0 audit guarantees (124/124 selfchecks, clean build, targeted ASan re-verification, production-path packaging verification) all describe the state of `v1.0-dev` as of `c039a64`, which is unchanged.

**The recommended strategy (Option B) can preserve those guarantees exactly**, provided the resolution plan above is followed: since every content conflict resolves to "keep `v1.0-dev`'s side" (verified as a strict superset in each case) and the `src/selfcheck/` question is resolved in `v1.0-dev`'s favor, the merge commit's resulting tree would be **identical to `v1.0-dev`'s current tree except for whatever master-only content survives untouched** (nothing, per the "should anything from master go into 1.0.0" analysis above) **plus master's history being folded in as a second parent.** In that scenario, re-running the same verification (build, `--selfcheck`, packaging) against the post-merge tree should reproduce the exact same 124/124 result — nothing about the recommended resolution changes any file `v1.0-dev` already has correct.

---

## STOP (end of the original investigation-only pass)

No files were modified. No commits were created. No merge, rebase, or push was performed. `git status` on `v1.0-dev` remained clean, identical to before that investigation began.

---

## Resolution (separate, later task)

Executed Option B exactly as recommended above: merged `master` into `v1.0-dev`, resolved every conflict by inspecting it individually (not a blanket `--ours`/`--theirs`), verified, committed, and pushed.

### Merge commit

**`bf8ccff1c7befb77f8759eb6aebfeb885b9e03de`**, parents `c039a648511923c06d2d90154efcfdd7e07bdbe0` (the release commit, unchanged and unrewritten) and `f8ecfbd32ff1c94b073b7cf1074ff7e4064851cf` (`master`'s tip). A normal, additive 2-parent merge commit — no rebase, no squash, no force-push.

### Conflicts resolved

- **11 content conflicts** (`backend/FileOperations.{h,cpp}` + 4 sibling files, `logic/ActionEngine.qml`, `packaging/arch/PKGBUILD`, `panels/ActiveFileList.qml`, `panels/FileListRow.qml`, `shared/MarqueeCatcher.qml`) — resolved to `v1.0-dev`'s side, per this document's own file-by-file verification above (every one confirmed a strict superset/newer revision, not a genuine disagreement).
- **10 modify/delete conflicts** (all of `src/selfcheck/`) — resolved by keeping `v1.0-dev`'s complete content, per explicit release policy.

### `src/selfcheck/` preservation — confirmed complete, including a gap this document's own conflict list missed

All 10 files this document originally flagged as conflicting were preserved. **During resolution, 5 additional `src/selfcheck/` files were found silently auto-deleted** that this document's `git merge-tree` pass never flagged: `checks/CheckDevices.qml`, `checks/CheckFilesystemListing.qml`, `checks/CheckPerformance.qml`, `checks/CheckPersistence.qml`, and `qmldir`. These weren't real conflicts in git's 3-way sense — `v1.0-dev` never modified them since the merge-base, so git silently applied `master`'s deletion with no conflict marker at all, the same mechanism as `bench/`'s clean auto-delete. The difference: `SelfCheckRegistry.qml`'s own `_moduleUrls` list explicitly references all 4 of those check files — deleting them would have broken the suite's module loading, not just shrunk its coverage. Restored from `v1.0-dev`'s tree and staged alongside the 10 originally-flagged files.

**Final verification of completeness:** every file that exists in `v1.0-dev`'s tree and also exists in the resolved merge tree was diffed byte-for-byte against `v1.0-dev`'s pre-merge content — zero differences found anywhere, confirming no stale `master` content survived in any file this operation didn't deliberately choose to delete.

### `bench/`

Not restored, as this document anticipated. Confirmed genuinely unambiguous, not a judgment call: `v1.0-dev` never touched `bench/` since the merge-base (empty diff), so `master`'s deletion applied as a clean, single-sided auto-resolve — not a real conflict requiring a decision, unlike `src/selfcheck/` where both sides had diverged. Already covered by `.gitattributes`' `export-ignore` on both branches; nothing in the 124-test verification suite or this release's audit trail depends on `bench/` existing. `AGENT_BOOTSTRAP.md`/`CLAUDE.md` treated identically, for the same reason (untouched by `v1.0-dev`, already `export-ignore`d, unrelated to release verification).

**One known side effect, deliberately left alone:** `README.md`'s "Performance Regression Gate" bullet still references `bench/bench-gate.py`, which no longer exists post-merge. Editing unrelated README prose wasn't part of resolving this conflict — flagged here as a small follow-up, not fixed.

### A real auto-merge defect caught and fixed

`core/ControllerRegistry.qml` merged with **zero conflict markers** — but the 3-way auto-merge silently reintroduced `list: registry.list` into the `ActionEngine` instantiation, a property P2.3's archive-browsing extraction had deliberately removed (confirmed: the resolved `ActionEngine.qml` no longer declares `property Item list` or uses `list.` anywhere). `master`'s independent, P0-only copy of this file still had the old line; git's line-based merge re-added it without recognizing it conflicted with `v1.0-dev`'s removal. Caught specifically because this operation diffed the *entire* resulting tree against `v1.0-dev`'s pre-merge tree file-by-file, not just the files git itself flagged as conflicting. Fixed by removing the reintroduced line and re-verifying the file matched `v1.0-dev`'s pre-merge content exactly.

### Verification (post-merge, pre-push)

- **Build:** clean, fresh build directory, 0 errors, 0 warnings.
- **Selfcheck:** **124/124**, confirmed on **7 consecutive clean runs**.
- **Packaging:** production-path build (matching `PKGBUILD`'s exact install paths) + `DESTDIR` install to an isolated fakeroot + the **staged binary itself** launched from that fakeroot and run through the full suite: 124/124.
- **ASan:** the `FileOperations` cancellation-token domain (the P1-4 fix, part of the resolved content conflicts) recompiled fresh against the **post-merge** tree and re-stress-tested: 3 passes, 180 overlapping copy/cancel operations, zero violations.

All verification passed before the merge commit was pushed, per the task's own "if any verification fails, STOP before pushing" instruction — nothing failed, so nothing needed to stop for.

### PR #7 status

Pushed with a normal (non-force) `git push origin v1.0-dev`. PR #7 auto-updated to head commit `bf8ccff1c7befb77f8759eb6aebfeb885b9e03de`. GitHub now reports **`mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`** (confirmed after the async recomputation settled) — the conflict is fully resolved. **State: OPEN.** Not merged, not closed, no auto-merge enabled, branch not deleted.

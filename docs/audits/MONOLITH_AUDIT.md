# Monolith Audit — Files Over 300 Lines

**Repo:** /home/josema/Projects/omafiles (branch `v1.0-dev`)
**Date:** 2026-08-16
**Scope:** every `.qml`/`.cpp`/`.h`/`.hpp`/`.js` file in the repository over 300 lines, per the ground-truth size table gathered before this audit began. Ten files qualify.

This document does not re-derive evidence from scratch. It classifies each of the ten files using the deep-dive forensic audits already performed (ActionEngine, CommandFacade, the MainLayout/DialogLayer/KeyboardShortcuts/OmafilesContent/ControllerRegistry cluster) and, where no dedicated deep dive exists, the best corroborating evidence surfaced incidentally by the directory-inventory passes (app-core, logic-state, panels-dialogs-shared, scripts-docs-selfcheck, backend-io, backend-features). Where the available evidence is thin or absent, the file is explicitly marked **UNVERIFIED** rather than guessed at. Nothing here was fixed, refactored, or edited — this is a read-only classification exercise.

## Classification legend

- **Coordinator** — orchestrates/wires other components together; size comes from breadth of composition, not tangled responsibility. Splitting it would mostly just relocate wiring code, not remove coupling.
- **Domain Module** — a single, real, cohesive concern (even if it has multiple functions/sub-areas) that legitimately belongs together. Large because the domain is large, not because unrelated things were merged into it.
- **Acceptable Large Component** — size is justified by the breadth of what the component visibly does (many sibling UI elements, many token categories, many small variants), not by scope creep or unrelated concerns bolted on.
- **Accidental Monolith** — grew large through file merges/consolidation rather than deliberate design; contains multiple genuinely separable concerns that were not unified by any real abstraction; typically has stale self-description (comments/docs) proving nobody re-validated the merge.
- **True Monolith** — no coherent single responsibility at all; a dumping ground with no redeeming coordinator/domain logic; the classification of last resort.

---

## Summary table

| # | File | Lines | Classification | Evidence basis |
|---|---|---|---|---|
| 1 | `logic/ActionEngine.qml` | 1205 | **Accidental Monolith** (tilting into architectural dumping ground) | Full deep dive |
| 2 | `main.cpp` | 442 | **UNVERIFIED** | No dedicated evidence in any pass |
| 3 | `app/qml_modules/qs/Commons/Style.qml` | 440 | **Acceptable Large Component**, inflated by confirmed dead code | app-core inventory (Findings 8) + UI-shell deep dive (hairline bug) |
| 4 | `backend/DirectoryModel.cpp` | 371 | **Domain Module** | backend-io inventory (explicit positive verdict) |
| 5 | `core/DialogLayer.qml` | 361 | **Acceptable Large Component**, with one serious bug | Full deep dive (UI-shell cluster) |
| 6 | `panels/BackgroundPanel.qml` | 326 | **Domain Module drifting toward Accidental Monolith** | panels-dialogs-shared inventory (Finding 5) |
| 7 | `src/selfcheck/checks/CheckFilesystemOps.qml` | 317 | **UNVERIFIED** | Explicitly not content-audited by any pass |
| 8 | `core/CommandFacade.qml` | 311 | **Accidental Monolith** (milder than ActionEngine) | Full deep dive |
| 9 | `logic/NavigationController.qml` | 303 | **Domain Module** (partial evidence, consistently positive) | Cross-references in ActionEngine + CommandFacade deep dives, logic-state inventory |
| 10 | `core/MainLayout.qml` | 303 | **Coordinator**, with confirmed defects | Full deep dive (UI-shell cluster) + app-core inventory (Finding 3) |

---

## 1. `logic/ActionEngine.qml` (1205 lines) — Accidental Monolith

**Verdict reproduced verbatim from the dedicated deep dive; do not re-litigate as "split it, it's big."**

This file was 290 lines as of commit `37f3f31^` — a genuinely cohesive "reversible-action execution engine" (undo/redo stack + native-batch backend dispatch). Commit `37f3f31` ("chore: architecture consolidation and final v0.9.0 stability fixes," 2026-08-15, one day before this audit) deleted seven separate, clearly-named domain files (`ArchiveActions.qml`, `ClipboardOps.qml`, `ConflictActions.qml`, `DeleteOps.qml`, `DragDropOps.qml`, `FileOps.qml`, `RenameOps.qml`) in the same commit and pasted their bodies in, verified 1:1 by function-name diff, growing the file to 1205 lines (+915) with zero rationale in the commit message beyond "architecture consolidation."

**The classification is Accidental Monolith, not "big but fine," on the strength of three independent, verified findings — none of which is about size:**

1. **The file's own header comments describe an architecture that no longer exists**, and describe it in a way that is now actively false: lines 7-14 claim six functions (`commitNewFolder`, `requestDelete`, `runPaste`, `commitChmod`, `makeLinkFor`, `restoreFromTrash`) live *elsewhere* and call *into* this engine — all six are defined inside this very file today. Lines 521-525 and 739-767 twice claim code "lives in `logic/ConflictActions.qml`" and warn about a circular-dependency risk with a file (`conflictActions`) that does not exist anywhere in the current file's scope. This is not documentation drift at the margins; it is the file lying about its own current structure, and the same rot is echoed in `state/ConflictState.qml:8` and `state/FileTypeConfig.qml:5`.
2. **The merge dropped a load-bearing dependency and shipped a live regression.** Every sibling controller that touches the shared `ListView` (`NavigationController`, `TabOps`, `SearchOps`) declares `property Item list: null` and receives it via explicit binding in `core/ControllerRegistry.qml`. The deleted `ArchiveActions.qml` followed this convention too (confirmed via `git show 37f3f31^:logic/ArchiveActions.qml`). The merged `ActionEngine.qml` declares no such property, and its sole instantiation site (`core/ControllerRegistry.qml:89-93`) does not bind `list` — yet the merged-in archive code still references the bare identifier `list` twice (`refreshArchiveListing()` line 1118, `archiveListProc.onFinished` line 1188). This throws `ReferenceError: list is not defined` on every archive open and every navigation step inside an archive. Zero selfcheck coverage exists for archive browsing (`grep -rln "enterArchive\|refreshArchiveListing\|archiveListProc\|isArchive(" src/selfcheck/` → empty), so this regression had no tripwire.
3. **Even within the file, the "many operations" aren't unified — they're concatenated.** `runPaste`(411-456) and `runDrop`(1051-1094) are ~40-line near-duplicates with inconsistent self-reference style (`pushUndo(...)` vs `actionEngine.pushUndo(...)`), and eight separate blocks reimplement the identical "check `existingPaths`, then open the matching `ConflictState.*ConflictOpen`" pattern. Both duplications predate the merge (they existed independently in the now-deleted files) — the merge co-located two already-duplicated implementations instead of using consolidation as an opportunity to unify them, which is the opposite of what a deliberate "one true domain" redesign would do.

**What NOT to extract, per the deep dive:** the undo/redo stack + native-batch backend orchestration (lines 30-290) is the one piece that earns "coordinator" status and should stay. Delete/trash, clipboard, rename/new-file/new-folder, bulk-rename, chmod, symlink, drag-drop, and compress/extract are all legitimately "mutating file actions through `runAction`" and recombining them isn't inherently wrong — the failure is that it happened silently, broke a real feature (archive browsing), and left the file's own documentation false.

**What is a defensible, narrowly-scoped extraction (named functions, not filesize hygiene):** (1) the archive navigation/listing block (~105 lines: `enterArchive`, `exitArchive`, `refreshArchiveListing`, `openFileInArchive`, `isArchive`, `isIso`, `archiveListProc`/`archiveOpenProc` handlers) — the only block that never touches `runAction`/native-batch/`pushUndo`, and the exact block that lost its `list` binding; (2) fixing the four stale/false comment blocks; (3) deduplicating `runPaste`/`runDrop`; (4) deduplicating the eight conflict-check blocks.

---

## 2. `main.cpp` (442 lines) — UNVERIFIED

No deep dive or inventory pass in this audit round read `main.cpp`'s content directly. The app-core inventory covered `app/HostAdapter.qml`, `app/Main.qml`, and `app/SelfCheck.qml` (QML bootstrap layer) but not the C++ `main.cpp` entry point itself. The only indirect signal available is from ground truth: it is the second-largest file in the repo after `ActionEngine.qml`, and per the app-core inventory, context properties it's responsible for setting up (`selfCheckTmpDir`, `SelfCheckOut`, `SingleInstance`, `omafilesInitialPayload`) suggest it owns single-instance activation, D-Bus service registration (`FileManager1`, portal `FileChooser`), and QML engine bootstrap — plausibly a legitimate "coordinator" given that surface area, but this is inference from adjacent evidence, not a direct reading of the file. **Do not classify without reading `main.cpp` directly in a follow-up pass.**

---

## 3. `app/qml_modules/qs/Commons/Style.qml` (440 lines) — Acceptable Large Component, inflated by confirmed dead code

This is a theming/design-token file (color, spacing, typography derivation) — the kind of file whose size is normally justified by breadth of token categories, which is a legitimate "Acceptable Large Component" shape. However, two independent passes found concrete problems that mean its 440 lines overstate the component's real, live surface:

- **Confirmed dead code inflating the line count** (app-core inventory, Finding 8): the entire `bar: QtObject { sizeHorizontal, sizeVertical, iconSlot, iconCanvas, iconFont, statusSlot }` token group, its backing `barToken()`/`barOverrides`/`barScaleWithFont`, and `menuFontFamily`/`resolvedFontFamily` (lines 291, 298-299, 312-318, 333, 355-362) have **zero usages anywhere in the repo** — verified by grep. These are Quickshell status-bar sizing tokens vestigial from the file's origin as a fork of the real Omarchy `qs.Commons.Style`, with no meaning in a file manager. The same finding notes a stale comment (line 366) referencing a `Color.loadShell` function that doesn't exist in this codebase.
- **A real, falsifiable arithmetic defect that other files depend on incorrectly** (UI-shell deep dive): `space(px)` (lines 217-220) rounds `spaceReal(px)` up to at least 1, so `hairline` (line 232, `root.space(1)`) is **not guaranteed to equal 1px** — it becomes 2px+ once `fontScale`/`spacingScale` exceeds ~1.5, a normal state for the accessibility/roomy-theme settings this same Style system explicitly supports. `core/MainLayout.qml` correctly uses `Style.spacing.hairline` for two dividers but hardcodes the literal `1` in two other places meant to represent the same divider width (lines 83, 274-278), producing either a 1px content/divider overlap or dead zone in the marquee-select hit area at scaled themes. This defect isn't in Style.qml itself, but Style.qml's own non-obvious rounding behavior is the root cause a consumer had to (and didn't) account for.

Net: legitimately a design-token file (Acceptable Large Component shape), but a meaningful fraction of its bulk is unused Quickshell-bar residue, and its rounding semantics for `hairline` are under-documented enough that a downstream consumer got them wrong twice in the same file.

---

## 4. `backend/DirectoryModel.cpp` (371 lines) — Domain Module

The backend-io inventory read this file in full and gave it an unambiguous positive verdict, calling it out by name as **"the cleanest file in this slice"**: no dead code, no unused functions, error codes threaded through consistently, life-safety (mutex + `shared_ptr<Life>`) correctly closing the worker/destructor race, and a generation counter that correctly discards stale scans. No duplication, no stale comments, and no scope-creep concerns were raised against it anywhere across any of the seven inventory/deep-dive passes. This is a textbook Domain Module: one real, large concern (async directory listing with correct lifetime management under a QThreadPool worker model) implemented cohesively, with size justified by the genuine complexity of getting that concurrency model right — not by unrelated things being merged in.

---

## 5. `core/DialogLayer.qml` (361 lines) — Acceptable Large Component, with one serious bug

Structurally this file hosts roughly 15 overlay/dialog panels (7 `ConfirmDialog`s, `BulkRenamePanel`, `ConnectServer`, `ChmodPanel`, `PropertiesPanel`, `ShortcutsHelp`, `OpenWithPanel`, `ContextMenuPanel`, two `ConflictResolveDialog`s, `CommandPalettePanel`, a busy-card) — a genuinely broad but single-purpose "dialog/overlay composition layer," which is the shape of an Acceptable Large Component (size from breadth of siblings, not entangled responsibility). It is not accreted from deleted domain files the way `ActionEngine.qml`/`CommandFacade.qml` were.

However, the dedicated UI-shell deep dive found one concrete, serious, verified runtime bug and several lower-severity architectural fragilities that should not be waved away just because the overall shape is defensible:

- **Confirmed missing-import bug (line 72):** the file imports `QtQuick`, `qs.Commons`, `qs.Ui`, `"../dialogs"`, `"../state"` — never `Omafiles.Backend` — yet `onAuthSubmitted` calls `Backend.NetworkResolver.submitAuth(user, password, remember)`. This throws `ReferenceError: Backend is not defined` the moment a user submits credentials on a password-protected network share, *after* `DialogsState.networkConnecting = true` has already been set (line 71) and never rolled back — the dialog gets stuck showing "Connecting…" indefinitely with the real auth call never made. Confirmed as the only file among all 28 in the app+core slice that references `Backend.*` without importing it.
- **z-index layering is not exhaustively exclusive**: 7 `ConfirmDialog`s pinned to `z:10`, busy-card at `z:25`, but the other ~8 overlay panels have no explicit `z` (default 0, order-dependent). Keyboard routing (`KeyboardShortcuts.qml`) enforces mutual exclusivity for keyboard input via early-return priority ordering, but nothing guarantees two `open`/`opened` booleans can't both be true simultaneously via non-keyboard paths (context-menu, palette, async backend callbacks). Flagged as UNVERIFIED-but-structurally-real — would require a full trace through `ActionEngine.qml`'s conflict-state setters to confirm reachability.
- **Untyped `root: Item` cross-file mutation pattern**: an anonymous, always-alive `Timer` (lines 185-192) directly mutates `root.actionBusyDots`, a property owned and declared in a different file (`OmafilesContent.qml:24`). This is the same qmllint-invisible wiring-fragility class the project's own `BackgroundPanel.qml:169-174` comment documents as having already caused one prior silent regression (the 14.E `refreshTick` incident).

Net: the multi-panel composition shape is legitimate and not itself a monolith symptom, but one of its panels' wiring is broken in a way users can hit today, and the file participates in an architectural pattern (untyped `root`) with a documented history of silent breakage.

---

## 6. `panels/BackgroundPanel.qml` (326 lines) — Domain Module drifting toward Accidental Monolith

No dedicated deep dive exists for this file, but the panels-dialogs-shared inventory read it in full and surfaced specific, concrete evidence (not a vague "it's big" observation):

- Owns a **hand-rolled bounded LRU cache** of directory listings (max 8 paths, manual `Object.keys`/`delete`/reinsert eviction, lines 90-103), decides whether the `ListView` model gets reassigned via content diffing, and implements scroll-position save/restore by index + sub-pixel offset (lines 186-220) — none of which is visual presentation. This is real data-management/orchestration logic of the kind that architecturally belongs in `logic/` (e.g., alongside `NavigationController`), not embedded in what the codebase's own docs describe as a "persistent UI panel."
- **This exact save/restore-by-index-and-offset mechanism is independently reimplemented a second time** in `panels/ActiveFileList.qml` (its own `firstVisibleIndex()`/`firstVisibleOffset()`/`positionAtIndexWithOffset()`, lines 46-63) — two parallel, non-shared implementations of the same scrolling mechanism in sibling files, the classic drift-risk pattern (a fix to one won't propagate to the other).
- The panels-dialogs-shared inventory notes explicitly that this is not a hard rule violation only because `panels/` (unlike `shared/`) has no written "no business logic" contract clause to violate — i.e., it's tolerated by omission of a rule, not by design intent.

This is not classified as a full Accidental Monolith because there's no evidence of a mechanical multi-file merge (no deleted-sibling-files trail like ActionEngine/CommandFacade, no stale comments pointing at nonexistent modules), and the file's core purpose (render a non-active tab's listing, pre-warmed) is coherent and well-commented (per the UI-shell deep dive's note on `BackgroundPanel.qml:30-41`'s deliberate `visible:true`/`opacity:0` pre-warm design). But it has already accreted a second, undocumented responsibility (cache-eviction policy + duplicate scroll-state machinery) beyond "render a background panel," which is exactly the early-stage pattern that produced `ActionEngine.qml`'s outcome elsewhere in this codebase. Flagged as the file most likely to become a genuine Accidental Monolith if left unaddressed.

---

## 7. `src/selfcheck/checks/CheckFilesystemOps.qml` (317 lines) — UNVERIFIED

The scripts-docs-selfcheck inventory pass explicitly states its content was **not audited**: "`src/selfcheck/` (2 runner files + 12 check files, content not audited)." No other pass in this audit round opened this file. The only facts known about it are structural (ground truth): it is one of 12 files under `src/selfcheck/checks/`, part of an 85-selfcheck suite launched via `app/SelfCheck.qml`, and — per the ActionEngine deep dive's negative-space check — it does *not* cover archive browsing (`grep` for archive-related function names across all of `src/selfcheck/` returned nothing). **No classification is possible without reading the file directly; do not infer one from its size alone.**

---

## 8. `core/CommandFacade.qml` (311 lines) — Accidental Monolith (milder than ActionEngine, same failure pattern)

**Verdict reproduced from the dedicated deep dive.** Roughly 70% of the file (`paletteCommands`, `itemActions`, `emptyAreaActions`, `bookmarkActions`, `mountActions`, `networkMountActions`, `openPalette`/`closePalette`/`runPaletteCommand`, `openContextMenu`) genuinely is a clean command-mapping facade — each entry's closure is a one-line delegate to a singly-owned controller (`actionEngine`/`mountOps`/`tabOps`/`searchOps`/`propertiesLoader`), with no function-name collisions against those controllers' own method lists. That portion is legitimate and its removal would just scatter command-assembly logic into every consuming view (`panels/FileListRow.qml`, `panels/ActiveFileList.qml`, `core/MainLayout.qml`, `core/DialogLayer.qml` all consume it).

But the remaining ~30% shows the same failure signature as `ActionEngine.qml` — architecture drift from an undocumented consolidation, not a deliberate cohesive design:

- **"Open With" is a complete, self-contained feature living inside the facade** (`showOpenWith`/`launchWith`, lines 252-268): it calls `Backend.MimeResolver` directly (bypassing `ActionEngine`, which every other mutating action routes through per its own header comment), owns three fields of `PreviewState` end-to-end, and independently records recents via `BookmarksState.addRecent`. This is corroborated as a dissolved module, not organic scope: three other files still reference a `logic/OpenWithOps.qml` that does not exist in the current 14-file `logic/` directory (`logic/NavigationController.qml:215`, `state/PreviewState.qml:7`, `docs/architecture/BACKEND_DESIGN.md:471`, `docs/architecture/DEPENDENCY_GRAPH.md:59`).
- **Bookmark/Recent "reveal" navigation logic is hand-duplicated, badly**, against a pattern `NavigationController.enter()` already implements correctly and more completely (`openBookmark`/`openRecent`, lines 208-222): both hand-parse `path.lastIndexOf("/")` instead of sharing a helper, and `openRecent()` — unlike `openBookmark()` — has no `type !== "file"` branch at all, a latent bug if a directory ever lands in recents (flagged UNVERIFIED-reachability in the deep dive). This is the second dissolved module's logic landing here undocumented: `DEPENDENCY_GRAPH.md:55` still shows a `NavigationController --> BookmarkOps` edge to a file that no longer exists.
- **Internal duplication** independent of the above: the "Refresh" command is implemented twice verbatim (lines 36, 204); the "Show/Hide dotfiles" label ternary is duplicated three times (lines 35, 187, 203); "Add to bookmarks" gating logic is duplicated three times (lines 74-76, 169-171, 278-280).
- **A fragile, duplicated safety rule**: archive-mode command filtering uses a hardcoded array of *display label strings* (lines 81-86) to block commands while browsing inside an archive, duplicating a guard that most (but not all) of the underlying `ActionEngine` functions already self-enforce with `if (ArchiveState.inArchive) return`. Three functions (`copyPathAbsoluteFor`/`copyPathRelativeFor`/`copyPathUriFor`) have **no self-guard at all** and currently rely solely on this facade-level filtering for archive safety — not currently exploitable (no other call site reaches them), but a load-bearing invariant sitting in the wrong layer.

This is real business/feature logic (command availability rules, archive-mode gating, Open-With resolution) sitting in a directory (`core/`) whose own contract is "composition/root UI — no business logic" (per the app-core inventory, Finding 4, independently flagging the same file for the same reason). Classified as Accidental Monolith rather than Domain Module because — like `ActionEngine.qml` — its current scope contradicts its own header comment ("menus, command palette, breadcrumbs"), it absorbed at least two former standalone controllers without reconciling the surrounding documentation, and it contains avoidable internal duplication. It is a **milder** case than `ActionEngine.qml`: no confirmed live `ReferenceError`, and 70% of the file is genuinely clean delegation rather than 0%.

---

## 9. `logic/NavigationController.qml` (303 lines) — Domain Module (partial evidence, consistently positive)

No dedicated deep dive targeted this file, but it surfaces repeatedly and favorably across three independent passes, all consistent with a single cohesive domain (real-folder navigation) rather than a merge or dumping ground:

- **ActionEngine deep dive**: cited as one of three siblings (`NavigationController`, `TabOps`, `SearchOps`) that correctly follow the project's dependency-injection convention for the shared `ListView` — `property Item list: null` declared at line 15, bound explicitly at `core/ControllerRegistry.qml:65`. Notably, this is the convention the *merged* `ArchiveActions` code inside `ActionEngine.qml` violated after the merge — `NavigationController.qml` itself was not implicated in that regression.
- **CommandFacade deep dive**: `NavigationController.enter()` (lines 229-239) is explicitly identified as the **canonical, correct** implementation of "reveal an absolute-path item" (navigate to parent + pre-select for a file, navigate directly for a dir) — the pattern that `CommandFacade.openBookmark()`/`openRecent()` hand-duplicate *incorrectly* (missing a type branch) rather than calling into. I.e., NavigationController is the source of truth other files should have deferred to and didn't.
- **logic-state inventory**: listed alongside `TabOps.qml` as one of the two `logic/` files that "legitimately still use `root` for fields not yet migrated to state/ (`tabEntriesCache`, `hasBlockingOverlay`, `suppressListFade`, `_pendingScrollY/Index/Offset`, `hasPendingEdit`, `requestClose()`)" — contrasted explicitly against 8 *other* `logic/` files carrying a *dead*, vestigial `root` property. This means NavigationController's use of shared composition-root state was checked and found to be live/justified, not leftover plumbing.

No pass raised any concern, duplication, or stale-comment finding against this file. Classified as Domain Module on the strength of this converging, entirely positive circumstantial evidence — but flagged as **not** a full line-by-line read the way `ActionEngine.qml`/`CommandFacade.qml`/`DialogLayer.qml` got, so treat with correspondingly less certainty than those three.

---

## 10. `core/MainLayout.qml` (303 lines) — Coordinator, with confirmed defects

This is the composition root for the main window layout (sidebar, panel row, path bar, search bar, file-picker bar, background/active panel repeaters, marquee-select hit area) — a Coordinator by shape: its size comes from wiring together many sibling visual elements, not from absorbed business logic (contrast with `ActionEngine.qml`/`CommandFacade.qml`, which absorbed entire deleted feature modules). The dedicated UI-shell deep dive and the app-core inventory both examined it directly and found concrete, real defects, but none that change its fundamental shape from Coordinator to Monolith:

- **Confirmed 1px layout defect (two sites)**: `mainColumn`'s width computation (line 83: `parent.width - sidebar.width - 1 - parent.spacing * 2`) and the marquee `MouseArea`'s width (lines 274-278: `2 * Style.spacing.panelGap + 1`) both hardcode a literal `1` to represent the sidebar/content divider, while the file correctly uses `Style.spacing.hairline` for the same divider elsewhere (lines 92, 103). Since `Style.spacing.hairline` is not guaranteed to equal 1px at scaled font/spacing settings (see item 3 above), these two sites are provably wrong under any accessibility/roomy theme scale, producing a 1px content/divider overlap or marquee dead zone. Not reproduced live (no scaled-theme build launched in this session), but the arithmetic is unambiguous.
- **Misleading comment vs. actual behavior** (line 110): claims the `Repeater` renders "Background panels (all tabs except the active one)," but `model: TabsState.tabs` has no filtering — a `BackgroundPanel` delegate is instantiated for every tab including the active one. Confirmed intentional/correct behavior elsewhere (`BackgroundPanel.qml:30-41`'s deliberate pre-warm design to avoid a previously-fixed scroll-jump bug), so this is a doc/code mismatch that risks a future maintainer "fixing" the Repeater and reintroducing the scroll-jump bug — not a live defect today.
- **Business logic bleeding into a Coordinator file** (app-core inventory, Finding 3): the exact same 9-line XDG-desktop-portal `SubmitResponse` D-Bus call-construction logic is duplicated verbatim three times across the codebase, once of which is inside `MainLayout.qml` (`FilePickerBar.onResponseSubmitted`, lines ~254-264), the other two in `core/OmafilesContent.qml`. This is genuine protocol/business logic (not composition) sitting in a Coordinator file — a smaller-scale version of the same "core/ = composition only" contract breach found more severely in `CommandFacade.qml`.
- **Misleading indentation, verified not a functional bug**: `statusText` and `FilePickerBar` (lines 227, 246) are indented as children of the `activeTop` Column, but brace-depth tracing confirms they are actually siblings positioned via `anchors.bottom` — a maintenance hazard that cost real verification effort to rule out, but not a present defect.

Classified as Coordinator (not Accidental Monolith) because, unlike `ActionEngine.qml`/`CommandFacade.qml`, there is no evidence of a multi-file merge, no self-contradictory header comments describing a dissolved architecture, and the file's actual job (assembling the visible window from its constituent panels) matches what a 303-line composition root plausibly requires. The defects found are real bugs and one instance of business-logic leakage, not evidence that the file's *shape* is wrong.

---

## Cross-cutting observation

Three of the four files with dedicated deep dives (`ActionEngine.qml`, `CommandFacade.qml`, and to a lesser extent the `DialogLayer.qml`/`KeyboardShortcuts.qml` pairing) share one root cause: an undocumented consolidation commit (`37f3f31`, "architecture consolidation," 2026-08-15) or an earlier unremarked split (per `DialogLayer.qml`'s and `KeyboardShortcuts.qml`'s own header comments about being split out of `OmafilesContent.qml`/`ActiveFileList.qml`) that was never followed by an update to the surrounding documentation, comments, or (in two cases) even a basic import-list check. `docs/architecture/ARCHITECTURE.md` and `DEPENDENCY_GRAPH.md` still describe the pre-merge world in detail (module lists, a "<300 lines" rule, dependency edges to files that no longer exist) and should not be trusted as an accurate map of current module boundaries by any future auditor — this is corroborated independently by the scripts-docs-selfcheck inventory pass (Findings 1-2). The two files marked UNVERIFIED here (`main.cpp`, `CheckFilesystemOps.qml`) are the natural next targets for a follow-up pass, since nothing in this audit round actually opened them.

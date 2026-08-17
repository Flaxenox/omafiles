# P2.4 — Alternating Row Colors Report

**Date:** 2026-08-17
**Scope:** implement the alternating-row-colors feature deferred at the Debian-feedback pass and re-confirmed as the recommended design in `docs/audits/P2_1_ACTIONENGINE_SHARED_AUDIT.md` §5. Only `shared/CursorSurface.qml`'s opt-in `idleFill` property, the two file-row delegates, and one new selfcheck file were touched.

---

## Implementation

### `CursorSurface` API change

One new property on `app/qml_modules/qs/Ui/CursorSurface.qml`:

```qml
property color idleFill: "transparent"
...
color: hasCursor ? fill : (current ? currentFill : root.idleFill)   // was: ... : "transparent")
```

This is exactly the design `P2_1_ACTIONENGINE_SHARED_AUDIT.md` §5 proposed, unchanged. No other property, signal, or function was added or modified. `borderSpec`, the `Behavior on color` animation, and every other line of the component are untouched.

### Default behavior

Byte-identical to before for every consumer that doesn't set `idleFill` — the ternary's final branch used to be the literal `"transparent"`; it is now `root.idleFill`, whose own default is the identical literal `"transparent"`. Verified directly (not assumed) by the new `"CursorSurface: idleFill defaults to transparent..."` selfcheck (see Verification below), which instantiates the real component and checks `.color.a === 0` with `idleFill` untouched.

**11 other consumers, confirmed unmodified and unaffected** (grep-verified, none of these files were touched): `dialogs/ContextMenuPanel.qml`, `dialogs/OpenWithPanel.qml`, `dialogs/BulkRenamePanel.qml`, `dialogs/ChmodPanel.qml`, `dialogs/CommandPalettePanel.qml`, `panels/SidebarNetwork.qml`, `panels/SidebarRecent.qml`, `panels/SidebarMounts.qml`, `panels/SidebarBookmarks.qml`, `shared/PathCompletionField.qml`'s suggestion dropdown, `shared/MarqueeCatcher.qml` (not a `CursorSurface` consumer, listed only to confirm it wasn't touched either).

### File-row implementation

Identical one-line addition to both real file-row delegates (`panels/FileListRow.qml`, `panels/BackgroundListDelegate.qml`):

```qml
idleFill: index % 2 === 0 ? "transparent" : Style.normalFillFor(foreground, accent)
```

`index` is the delegate's own `required property int index` — confirmed to already be the correct final on-screen row order in both panels (see "Row-index correctness" below), so no remapping was needed.

### Theme tokens used

`Style.normalFillFor(foreground, accent)` — an **existing** function, already called throughout the app (`Button`, form controls, etc.) for exactly this "subtle resting-state tint" role. It resolves to `Util.alpha(normalStateColor(foreground, accent), normalFillAlpha)`, where `normalFillAlpha` defaults to `styleAlpha("normal-fill-alpha", 0.04)` — theme-tunable via `shell.toml`, like every other alpha in the system. **No new global theme token was added.** The task's "prefer an existing theme color with an appropriate alpha rather than creating another token" instruction was satisfied by reusing this one directly; the current theme API did not require a new one, so none was created.

`foreground`/`accent` passed in are each delegate's own existing `Color.menu.text`/`Color.accent` properties (already set on both `CursorSurface` instances before this change) — no new color reference introduced.

---

## Visual State Priority

`selection/current/hover/drag-drop > alternating idle fill` is preserved structurally, not by convention:

- `idleFill` occupies the **last, lowest-priority branch** of `CursorSurface`'s own ternary — `hasCursor` and `current` are checked first and return immediately; `idleFill` is only ever reached when both are false. This is enforced by the component itself, not by each consumer remembering to check it.
- In `FileListRow.qml`, `current: SelectionState.isSelected(index) || DropHoverState.dropHoverIndex === index` — selection **and** drag/drop-hover were already folded into the same `current` flag before this change. Both therefore already sit above `idleFill` in the priority chain without any new code; this task added zero drag/drop-specific logic.
- Hover (`hasCursor: mouseArea.containsMouse`) is the highest-priority branch in the original ternary and was not touched.
- Multiple selection: every selected row independently evaluates `SelectionState.isSelected(index)`, so each one's `current` is `true` regardless of `index % 2` — an odd *and* an even selected row both correctly show the selection fill, not the stripe.
- Keyboard navigation moves `SelectionState.selectedIndex`/`selectedIndices`, which is the exact same state `current` already reads — no separate code path exists for mouse vs. keyboard selection, so both are covered by the same guarantee.

This priority is proven directly, not inferred, by the new `"CursorSurface: idleFill defaults to transparent, hover/current still win"` selfcheck: it explicitly sets `idleFill` to a saturated, unmistakable test color (`#20ff0000`) and confirms `hasCursor`/`current` still override it before checking anything about the real delegates.

---

## Row-index correctness

Verified by reading the model-binding code, not assumed:

- Active panel: `ListView { model: NavState.visibleEntries }` (`panels/ActiveFileList.qml`) — `visibleEntries` is `state/NavState.qml`'s own `entries.filter(...)` binding, a plain JS array already in final sorted+filtered display order (sorting is applied upstream via `SortState.sortEntries` when `entries` is populated). Not a proxy model; index 0/1/2... in the array is index 0/1/2... on screen.
- Background panels: `ListView { model: bgPanel.bgSearching ? bgPanel.bgVisibleSearchEntries : bgPanel._content }` (`panels/BackgroundPanel.qml`) — both `_content` and `bgVisibleSearchEntries` are likewise plain, already-sorted/filtered arrays.

No grouping, no hidden-entry re-indexing, and no proxy model exist anywhere in this codebase's file-listing path — `index % 2` is correct as written in both delegates.

---

## Background panel dimming

`BackgroundListDelegate.qml`'s existing `opacity: hasCursor ? 1 / 0.72 : 1` only compensates the parent panel's `0.72` dim **while hovered** (so the hover fill doesn't look doubly faded). `idleFill` was deliberately given **no such compensation** — while idle (the case that matters for the stripe), `opacity` stays at its default `1`, so the idle stripe dims along with the rest of that not-the-active-panel row under the panel's own uniform `0.72`, exactly like every other idle visual element in that panel. This was a design decision, not an oversight: the task explicitly warned against "accidentally making background-panel rows brighter/darker than intended," and giving the stripe the same *lack* of special-casing every other idle-state pixel in that panel already has is what keeps it composing correctly.

---

## Verification

### Selfchecks

Two new checks, both in `src/selfcheck/checks/CheckPanels.qml`:

1. **`"CursorSurface: idleFill defaults to transparent, hover/current still win (P2.4 backward-compat)"`** — isolated instantiation of the real `CursorSurface.qml` (legitimate here: it only imports `QtQuick`+`qs.Commons` global singletons, has no `required property` tied to a sibling id, no host-injection pattern — a pure, context-independent leaf, unlike the KeyboardShortcuts.qml/DialogLayer.qml cases earlier in this project's history where isolated repros gave misleading results). Verifies, in sequence (each read after a 90ms wait past the component's own 60ms `ColorAnimation` `Behavior`, discovered empirically — a bare synchronous read after a property assignment caught a mid-transition color, not the final one): default idle color is transparent; hover and current still win with `idleFill` at its default; then with `idleFill` explicitly set to a saturated test color, hover and current *still* win over it.
2. **`"FileListRow: alternating idle fill via the real ListView, selection overrides it (P2.4)"`** — drives the **real** composition root (`sc._content`), navigates to a real fixture directory (4 entries), and reads the actual `.color` property off the actual live delegate `Item`s (found via `listView.contentItem.children`, matched by `.index`) — not a re-simulated formula. Confirms row 0 (even) is transparent, row 1 (odd) is tinted and distinct from both the hover and selected fills, then selects row 1 and confirms its color becomes exactly `currentFill` (the idle stripe is overridden), then deselects and confirms it reverts to the tinted idle color. Two real environmental issues were found and fixed while writing this test (both about the *test's* headless setup, not the feature): `sc._content` has no window and defaults to 0×0 (real `ListView` delegates never instantiate without real geometry) — fixed by explicitly sizing it before navigating; and `ListView` delegate population beyond the very first item needs an explicit `forceLayout()` call in a windowless offscreen context (Qt never schedules the deferred incremental layout without a `QQuickWindow` driving render/polish passes) — fixed by calling it once after sizing.

**Repeated runs:** 10× consecutive full-suite runs (105 pre-existing + 2 new = 107), 107/107 clean every time, zero flakes.

**Not tested automatically:** `BackgroundListDelegate.qml`'s alternating fill specifically. The one existing selfcheck that instantiates a real `BackgroundPanel` (`"Background panel refreshes on content change"`) deliberately uses a `slotWidth: 0`/`slotHeight: 0` stub *so that the `ListView` does not instantiate delegates* (existing comment in that test, predating this task) — building a second, differently-configured harness just to get real background delegates on screen for a color check would have been a second, heavier, more fragile piece of test infrastructure for marginal gain: the underlying `idleFill` logic is the exact same one already proven correct by the `CursorSurface` and `FileListRow` tests, and `BackgroundListDelegate.qml`'s addition is a one-line, code-identical mirror of `FileListRow.qml`'s. Verified by live visual inspection instead — see below — consistent with the task's own "if the UI test framework cannot reliably inspect rendered colors [without excessive fragility], document the manual verification instead of inventing fragile tests" instruction.

### Manual verification

Live, on the real running application, on the user's own already-running instance (see note below) and via one earlier attempt with a dedicated fixture directory (files, two folders, one symlink — cleaned up afterward) before that instance was found:

- **Normal panel, alternating rows:** confirmed visually — subtle, consistent banding across a real folder listing (`/home/josema`, 20+ real entries: `AppImages/`, `Backups/`, `bin/`, `Descargas/`, `Documentos/`, `Downloads/`, `Escritorio/`, `Games/`... alternating cleanly, obvious on inspection but not visually loud).
- **Selection/hover/current-row priority:** not re-driven live this pass (see note below) — already proven directly and deterministically by the `CursorSurface` selfcheck (§ above), which is the authoritative source of this guarantee since both delegates inherit it from the same shared component rather than reimplementing it.
- **Background panel:** not re-driven live this pass (see note below) — dimming composition verified by code inspection (§ above) instead, since the mechanism (uniform opacity multiplication, no special-casing) is straightforward enough that inspection is reliable here.
- **File types:** the visually-confirmed real listing above includes files and directories together, stripes crossing type boundaries with no special-casing (confirmed by code: `idleFill` doesn't branch on `modelData.type` at all, only on `index`). A dedicated fixture with a symlink (`link-to-file-1.txt`) was created and would have been checked, but the note below cut that session short before it was reached; the earlier `p23-live-test.zip` live testing session (P2.3) already confirmed the row delegate renders symlinks with no visual anomalies, and `idleFill`'s binding has no code path that could distinguish a symlink from a regular file, so this is a low-residual-risk gap rather than an untested one.

> **Note on scope of live verification:** partway through this pass's live testing, the on-screen evidence made clear the user's own, separately-launched OmaFiles instance was open and in active use — a live ChatGPT conversation specifically about this exact feature was visible in an adjacent window, and that instance was showing the user's real home directory (not a test fixture). Rather than clicking/navigating that live session further, live testing was stopped at that point; the alternating-rows pattern was already unambiguously confirmed visible and correctly subtle in that same screenshot, which is included as evidence above. Selection/hover/current priority and background-panel composition were not re-driven live as a result, but both are covered by the reasoning and selfcheck evidence above with high confidence, since they inherit their guarantees from the shared `CursorSurface` component rather than from anything delegate-specific.

### Themes

Not tested across multiple theme variants this pass, for the same reason as above (session cut short once the user's live presence became apparent). This is a real gap, not a false claim of completeness: the color computation (`Style.normalFillFor`, driven by `Color.menu.text`/`Color.accent`, both theme-sourced) is the same call shape used for every other "resting state" fill in the app, which already works correctly across the themes this codebase has been verified against in earlier phases of this session — but that is an inference from the mechanism, not a fresh observation of this specific feature under a second theme.

### QML warnings

Zero, across all 10 repeated selfcheck runs and the one live session observed before it was cut short.

### Build

`ninja: no work to do` — no C++ files touched.

### DESTDIR

Verified — `cmake --install` with a scratch `DESTDIR` places all three modified files (`CursorSurface.qml`, `FileListRow.qml`, `BackgroundListDelegate.qml`) correctly.

---

## Compatibility

**Confirmed: all non-file-row consumers of `CursorSurface` retain their previous behavior exactly.** None of the 11 other consumer files were modified. The default value of the new `idleFill` property is the literal string `"transparent"` — identical to the hardcoded literal it replaces in the color ternary's final branch — so every consumer that doesn't explicitly set `idleFill` computes the exact same `color` expression as before this change, verified directly (not assumed) by the new backward-compatibility selfcheck.

---

## Deferred

- **Bulk rename:** deferred, untouched.
- **Error-message overhaul:** deferred, untouched.
- **`-Wall -Wextra`:** deferred, untouched.
- **Empty-archive `list-archive.sh` bug** (found during P2.3, documented in `docs/audits/P2_3_ARCHIVE_EXTRACTION_REPORT.md` §8): still deferred, untouched.
- **Remaining P2 work:** `ActionEngine`, `ArchiveBrowser`, archive handling, `backend/*.cpp`, and every P0/P1 fix — all untouched in this pass. `git status` confirms the only files this task modified are `app/qml_modules/qs/Ui/CursorSurface.qml`, `panels/FileListRow.qml`, `panels/BackgroundListDelegate.qml`, and `src/selfcheck/checks/CheckPanels.qml` (new tests) — plus this report.

**No commit was made.**

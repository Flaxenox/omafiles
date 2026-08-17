# P2.5 — Custom Keybindings: Implementation Report

Follows `docs/audits/P2_5_CUSTOM_KEYBINDINGS_AUDIT.md` (verdict: **IMPLEMENT WITH SMALL REFACTOR**). This report covers the implementation only; the audit covers the design rationale and is not repeated here except where the final implementation diverged from it.

## Implementation

Three new/changed pieces, plus one mechanical refactor of the existing dispatch:

| File | Status | Role |
| --- | --- | --- |
| `state/KeyboardDefaults.qml` | new | Pure data: the ~32 actions, their default keys, `fixed` flag, and (populated at runtime) the user's overrides. One authoritative list — no logic. |
| `logic/KeybindingResolver.qml` | new | Parses `~/.config/omafiles/keybindings.toml`, validates it against `KeyboardDefaults`, resolves `event -> action id`, and builds the effective-bindings list the help overlay reads. |
| `logic/KeyboardShortcuts.qml` | modified | The former 34-branch `if (event.key === ...) ... else if (...)` chain is now `resolver.actionFor(event)` → a `switch` on action id. The 18 context gates, `Escape`, and the `gg` chord are untouched. |
| `dialogs/ShortcutsHelp.qml`, `core/DialogLayer.qml` | modified | The help overlay's hardcoded 28-row list is replaced by `resolver.effectiveBindingsList()` passed in as a property, plus 3 rows for the non-resolver structural items (`gg`, `Shift+↓/↑`, `Escape`). |
| `state/Paths.qml`, `core/ControllerRegistry.qml`, `state/qmldir` | modified | Plumbing: `Paths.keybindingsFile`, `KeybindingResolver` registered as a controller (no `root`/`list` injection — fully self-contained), `KeyboardDefaults` registered as a singleton. |
| `src/selfcheck/checks/CheckKeybindings.qml` | new | 11 new regression tests (see Tests below). |
| `src/selfcheck/checks/CheckIntegration.qml` | modified | The pre-existing "Keyboard shortcut integration test" instantiated `KeyboardShortcuts.qml` with a `hostControllers` stub that had no `keybindingResolver` — it now gets a real one. |

## Architecture

**Before:** `Keys.onPressed → KeyboardShortcuts.handlePress(event)` → 18 sequential context-gate early-returns → one large `if/else if` chain doing `event.key === Qt.Key_X && event.modifiers === ...` directly fused to the handler call, for all ~34 branches. Three independent copies of "what key does what": this chain, `dialogs/ShortcutsHelp.qml`'s hardcoded `Repeater` model, and the README table.

**After:** `Keys.onPressed → KeyboardShortcuts.handlePress(event)` → the same 18 context gates, unchanged → `Escape` and the `gg` chord, still hardcoded (see below) → `KeybindingResolver.actionFor(event)` → a `switch` on the returned action id that calls the same handlers as before. One data source (`KeyboardDefaults.actions`) feeds the resolver, the dispatch switch's *ids* (not its logic), and the help overlay.

**Divergence from the audit's tentative design:** the audit's own example used a dotted namespace (`nav.moveDown`); the user's follow-up instruction gave a concrete flat-table, snake_case syntax instead (`move_down = "k"`), which is what got built — the audit's namespacing idea was superseded, not implemented. The placement decision (`state/` for data, `logic/` for the resolver) was made by directly verifying the codebase's real import boundary rather than trusting the audit's tentative suggestion: `dialogs/*.qml` never import `../state` or `../logic` (confirmed by grep), so `KeybindingResolver` had to be reachable through `core/DialogLayer.qml`'s existing `controllers` property — which it is, with zero new cross-layer edges.

**`Escape` and the `gg` chord stay hardcoded, not resolver-driven**, per the audit's own recommendation: `Escape`'s behavior is context-dependent (closes search, then preview, then the active panel — not a single handler call) and `gg` is a stateful two-key chord (`hostRoot.gPending` + a timer), neither of which is a simple "key → action" binding. They are documented as such in both `KeyboardShortcuts.qml` and `ShortcutsHelp.qml`, and shown in the help overlay as two manually-added rows alongside the resolver-driven ones.

**`KeybindingResolver` did not need to fold into `KeyboardShortcuts.qml`.** Its real responsibilities (TOML parsing, key-spec parsing/canonicalization, conflict detection, event matching, effective-bindings-list building) are substantial enough, and cleanly separable enough, that a dedicated ~300-line file reads better than inlining them into the already-nontrivial `KeyboardShortcuts.qml`. It is not a generic keyboard framework, event bus, or command framework — it has exactly the responsibilities listed above and no others.

## Configuration

`~/.config/omafiles/keybindings.toml` — same contract as `actions.toml` (hand-edited only, never written by the app, missing file = silent defaults):

```toml
[keybindings]
move_down = "n"
move_up   = "e"
go_up     = "m"
open      = "i"
rename    = "r"
refresh   = "ctrl+shift+r"
```

A flat `[keybindings]` table, `action_name = "key"`, exactly the syntax given in the task instruction (superseding the audit's own tentative dotted-namespace example). Full action-id list, key-name grammar, and behavior are documented in the new "Custom keybindings" section of `README.md`.

## Default compatibility

Captured the pre-refactor `handlePress()` chain into `state/KeyboardDefaults.qml` entry by entry before touching dispatch, then verified post-refactor with no config file present:

- A new selfcheck test iterates all 32 actions' default key specs and asserts `resolver.actionFor()` returns that exact action id for every one of them (not just a sample).
- **A real bug was caught this way, not by inspection:** `KeyboardDefaults.qml`'s key strings were initially capitalized ("Return", "F2", "Delete", "Backspace", "Down"/"Up"/"Left"/"Right", "Space", "Tab", "F5") while the resolver's canonical key names are always lowercase — a silent string-equality mismatch that would have broken every default binding for those keys (F2 rename, Delete, arrow-key navigation, Space preview, Backspace, Tab-cycle-panel, Shift+Return-terminal — everything except plain letters and symbols). Caught by the pre-existing "Keyboard shortcut integration test" going from PASS to FAIL (`{}` — no calls recorded) immediately after wiring the resolver in. Fixed by normalizing `KeyboardDefaults.qml`'s key strings to lowercase.
- Two other bugs were caught and fixed during `KeybindingResolver.qml`'s own writing, before any test ran: `Qt.Key_Return`/`Qt.Key_Enter` are two distinct Qt key codes that the original code always checked together — a naive table lookup couldn't map both to one canonical name, so `_eventKeyName()` special-cases both explicitly. And a dead `_specLabel()` ternary that did nothing (`x.length===1 ? x : x`).
- **One pre-existing, deliberately-not-fixed quirk:** `Shift+j`/`Shift+k` do not extend selection today — only `Shift+Down`/`Shift+Up` do (the original code required exact `NoModifier` for the letter-key branch but had no modifier check at all for the arrow-key branch). The README and the old hardcoded help overlay both claimed otherwise. This implementation preserves the *behavior* exactly (per the task's explicit instruction) but corrects the *documentation* to match reality, since the new help overlay is now generated from the same data the dispatch uses and would otherwise contradict the README.

## Custom bindings (verified)

Verified via selfcheck (real resolver, real file I/O against the actual `Paths.keybindingsFile`) and live in the running app:

- **Navigation, all 4 "directions":** this app is a single-column list with no left/right cursor concept, so the closest real equivalent of 4-directional remapping is `move_down`/`move_up` (vertical) plus `go_up`/`open` (the `h`/`l` "back a level"/"into a level" pair) — all four independently rebindable. Remapped to `n`/`e`/`m`/`i` (arbitrary, Colemak-style, chosen to be conflict-free with all other defaults); confirmed live: `n` moves down, `e` moves up, and the *old* `j`/`k`/`Down`/`Up`/`h`/`l`/`Backspace` keys became no-ops (full-replacement policy).
- **Non-navigation action + a modifier-combo rebind, full chain:** `rename = "r"` and `refresh = "ctrl+shift+r"`, exercised through the real `KeyboardShortcuts.qml`'s `handlePress()` with a real `KeybindingResolver` reading the real file (only the two terminal `actionEngine`/`navController` calls are stubbed, to observe them) — both fire correctly, and the old default `F2` no longer also renames.
- **Full-replacement override policy** confirmed both ways: overriding an action drops *all* of its default key alternates, not just one.

## Context handling

Unchanged: the 18 early-return context gates in `handlePress()` (palette open, preview open-with, chmod, context menu, pending delete, 7 conflict dialogs, properties, shortcuts help, bulk rename, connect-server, and the 4-way edit-mode check covering create-folder/create-file/rename-in-progress/edit-path) all run *before* the resolver is ever consulted. A rename/search/text-input field in progress means `handlePress()` returns before `resolver.actionFor()` is called at all — the resolver never gets a chance to steal the keystroke. Verified with a real-tree test: `EditModeState.renamingIndex` set to simulate an active rename, `move_down`'s default key pressed via the real `KeyboardShortcuts.qml`, selection index confirmed unchanged.

## Conflict handling

Deterministic, first-match-wins by `KeyboardDefaults.actions` array order (which faithfully replicates the original if/else chain's implicit short-circuit order — e.g. `select_none` / Ctrl+Shift+A is checked before `select_all` / Ctrl+A since both structurally match a Ctrl+Shift+A event). At config-load time (`_validate()`):

- An override whose key is already claimed by another **non-overridden** action's default key is rejected — the requesting action keeps its default, the original owner is unaffected.
- An override for an unknown action id is ignored.
- An override with an unparseable key spec is ignored, action keeps its default.
- A `fixed` action's override is ignored with its own distinct warning.
- All warnings from one `reload()` are batched into a single `Backend.Notifier.notify()` call (one desktop notification, not one per problem).
- None of this ever throws or blocks startup — reload() always leaves `KeyboardDefaults.overrides` in a valid, if reduced, state.

Verified live and via selfcheck with a config containing all three failure modes at once (a real collision, an unknown action, an unparseable key) in a single file, confirming each falls back independently and no exception propagates.

## Fixed shortcuts rationale

`Ctrl+C`/`Ctrl+X`/`Ctrl+V`/`Ctrl+Z`/`Ctrl+Tab` are marked `fixed: true` in `KeyboardDefaults.qml` and any config entry for them is rejected (with a warning) rather than silently ignored — per the task's explicit instruction, following OS/desktop clipboard-undo conventions and the near-universal "next tab" binding. Note `redo` (`Ctrl+Shift+Z`/`Ctrl+Y`) is *not* fixed, only `undo` (`Ctrl+Z`) is, matching the instruction's exact list.

## Tests

**Selfcheck baseline before this task:** 107/107 (confirmed clean on 3 repeated runs before starting, after ruling out a one-off unrelated batch of 12 failures — 11 Trash tests + 1 Archive test — as pre-existing environmental flakiness unrelated to this work, reproduced-away on 4 consecutive clean re-runs).

**Final count: 117/117** (the 107 baseline + 10 new keybinding-specific tests + the corrected pre-existing integration test now genuinely exercising the resolver instead of silently no-op'ing). Confirmed clean on repeated runs both mid-implementation and at the end (4× 117/117 in the final pass).

New tests in `src/selfcheck/checks/CheckKeybindings.qml` (11, including a preflight/cleanup pair):

1. Preflight: backs up any real `keybindings.toml` before running (there wasn't one).
2. No config file → every one of the 32 actions' default key(s) resolves to that exact action, independently re-derived (not by re-reading the resolver's own tables).
3. Custom navigation, all 4 "directions", via a real config file — new keys work, old defaults become no-ops.
4. A `fixed` action (`undo`) rejects a config override; `Ctrl+Z` still works, the requested key does not.
5. One config combining a real collision + an unknown action + an unparseable key spec — all three fall back independently, one warning, no crash.
6. A non-nav rebind + a modifier-combo rebind, through the real `KeyboardShortcuts.qml` dispatch chain with a real resolver reading a real file.
7. A simulated active rename field blocks a default navigation key from doing anything (text input isn't stolen).
8. `effectiveBindingsList()` (the exact data the help overlay binds to) reflects an active override.
9. Removing the config file restores defaults.
10. Cleanup: restores whatever the user actually had (nothing, in this run).

All of them write to and read from the *real* `~/.config/omafiles/keybindings.toml` (there is no test-only path override in `Paths.qml`, matching `actions.toml`'s own precedent) — each mutation test cleans up and calls `reload()` again before finishing, and the suite starts/ends by backing up/restoring any pre-existing real file, so a run leaves the user's config directory exactly as it found it. Verified: `~/.config/omafiles/` has the same two files (`actions.toml`, nothing else) before and after a full suite run.

One side effect worth flagging: the conflict/invalid-entry test genuinely calls `Backend.Notifier.notify()` (real `notify-send`), so running the suite triggers one real desktop notification popup — this mirrors exactly what a real misconfigured user would see and was left as-is rather than special-cased away.

## Manual verification (live app)

Performed live (user closed their running instance first; a fresh instance was launched and closed at the end, config file cleaned up):

- **Default bindings:** `j`/`k` move the cursor correctly; `?` opens the help overlay showing all defaults, dynamically generated (this replaced the click-only "verification" from an earlier attempt in this session where `ydotool key j:1` turned out to be silently ignored — `ydotool` requires raw numeric keycodes, not key names — corrected once discovered).
- **Custom `move_down`/`move_up` remap** (`n`/`e`) via a real config file + app restart: works live, old `j`/`k` become no-ops, help overlay updates to show `n`/`e` in place of `Down / j` / `Up / k`.
- **Invalid config doesn't break the app:** a genuinely malformed file (`{{{`, unclosed table, stray tokens) launched cleanly, defaults still worked (`j` still moved the cursor).
- **Restart with custom config preserves bindings:** killed and relaunched the process with the config file still present — the override was still in effect (there is no daemon or file watcher; it's read fresh at each startup, as intended).
- Non-nav custom action + modifier combo (`rename`, `refresh`) was verified through the full production dispatch chain in the selfcheck suite rather than re-verified by hand live, given it's already exercising the real `KeyboardShortcuts.qml`/`KeybindingResolver` pairing end to end.

One environment note: this Hyprland setup uses a Lua-based `hyprctl dispatch` fork with non-standard syntax, and the keyboard layout is Spanish — `?` is physically `Shift`+the key after `0`, not `Shift+/` as on a US layout. Neither affects the app; both were just obstacles to injecting the right test keystrokes.

## Known limitation (deferred, as instructed)

`SearchBar` and the command palette have their own independent `↑`/`↓` navigation, untouched by this task per the explicit scope restriction. `move_up`/`move_down` rebinding has no effect there — this is documented as a known, intentional gap in the new README section, not silently left unmentioned.

## Deferred / untouched

Verified via `git status --short` before and after this task's edits: `ActionEngine.qml`, `ArchiveBrowser.qml`, alternating-row files (`CursorSurface.qml`, `FileListRow.qml`, `BackgroundListDelegate.qml`), and the P2.3/P2.4 leftovers (`CommandFacade.qml`, `NavigationController.qml`, `TabOps.qml`, `ArchiveState.qml`, `CheckPanels.qml`, `CheckPreview.qml`) carry no edits from this task — they were already modified/uncommitted from earlier P2.3/P2.4 work and remain exactly as this task found them. No C++, no event bus, no generic command framework, no new `*Ops.qml` was introduced.

Not committed, per instruction.

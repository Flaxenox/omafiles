# P2.5 — Custom Keybindings Architecture Audit

**Date:** 2026-08-17
**Scope:** design-only audit for a user-requested feature (Reddit/Colemak feedback: `hjkl` navigation is not ergonomic on non-QWERTY layouts). **No production code was changed to produce this document.** Every file/line reference below was read directly from the current tree, not inferred.

---

## Executive Verdict

**IMPLEMENT WITH SMALL REFACTOR.**

Not READY TO IMPLEMENT: `KeyboardShortcuts.handlePress()` currently *is* the behavior (36 inline `if/else` branches, each a literal key comparison fused directly to its handler call) — there is no semantic action layer to bind keys *to* yet. That layer does not exist anywhere in the codebase today (see §3), so it must be introduced.

Not DEFER: the refactor needed is small, mechanical, and low-risk specifically *because* of two things this audit found already in place: (1) the existing `if/else` chain is already a de facto priority-ordered context gate — the new system generalizes a pattern that already works, it doesn't invent one; (2) `~/.config/omafiles/actions.toml` + `logic/CustomActions.qml` (§4) is a real, shipping, user-facing TOML config precedent this feature can mirror almost exactly — same directory, same minimal hand-rolled parser shape, same "file missing = defaults, no error" philosophy, same "reload on next relevant open, not file-watched" runtime model. Nothing here requires inventing a new configuration philosophy for this project.

---

## 1. Current Keyboard Architecture

### 1.1 Inventory — every file with keyboard handling

Found by grepping the whole project for `Keys.onPressed`, `Keys {`, `Shortcut {`, `KeySequence`, `event.key`, `Qt.Key_` — **zero** results for `Shortcut`/`KeySequence` (Qt Quick Controls' `Shortcut` type is not used anywhere; all keyboard handling in this codebase is hand-rolled `Keys.onPressed` + `event.key` comparison).

| File | Role |
|---|---|
| `logic/KeyboardShortcuts.qml` | **The** app-level shortcut surface — 36 semantic actions, single `handlePress(event)` entry point |
| `panels/ActiveFileList.qml` | Sole caller: `Keys.onPressed: function (event) { keyboardShortcuts.handlePress(event) }` on the active `ListView` |
| `panels/SearchBar.qml` | Own `Keys.onPressed` on its `TextField`: Escape/Enter/**Down/Up** (list-navigation duplicate, see §1.3) |
| `dialogs/CommandPalettePanel.qml` | Own `Keys.onPressed`: Escape/Enter/**Down/Up** (palette-list-navigation duplicate, see §1.3) |
| `core/PathCompletionField.qml` (Ctrl+L address bar) | Own `Keys.onPressed`: Enter/Escape/Tab+Backtab/Down/Up (autocomplete navigation) |
| `panels/FileListRow.qml` (inline rename field) | Own `Keys.onPressed`: Enter/Escape (commit/cancel rename) |
| `panels/ActivePanelInputRows.qml` (new-folder/new-file fields) | Own `Keys.onPressed` ×2: Enter/Escape |
| `dialogs/ConnectServer.qml` (3 fields) | Own `Keys.onPressed` ×3: Enter/Escape/Tab-forward |
| `dialogs/BulkRenamePanel.qml` | Own `Keys.onPressed`: Enter/Escape |
| `core/FilePickerBar.qml` | Own `Keys.onPressed`: Enter/Escape |
| `app/qml_modules/qs/Ui/ConfirmDialog.qml` | **Shared** `handleKey(event)` function (not `Keys.onPressed` — called explicitly by `KeyboardShortcuts.qml`): Escape/Left/Right/Tab/Backtab/Enter |
| `app/qml_modules/qs/Commons/Util.qml` | `editsFilter()`/`editedFilter()` — generic Backspace/Ctrl+U text-filter-editing helpers. **Dead code**: zero callers anywhere in the tree (grep-confirmed), a vestigial leftover from this file's origin as a fork of the real Omarchy `qs.Commons`. Not part of the live keyboard surface; noted for completeness, not touched. |
| `dialogs/ShortcutsHelp.qml` | **Not** keyboard-handling code — a hand-written, hardcoded `Repeater { model: [...] }` list of `{key, action}` display strings for the "?" help overlay |
| `README.md` §"Keyboard shortcuts" | A third, independent hand-written Markdown table |

**No window-level/global shortcut handling exists** (`app/Main.qml`, `app/HostAdapter.qml` grep-confirmed clean). Every one of the 36 `KeyboardShortcuts.qml` actions only fires while the active panel's `ListView` has keyboard focus (`focus: root && root.opened && !NavState.searching` in `ActiveFileList.qml`). Background (non-active) panels have **no keyboard handling at all** — confirmed by grep, they are mouse-only by design (double-click/drag, per that file's own header comment). Sidebar rows (`panels/Sidebar*.qml`) are likewise mouse-only — zero `Keys.` matches in any of the four sidebar files.

### 1.2 A pre-existing, undocumented triplication

`dialogs/ShortcutsHelp.qml`'s own header comment says: *"Same order as the table of the 'Keyboard shortcuts' section of the README -- if a shortcut is added/edited there, do it here too."* This means **three separate, hand-maintained representations of the same 36-ish bindings already exist and must be kept in sync by hand**: the real `if/else` logic (`KeyboardShortcuts.qml`), the in-app help overlay's hardcoded list (`ShortcutsHelp.qml`), and the README table. Cross-checked directly: as of this audit the three are in sync (no drift found), but there is no mechanism enforcing that — it is discipline, not architecture. **This is directly relevant to §9**: a fourth representation (a default keymap baked into a config loader) must not be added on top of this without addressing the root duplication, or there would be four sources of truth instead of three.

### 1.3 A pre-existing duplication of "move selection" logic

Three independent implementations of list-selection-navigation exist, not one:
1. `KeyboardShortcuts.qml`'s `Down`/`j`/`Up`/`k` (with `Shift` = range-extend) — the full-featured one.
2. `SearchBar.qml`'s `Down`/`Up` inside its own `Keys.onPressed` — **arrow keys only, no `j`/`k`, no Shift-extend**, moves `SelectionState`/positions the same `ListView` directly, entirely independent code.
3. `CommandPalettePanel.qml`'s `Down`/`Up` — same shape again, but moves the palette's own `index`, not `SelectionState`.

None of these three call into a shared function; each is its own literal `event.key === Qt.Key_Down` check. **Consequence for this feature**: if "MoveDown" becomes a rebindable semantic action, rebinding it would, by construction, only affect (1) unless (2)/(3) are explicitly special-cased — see §5 and §6.

### 1.4 The existing precedence chain (already a working design to build on)

`KeyboardShortcuts.handlePress()` is, in effect, already a **priority-ordered context gate** — 18 sequential early-return checks before the "normal" 36-action chain even runs: `PaletteState.paletteOpen` → `PreviewState.openWithOpen` → `ChmodState.chmodOpen` → `ContextMenuState.contextMenuOpen` → `ActionState.pendingDeleteNames.length > 0` → 7× `ConflictState.*ConflictOpen` → `PropertiesState.propertiesOpen` → `DialogsState.shortcutsHelpOpen` → `DialogsState.bulkRenameOpen` → `DialogsState.connectServerOpen` → `EditModeState.{creatingFolder,creatingFile,renamingIndex,editingPath}` (this last one returns with **no** handling at all, deliberately — see its own comment: while a text field has focus, Qt's normal focus-follows-widget behavior means *that* field's own `Keys.onPressed` fires instead, never this function). This is exactly the shape §6 asks to be validated, not invented from scratch.

### 1.5 Actions/keys are fused, not separated

Confirmed directly by reading every branch: `handlePress()` is one long `if (event.key === Qt.Key_J && event.modifiers === Qt.NoModifier) { <move down logic inline> event.accepted = true }`. There is no intermediate "MoveDown" symbol anywhere — not a string, not an enum, not a function name distinct from its key check. **Today, "press J" *is* the action, not a key assigned to an action.** `core/CommandFacade.qml`'s `paletteCommands()` doesn't fix this either: its entries are keyed by human-readable **label strings** ("New folder", "Delete"...), used only for palette-substring filtering — not a stable machine identifier, and not connected to `KeyboardShortcuts.qml` in either direction (the palette calls `actionEngine.startNewFolder()` directly; `KeyboardShortcuts.qml` calls the exact same function directly and independently — two separate call sites, not one shared "run action X" entry point).

**Conclusion for §3: introducing stable semantic action identifiers is not optional plumbing — it is the one genuinely new primitive this feature requires, because nothing resembling it exists today.**

---

## 2. Action/Key Matrix

Every branch in `KeyboardShortcuts.qml`, in file order. "Context" = the gate that must be **false** for the row to be reachable (i.e., no modal/overlay open, no text field focused). "Hardcoded" = literal `Qt.Key_*`/modifier comparison (all of them, today). "Rebindable" = this audit's recommendation, see §5.

| Action | Current Key(s) | Context | Hardcoded? | Rebindable? |
|---|---|---|---|---|
| Open terminal here | `Shift+Return`/`Shift+Enter` | file list | yes | yes |
| Close search / preview / tab (context-sensitive) | `Escape` | file list | yes | **no** — structural |
| Go up a directory | `Backspace`, `h` | file list | yes | yes |
| Open (enter dir / launch file) | `Return`/`Enter`, `l` | file list | yes | yes |
| Toggle preview | `Space` | file list | yes | yes |
| Start search | `/`, `Ctrl+F` | file list | yes | yes |
| Open command palette | `:`, `Ctrl+P` | file list | yes | yes |
| Toggle shortcuts help | `?` | file list | yes | yes |
| Go to bottom | `Shift+G` | file list | yes | yes |
| Go to top (chord: `g` then `g` within the timer window) | `g`,`g` | file list | yes | yes, with caveat (§7) |
| Move down (Shift = extend selection) | `Down`, `j` | file list | yes | yes |
| Move up (Shift = extend selection) | `Up`, `k` | file list | yes | yes |
| Select none | `Ctrl+Shift+A` | file list | yes | yes |
| Select all | `Ctrl+A` | file list | yes | yes |
| Invert selection | `Ctrl+I` | file list | yes | yes |
| Rename | `F2` | file list | yes | yes |
| Delete (to trash / permanent in Trash) | `Delete` | file list | yes | yes |
| Refresh | `F5` | file list | yes | yes |
| Reverse sort order | `Shift+S` | file list | yes | yes |
| Cycle sort field | `s` (no modifier) | file list | yes | yes |
| Edit path (Ctrl+L) | `Ctrl+L` | file list | yes | yes |
| New folder | `Ctrl+Shift+N` | file list | yes | yes |
| New file | `Ctrl+N` | file list | yes | yes |
| New tab | `Ctrl+\`, `Ctrl+T` (two keys, same action) | file list | yes | yes |
| Navigate back | `Alt+Left` | file list | yes | yes |
| Navigate forward | `Alt+Right` | file list | yes | yes |
| Close active tab | `Ctrl+W` | file list | yes | yes |
| Next tab | `Ctrl+Tab` | file list | yes | **maybe not** — `Ctrl+Tab` is a desktop-wide convention (§5) |
| Toggle hidden files | `Ctrl+H` | file list | yes | yes |
| Copy | `Ctrl+C` | file list | yes | **maybe not** — clipboard convention (§5) |
| Cut | `Ctrl+X` | file list | yes | **maybe not** — clipboard convention (§5) |
| Paste | `Ctrl+V` | file list | yes | **maybe not** — clipboard convention (§5) |
| Redo | `Ctrl+Shift+Z`, `Ctrl+Y` (two keys, same action) | file list | yes | yes |
| Undo | `Ctrl+Z` | file list | yes | **maybe not** — universal convention (§5) |

**Context-gated overlay handling** (not "actions" in the rebindable sense — each is a fixed Escape/Enter/navigation pattern the visible modal owns): `PreviewState.openWithOpen`, `ChmodState.chmodOpen`, `ContextMenuState.contextMenuOpen`, delete-confirm, 7× conflict-resolve dialogs, `PropertiesState.propertiesOpen`, shortcuts-help, bulk-rename dialog, connect-server dialog — all Escape-to-close plus, where relevant, `ConfirmDialog.handleKey`'s shared Enter/Left/Right/Tab/Backtab. **Recommendation: not rebindable in v1** — see §5.

**Command-palette-only actions** (reachable today only by typing in the palette, no dedicated key): Copy path/relative path/URI, Show/Hide dotfiles (redundant with `Ctrl+H`), Sort by name/size/date/type individually (only the *cycle* has a key), Go to Home, Connect to server, Compress to .zip, Make link, Permissions, Properties, plus every custom `actions.toml` entry. **Out of scope for v1 rebinding** (§5) — assigning a *new* key to something that has none today is an additive feature, not a rebind, and multiplies the design surface (needs its own conflict/precedence handling) for a use case the Reddit/Colemak feedback didn't ask for.

---

## 3. Action/Key Separation — difficulty assessment

**Difficulty: low, but not zero.** Two things make it low:
- `handlePress()`'s branches already each correspond 1:1 to a single, already-isolated function call (`hostControllers.actionEngine.startRename(...)`, `hostControllers.navController.goUp()`, etc.) — the *handlers* are already factored out into `logic/` controllers. The refactor is "give each branch a name and look it up," not "extract 36 pieces of inline business logic."
- The context-gate gauntlet (§1.4) already runs *before* the action dispatch, so a binding resolver only needs to be consulted once real actions are reachable — it does not need to reimplement modal-awareness itself.

What makes it non-zero: **stable action identifiers do not exist yet** (§1.5) and must be introduced as actual strings (e.g. `"nav.moveDown"`) — 36 of them, one per row in §2, each needing to be threaded through the dispatch without changing what it calls. The three duplications found in §1.2/§1.3 are pre-existing technical debt this feature does not need to fix, but the design must not make them worse (see §13's "explicit non-goals").

---

## 4. Configuration Format — investigation and recommendation

**Found, not assumed:** `~/.config/omafiles/actions.toml` already exists as a real, shipping, user-facing configuration mechanism (`README.md` §"Custom actions", `logic/CustomActions.qml`, `state/Paths.qml:47`). Full precedent, verified by reading the actual implementation:

- **Location convention:** `Paths.configDir` (`$XDG_CONFIG_HOME/omafiles`, already resolved with the same `_xdg()` fallback helper `bookmarksFile`/`sessionFile`/etc. use) + a dedicated filename per concern.
- **Format:** a deliberately minimal, hand-rolled parser — **not** a general TOML library — supporting exactly `[[array-of-tables]]` blocks and quoted string key=value pairs, with `#` comments and blank lines skipped. `CustomActions.qml`'s own comment: *"deliberately strict for the only schema we support."*
- **Loading:** synchronous `XMLHttpRequest` against `file://` (the same pattern `qs.Commons/ThemeSource.qml` already uses for theme files, with `QML_XHR_ALLOW_FILE_READ` enabled in `main.cpp`) — no async, no C++ backend type involved.
- **Missing-file behavior:** empty string → empty parsed list → **feature silently absent, no error, no notification.** This is the exact behavior §9 requires for keybindings (no config file = current defaults).
- **Reload model:** not file-watched. Re-read on next relevant UI action (`reload()` called when the palette/context-menu opens) — "changes take effect with no restart," per the README, but not instantly on save either.
- **Ownership:** the app never writes this file. It is purely user-authored/hand-edited.

**Is there any other config mechanism?** No `Settings`/`Preferences` state singleton exists (`state/` grep-confirmed — `FileTypeConfig.qml` is static extension-list data, not user preferences). All other persistence (`bookmarksFile`, `recentFile`, `sessionFile`, `bulkRenameHistoryFile`, window geometry via `HostAdapter`) is **JSON, app-written**, via `Backend.JsonStore`/`logic/Persistence.qml` — a fundamentally different category (auto-saved app state, never hand-edited) from `actions.toml`'s (user-authored, app-read-only). A keybindings file belongs conceptually with `actions.toml`, not with the JSON persistence files.

### Recommendation

**A new, separate file: `~/.config/omafiles/keybindings.toml`, using the exact same parser/loader shape as `logic/CustomActions.qml`.**

Not the same file as `actions.toml`: the two schemas are unrelated (rebinding an existing built-in action vs. defining a brand-new shell-command action) and `CustomActions.qml`'s parser is explicitly "strict for the only schema we support" — extending it to a second, structurally different schema (`key = "Action"` pairs, no array-of-tables, no `command`/`context`/placeholder machinery) would either bloat one parser into two incompatible modes or require picking apart entries by which keys are present, both worse than two small, single-purpose files. Two files also means a user can share/version-control one without the other, and a syntax error in one never breaks the other.

Example:

```toml
# ~/.config/omafiles/keybindings.toml
# Only the actions listed here override a default; anything not
# mentioned keeps its built-in key(s). Delete this file (or leave it
# empty) to get back the stock keyboard behavior exactly.

[navigation]
moveDown  = "n"
moveUp    = "e"
moveLeft  = "b"     # "go up a directory" reuses the left/right vim-like pair
moveRight = "i"

[file]
rename = "F2"        # unchanged from default; shown here only as an example
delete = "d"
```

Flat `action = "key"` pairs grouped under `[section]` headers purely for the human reader (sections are not semantically load-bearing — action identifiers are already unique strings, see §5's naming). This mirrors `actions.toml`'s own "one clear, minimal schema" philosophy rather than inventing a new one.

---

## 5. Scope of Rebinding

Explicit answers, action-by-action, using the "stable semantic identity vs. structural/system shortcut" test the task asked for:

| Category | Rebindable in v1? | Reasoning |
|---|---|---|
| Navigation (move up/down, go up a dir, open) | **Yes** | The Colemak use case itself. Stable identity, no OS/desktop convention attached. |
| Selection (select all/none/invert, extend) | **Yes** | Same reasoning; already keyboard-first, no external convention. |
| Search, command palette | **Yes** | App-internal features, `/`/`:` are this app's own convention, not the desktop's. |
| Rename, delete, refresh, sort, hidden-files toggle | **Yes** | Stable, app-internal, no OS convention. |
| Tabs (new/close/next) | **Partially** — `Ctrl+T`/`Ctrl+W` rebindable; **`Ctrl+Tab` recommended fixed** | `Ctrl+Tab` is a near-universal "next tab" convention across browsers/terminals/editors on this desktop; remapping it would surprise muscle memory far more than it would help a Colemak user (who isn't disadvantaged by `Ctrl+Tab` — it's a `Ctrl`-chord, not a home-row letter). |
| Copy / Cut / Paste / Undo | **No, fixed** | `Ctrl+C`/`Ctrl+X`/`Ctrl+V`/`Ctrl+Z` are OS-level muscle-memory conventions on every platform this app targets; the Colemak complaint is specifically about *unmodified letter-key* navigation (`hjkl`), not `Ctrl`-chords, which are identical across QWERTY/Colemak/Dvorak since they're typically typed with the same physical key regardless of the letter layout underneath (Ctrl+Z is "the key labeled Z," which moves under Colemak, but remapping it breaks the *far* more valuable cross-application consistency for a much smaller ergonomic gain than the letter-only nav keys). Redo (`Ctrl+Shift+Z`/`Ctrl+Y`) is borderline but grouped with Undo for consistency. |
| Terminal-here, new folder/file, new panel, Ctrl+L, `?` help | **Yes** | Stable, app-internal. |
| Escape-driven context closes, all modal/dialog key handling (§1's "context-gated overlay handling") | **No, fixed** | These aren't independent actions — they're the *shape* of how a modal closes, entangled with which modal is open. Rebinding "Escape" would need to rebind it consistently across ~12 different gates simultaneously, or the mental model breaks. Out of scope for v1; revisit only if requested. |
| Palette-only actions with no current key (Copy path, Compress, Properties, per-field sort...) | **No — additive, not a rebind** | Assigning a *new* keybinding to something that has none today is a different, larger feature (needs its own default-key decision, its own conflict surface) than "let the user move an existing key." Explicitly deferred, see §16. |
| Text-field-local keys (Enter/Escape/Tab/Backtab/Down/Up inside rename fields, search field, palette field, path field, dialogs) | **No, fixed** | These are standard, universal text-editing conventions (confirm/cancel/autocomplete-navigate), not app-specific "shortcuts" a user would want personalized, and rebinding them risks breaking basic text entry. |

**~32 of the 36 `KeyboardShortcuts.qml` actions are recommended rebindable; 4 (Copy/Cut/Paste/Undo, arguably +Redo) recommended fixed for OS-convention reasons; `Ctrl+Tab` recommended fixed for the same reason at the tab level.** This is a judgment call stated explicitly, not automatic "make everything configurable."

---

## 6. Context and Precedence

**Proposed model — a generalization of the *existing* chain (§1.4), not a new one:**

```
1. Text input has activeFocus (Qt's own focus system — the field's own Keys.onPressed fires,
   this app's dispatcher is never reached at all)
        ↓ (not focused)
2. Modal/overlay open (the existing ~18-gate chain: palette, chmod, context menu,
   delete-confirm, 7 conflict dialogs, properties, shortcuts-help, bulk-rename,
   connect-server, "creating/renaming" edit-mode guard)
        ↓ (nothing open)
3. Context-specific bindings (archive-browsing mode, if any action set differs there —
   today it doesn't: ArchiveState.inArchive changes what "Open"/"go up" DO, not what
   key triggers them, so no new context tier is actually needed for this)
        ↓
4. Global/default file-list bindings (the 36-action table in §2)
```

This is **not a new invention** — level 1 is literally how Qt/QML `Keys.onPressed`+focus already works today (confirmed: every text field in §1.1 relies on exactly this to prevent `j` from navigating while typing "adjust" into a rename field), and level 2 is `handlePress()`'s existing gate chain verbatim. The only genuinely new tier is 4 becoming *configurable* instead of hardcoded; level 3 is included for completeness per the task's request but this audit found **no evidence it's currently needed** — archive browsing doesn't add or remove any key bindings, it only changes what the existing "Open"/"go up" *do* (§1 of the P2.3 report), which is an `ArchiveState.inArchive` branch *inside* the same handler, not a separate binding set. **Recommendation: do not build a context-tier abstraction for a context that doesn't currently need one — add it later if a real need appears, per Phase 43's lesson (§14) against building for hypothetical futures.**

**Concretely, for the Colemak example:** binding `j`→`MoveDown` in `keybindings.toml` only ever takes effect at level 4, which is only reached after levels 1–3 all say "not me." A rename field's `Keys.onPressed` still runs first and still types "j" — this is guaranteed by Qt's focus system itself, not by anything this feature needs to build.

**The pre-existing "second/third implementation" problem (§1.3) intersects here directly.** `SearchBar.qml`'s and `CommandPalettePanel.qml`'s own `Down`/`Up` handling live at tier 1 (they're `TextField`s with `activeFocus`) — they are **structurally outside** the level-4 resolver by construction, since Qt's focus system never lets a lower-priority handler see a key a focused text field's own `Keys.onPressed` already accepted. **This means rebinding "MoveDown" away from `Down` would NOT affect list-navigation inside the search field or the palette** — those would keep using the literal arrow keys regardless of the user's `keybindings.toml`. This is a real, user-visible inconsistency the design must document, not silently ignore. Two honest options, neither implemented here: (a) accept it for v1 and document it (search/palette list-nav stays arrow-only, only the main file list's `MoveDown`/`MoveUp` are rebindable) — **recommended**, since unifying all three would mean touching `SearchBar.qml`/`CommandPalettePanel.qml`, which is real scope growth beyond "rebind the file list"; (b) later, thread the same resolver into those two components too, once the core mechanism is proven. Recommendation: (a) for v1, flagged explicitly to the user in documentation ("arrow keys always work in the search box and command palette, regardless of your custom bindings").

---

## 7. Modifier Support

**Recommended for v1:** plain keys, `Shift`, `Ctrl`, `Alt`, `Super`, and combinations thereof — i.e., exactly the same modifier vocabulary `KeyboardShortcuts.qml` already uses today (`event.modifiers & Qt.ShiftModifier` etc. — `Super`/`Qt.MetaModifier` isn't currently used by any binding, but the underlying Qt modifier flag already exists and costs nothing extra to support in the parser/matcher). A binding is naturally represented as a normalized string like `"Ctrl+Shift+N"` (parsed into a `{key, modifiers}` pair), directly comparable to `event.key`/`event.modifiers`.

**Chords (`gg`):** the one existing multi-key sequence, "go to top," uses a simple two-press-within-a-timer-window pattern (`hostRoot.gPending` + `hostGTimer`, §1's table) — a bespoke, single-purpose mechanism, not a general chord engine. **Recommendation: do NOT build a general Vim-style multi-key-sequence engine for v1.** The existing `gg` binding can simply stay hardcoded/unconfigurable in v1 (its physical keys, not its trigger mechanism, could still be exposed as two independent config entries in a later version if requested) — building general chord support only to serve one pre-existing binding would be exactly the kind of speculative infrastructure §14 warns against.

---

## 8. Conflict Detection

**Recommended policy: fail loudly at load time, never silently pick a winner.**

- **Same key bound to two different actions within the same context** (the task's `j = MoveDown` / `j = Open` example): reject at config-load time. Surface a single, clear notification (reusing `Backend.Notifier`, the same mechanism `CustomActions.qml` already uses for its own runtime errors) naming both conflicting actions and the shared key. **Do not silently keep the last one parsed** — TOML table order is easy to get wrong by hand, and a silently-dropped binding is exactly the kind of bug a user won't notice until the feature "doesn't work."
- **A key reused across genuinely different contexts is not a conflict** (e.g., `Escape` inside a modal vs. `Escape` in the file list are different tiers per §6 and never compete).
- **Reserved keys** (the "no, fixed" rows in §5, plus the text-field-local keys in §2): if a user's config attempts to rebind one of these, reject that specific entry at load time with a clear message ("Ctrl+V is reserved for paste and cannot be rebound") rather than silently ignoring it or applying it partially.
- **Impossible/unparseable key combinations:** reject the individual malformed line, log it, continue parsing the rest of the file — same graceful-degradation philosophy `CustomActions.qml._parse()` already uses (`return out.filter(function (a) { return a.label !== "" && a.command !== "" })` — bad entries are dropped, not fatal to the whole file).
- **A default binding overridden by user config:** not a conflict at all — this is the entire point of the feature. The user's entry for a given action simply replaces the built-in default for that action; the built-in default for every *other*, unmentioned action stays exactly as-is (§9).

Overall: validation happens once, at config load (app startup, or next reload per §12), never at each keypress — keypress-time dispatch should be a simple map lookup, not a conflict-resolution algorithm running 100+ times a second during fast navigation.

---

## 9. Defaults and Backwards Compatibility

**The single most important constraint, and the reason this audit recommends addressing §1.2's triplication as part of implementation, not as an afterthought:**

Recommendation: **the 36 default bindings move from being *implicit in the `if/else` chain's literal comparisons* to being an explicit, named data structure** — e.g. a plain JS object/array literal at the top of `KeyboardShortcuts.qml` (or a new tiny sibling file) shaped like:

```js
readonly property var defaultBindings: [
  { action: "nav.moveDown", key: "Down", altKey: "j" },
  { action: "nav.moveUp",   key: "Up",   altKey: "k" },
  ...
]
```

This single list becomes the **one** source of truth for three consumers that today are three separately-maintained copies (§1.2): (1) the resolver falls back to it for any action the user's `keybindings.toml` doesn't mention; (2) `ShortcutsHelp.qml`'s `Repeater` model is generated from it (merged with the user's overrides) instead of hand-copied; (3) the README table becomes the one place that's still genuinely hand-written (Markdown isn't QML-loadable), but with a comment pointing at this list as the generator's source of truth, closing the loop.

**"No configuration file" must produce byte-identical behavior to today.** Concretely: `keybindings.toml` missing → `CustomActions.qml`-style empty-read → empty override map → the resolver falls through to `defaultBindings` for every single action → `handlePress()`'s dispatch is *behaviorally* the same 36-branch decision it is today, just reached through one extra lookup instead of a literal `if`. This is directly testable (§15) by running the *existing* keyboard-shortcut selfcheck with zero config file present and asserting identical results.

This is not "creating an unnecessary abstraction layer" (the task's own concern in §9) — it is naming a list that is already fully enumerable today (§2's table *is* that list, just currently spread across 36 `if/else` conditions instead of one array), which is a prerequisite for the feature existing at all, not a speculative addition on top of it.

---

## 10. Colemak Use Case

With the design above, a Colemak user's `~/.config/omafiles/keybindings.toml`:

```toml
[navigation]
moveDown = "n"      # Colemak home-row-adjacent "down" position
moveUp   = "e"
moveLeft = "b"       # "go up a directory" (was h)
moveRight = "i"      # "open" (was l)
```

At load: the resolver builds an override map `{"nav.moveDown": "n", "nav.moveUp": "e", ...}`. At keypress time: `n` (no modifier, file-list context, no modal open) → resolver looks up `n` → finds it maps to `nav.moveDown` → dispatches to the exact same `hostControllers` call `Down`/`j` dispatch to today. The user does not need to know or guess the "correct" Colemak mapping — **this audit deliberately does not prescribe one** (per the task's own instruction); the user picks whatever four keys are comfortable, exactly like they would configure any other Colemak-aware application. `Down`/`Up`/`Left`/`Right` (the arrow keys) are physically unaffected by keyboard layout and continue working as the unconfigurable fallback for every rebound action, same as today (§2: every navigation row already lists the arrow key as an always-present alternate, and that pattern is preserved, not replaced, by rebinding).

---

## 11. User Experience

**Recommended: Option B — configuration file + the existing "?" help overlay showing the *effective* (post-override) bindings.**

- **Option A (file only)** was rejected: `ShortcutsHelp.qml` already exists and already shows this exact information — leaving it hardcoded to the *defaults* after a user has customized their bindings would make the in-app help actively wrong for exactly the users this feature serves. Since §9 already requires centralizing the default list as real data (not literal `if/else` text), making `ShortcutsHelp.qml` render `defaultBindings` merged with the user's overrides instead of its current hand-copied array is a small, natural extension of work already being done for §9 — not a separate project.
- **Option C (GUI editor)** was rejected for v1: the architecture doesn't support it cheaply yet (no settings window exists at all in this app — confirmed, `state/` has no `Settings`/`Preferences` singleton, per §4), and building one is a large, separate UI feature orthogonal to the keybinding-resolution mechanism itself. Nothing about this design blocks adding one later once the underlying action/binding model exists — a GUI editor would just be a UI that writes `keybindings.toml`, which is exactly the kind of thing that gets easier, not harder, once this audit's proposed structure exists.
- **Command palette displaying the bound key next to each action:** worth doing, low-cost (the palette already has `{label, run}` entries; adding `{label, run, shortcut}` and rendering `shortcut` is a small template change), but **not required for v1** — flagged as a nice-to-have, not blocking.

---

## 12. Runtime Reload

**Recommendation: reload on next relevant use, not a file watcher — mirroring `CustomActions.qml`'s existing pattern exactly, not a restart requirement.**

Two real options were weighed:
- **Full restart required:** simplest possible implementation, but a strictly *worse* user experience than what `actions.toml` already offers today for a structurally identical problem (small, rarely-changed, user-hand-edited config file) — there's no reason keybindings should regress below the bar the existing custom-actions feature already cleared.
- **A file-system watcher (`QFileSystemWatcher` or similar) triggering live reload:** rejected — the task explicitly warns against adding a daemon/watcher "simply for this feature," and `CustomActions.qml` deliberately doesn't do this either (its own comment: reload happens "on opening the palette or a context menu," not on file change) — there is no existing infrastructure for config-file watching anywhere in this codebase to reuse, so adding one would be new, unjustified complexity for a config file that changes on the order of "once, when the user sets it up."
- **Recommended, matching the existing precedent:** re-read `keybindings.toml` the same way `actions.toml` is re-read — on a natural, infrequent trigger the user already associates with "the app noticing my config," such as opening the command palette (already the `CustomActions.reload()` trigger) or opening the shortcuts-help overlay. A keypress that changes behavior moments after the user saved the file, without a restart, without any new file-watching machinery.

---

## 13. Proposed Architecture

```
Keyboard event (Keys.onPressed, unchanged call sites)
        ↓
KeyboardShortcuts.handlePress(event)          [existing file, existing entry point]
        ↓  (existing ~18-gate modal/text-field precedence chain, UNCHANGED)
        ↓
KeybindingResolver.actionFor(event)  →  "nav.moveDown" | null    [NEW, small]
        ↓
handlePress()'s existing dispatch switch, now keyed by action id instead of
inline event.key comparisons — SAME handler calls as today, just reached
via one indirection instead of a literal if
```

**Proposed new files:**
- `logic/KeybindingResolver.qml` (or, given its small size, this could equally be a handful of functions added directly to the top of `KeyboardShortcuts.qml` — see the explicit recommendation below on which shape is actually justified). Responsibility: load+parse `keybindings.toml` (mirroring `CustomActions._parse()`'s shape), merge with `defaultBindings`, validate/detect conflicts (§8), expose one function: `actionFor(event) → string|null`.
- `logic/KeyboardDefaults.qml` (or a `readonly property var defaultBindings` block inside `KeyboardShortcuts.qml` itself) — the single source of truth from §9. A separate file is only justified if `ShortcutsHelp.qml` needs to import it without depending on the whole `KeyboardShortcuts` controller (it does — `ShortcutsHelp.qml` is a `dialogs/` component with no controller access today); a small dedicated file avoids a `dialogs/` → `logic/` dependency that doesn't otherwise exist anywhere in this codebase. **Recommendation: yes, a separate tiny file, specifically to avoid that new cross-layer edge — not because "defaults deserve their own file" in the abstract.**

**Existing files modified:**
- `logic/KeyboardShortcuts.qml`: each of the 36 `else if (event.key === Qt.Key_X && ...)` conditions becomes `else if (action === "nav.moveDown")` after one `var action = KeybindingResolver.actionFor(event)` call at the top of the "normal" dispatch section (i.e., *after* the existing 18-gate chain, which stays byte-for-byte the same). This is a **mechanical, line-for-line transformation** of the existing structure — not a rewrite.
- `dialogs/ShortcutsHelp.qml`: its `Repeater { model: [...] }` becomes `model: KeyboardDefaults + resolver overrides` instead of a hand-copied literal (closes the §1.2 gap).
- `state/Paths.qml`: one new `readonly property string keybindingsFile: configDir + "/keybindings.toml"`, mirroring `actionsFile` exactly.
- `README.md`: the keyboard-shortcuts table gains a one-line note pointing at the new config file, mirroring the existing "Custom actions" section's own structure.

**Public API surface:** exactly one function, `actionFor(event): string | null`. Everything else (parsing, defaults, conflict detection) is internal to the resolver.

**Action identifiers:** flat, namespaced strings (`"nav.moveDown"`, `"file.rename"`, `"clipboard.copy"`...) — the §2 table, dot-namespaced by the existing controller each already calls into (`nav.*` → `navController`, `file.*`/`selection.*` → `actionEngine`, `tab.*` → `tabOps`, etc.), so the mapping from action id to "which controller method does this call" reads directly off the name.

**Context handling:** no new mechanism — the existing 18-gate chain (§1.4) stays exactly where it is, unmodified, and the resolver is only ever consulted after it. §6 already establishes no context tier beyond that is currently needed.

**Conflict handling:** inside the resolver's load/merge step, per §8 — a pure function of the parsed override map plus `defaultBindings`, no runtime cost per keypress.

**Defaults:** `KeyboardDefaults.qml`'s data, per §9 — one list, three consumers (resolver fallback, help overlay, README-generation-in-spirit).

---

## 14. Phase 43 / Previous Architecture Lessons — explicit comparison

| Phase 43 failure mode | Does this proposal repeat it? |
|---|---|
| Wrapper-on-wrapper (a component that only forwards to another) | No — `KeybindingResolver` does real work (parse, merge, validate) that doesn't exist anywhere today; it is not a pass-through. |
| Generic service with no real ownership | No — it owns exactly one thing (mapping a physical key + context to an action id) and nothing else; it does not become a dumping ground for other keyboard-adjacent concerns (§6 explicitly declines to add a context-tier system it doesn't need yet). |
| Duplicated state | Partially pre-existing (§1.2's triplication, §1.3's triple selection-nav) — this proposal **reduces** one of the two (§9 centralizes defaults) and **documents but does not fix** the other (§6's SearchBar/CommandPalette arrow-nav gap) rather than silently ignoring it or building unrequested scope to fix it too. |
| Excessive signal forwarding | No new signals are introduced; `actionFor()` is a plain synchronous function call, same shape as every other `logic/` controller function `KeyboardShortcuts.qml` already calls. |
| Context-property magic | No — the resolver receives the same `event` object `handlePress()` already has; no new implicit/global state threading. |
| Creating a class solely because a file is large | Explicitly rejected as the reason for `KeybindingResolver.qml`'s existence — the actual reason given (§13) is "config parsing + conflict validation is a distinct, real responsibility `KeyboardShortcuts.qml` doesn't have today," matching the P2.3 `ArchiveBrowser` extraction's own bar ("a genuine domain boundary, not a renamed wrapper") rather than a size threshold. `KeyboardDefaults.qml`'s justification is even narrower and explicit: avoiding one specific new cross-layer dependency edge (`dialogs/` → `logic/`), not general tidiness. |

**If a future implementer finds that `KeybindingResolver` ends up being three lines that just call `Object.assign(defaults, overrides)[key]`,** the honest conclusion at that point would be to fold it directly into `KeyboardShortcuts.qml` as a private function instead of a separate file — this audit's file split is a *prediction* based on the parsing+validation work in §4/§8 being real, not a foregone conclusion; the implementer should re-check this specific call when writing the code, not treat §13's file list as gospel.

---

## 15. Testing Strategy

All tests below should exercise the **real** `logic/KeyboardShortcuts.qml` dispatch via the real composition root (`sc._content`), per this session's established discipline (P0/P1/Debian-feedback/P2.1–4 passes) — never an isolated fake `Item` standing in for the resolver.

| Scenario | Approach |
|---|---|
| Default bindings identical with no config file | Point `Paths.keybindingsFile` at a nonexistent path (or the existing selfcheck harness's isolated temp `$XDG_CONFIG_HOME`, already used for other config-adjacent tests), synthesize the same key events the *existing* `"Keyboard shortcut integration test (BUG-06)"` selfcheck already sends, assert identical `stubEngine` calls. This existing test is the direct regression baseline — it must keep passing unmodified. |
| Custom navigation binding (the Colemak case) | Write a real `keybindings.toml` to the selfcheck's isolated config dir, remap `nav.moveDown` to a non-default key (e.g. `n`), send that key through the real composition root, assert `SelectionState.selectedIndex` moved — and that the *old* default key (`j`/`Down`) no longer does, proving the override actually replaced rather than added. |
| Modifier bindings | Same shape, for a `Ctrl+`-combination action. |
| Context precedence (text field wins) | Open the rename field for real (`EditModeState.renamingIndex = ...`), send the user's custom `nav.moveDown` key, assert it typed into the field / did not move selection — proving tier 1 (§6) still wins regardless of user config. |
| Dialogs | Open a real `ConfirmDialog`-backed gate (e.g. delete-confirm, already selfcheck-covered from the Debian-feedback pass), send a custom-bound key that would otherwise trigger a file-list action, assert the dialog's own Escape/Enter handling still runs instead. |
| Command palette | Send the user's custom `openPalette` key (if rebound) and confirm `PaletteState.paletteOpen` toggles; separately confirm the palette's own internal `Down`/`Up` are unaffected by user config (§6's documented gap — the test should assert this is *still* arrow-only, not silently accept a regression either way). |
| Conflicting bindings | Write a `keybindings.toml` with two actions mapped to the same key in the same context; assert config load reports the conflict (via whatever the resolver's error-reporting hook ends up being — likely `Backend.Notifier`, matching §8) and that neither binding silently wins over the other in an untested way. |
| Invalid configuration | Malformed TOML line, unknown action name, reserved-key rebind attempt (§5/§8) — assert graceful per-line degradation, matching `CustomActions._parse()`'s existing tolerance, and that the rest of a mostly-valid file still loads. |
| Missing configuration | The "no file" case is the same as the first row — explicitly called out again here because it is the single most important regression to guard, per §9. |
| Restart with custom configuration persisted | Since reload is "next relevant use" not instant (§12), a test should confirm a binding set via `keybindings.toml` at process start is active immediately (no extra action needed) — the *live-edit* reload case is lower-priority to test exhaustively than "did it load correctly at all," since instant-reload was explicitly not promised. |

---

## 16. Implementation Plan (future work, not this task)

Small, independently testable, in this order:

1. **Centralize the 36 defaults into `KeyboardDefaults.qml`** (§9) with zero behavior change — `KeyboardShortcuts.qml`'s dispatch still uses literal `event.key` checks, just now reading the comparison values from the new data structure instead of hardcoding them inline. Test: existing selfchecks + repeated runs, byte-identical pass/fail.
2. **Regenerate `ShortcutsHelp.qml`'s model from `KeyboardDefaults.qml`** instead of its hand-copied array (§1.2/§11), still with no user-config concept yet. Test: visual/content diff against the current hardcoded list is empty.
3. **Add `KeybindingResolver.qml`: parse `keybindings.toml`, merge with defaults, expose `actionFor(event)`** — but `KeyboardShortcuts.qml` doesn't call it yet. Test: unit-style selfchecks against the resolver directly (parsing, merging, conflict detection), independent of the dispatch wiring.
4. **Wire `handlePress()`'s dispatch through `actionFor()`** (§13's mechanical transformation), still shipping with an empty/absent `keybindings.toml` by default. Test: the full existing keyboard-shortcut selfcheck suite must still pass unmodified — this is the step where a regression would be most likely and most damaging.
5. **Ship the Colemak-style override capability** — by this step it already works; this is just removing any remaining "not yet wired" caveat and updating `README.md`.
6. *(Optional, not required for the feature to be complete)* Command palette shows the bound key next to each entry (§11).

Each step should land, get the full 107-selfcheck suite run repeated (this session's established discipline), and be independently revertable before the next step starts.

---

## Explicit Non-Goals

- **No GUI keybinding editor** in v1 (§11) — no settings window exists in this app at all today; building one is a separate, much larger feature.
- **No Vim-style multi-key chord engine** (§7) — the one existing chord (`gg`) stays as its current bespoke timer-based mechanism, unconfigurable in v1.
- **No file-watcher/daemon** for live config reload (§12) — reload-on-next-relevant-use, matching `actions.toml`'s existing behavior exactly.
- **No unnecessary service layer** — `KeybindingResolver`'s justification is concrete (real parsing+validation work, §14's table), not size or "it would be cleaner"; the implementer is explicitly told to fold it back into `KeyboardShortcuts.qml` if it turns out to be trivial.
- **No unrelated keyboard refactor** — `SearchBar.qml`'s and `CommandPalettePanel.qml`'s independent arrow-key navigation (§1.3) is documented, not fixed, in this pass; unifying them into the same resolver is explicitly deferred, not silently ignored.
- **No rebinding of OS-convention keys** (`Ctrl+C/X/V/Z`, `Ctrl+Tab`) in v1 (§5) — a deliberate scope line, not an oversight.
- **No new keybindings for currently-key-less palette-only actions** (§2, §5) — additive-key assignment is a different feature from rebinding an existing one.

---

## Risks (highest first)

1. **The §1.3 SearchBar/CommandPalette gap becomes a real support burden.** A Colemak user who rebinds `MoveDown` will reasonably expect it to work *everywhere* selection moves, including while typing a search query or filtering the palette — and it won't, per this design. Mitigation: this must be documented prominently (help overlay, README) the moment the feature ships, not discovered by users through confused bug reports. If it becomes a frequent complaint, unifying those two components into the same resolver (§6 option (b)) should be revisited as a fast-follow, not re-litigated as a v1 blocker.
2. **§9's centralization touches the one file (`KeyboardShortcuts.qml`) with 36 branches and zero existing selfcheck coverage per-branch** (only one aggregate "6 shortcuts" isolated-component test exists today, per this session's earlier P1-3 work — `"Keyboard shortcut integration test (BUG-06)"`). The mechanical transformation in implementation step 4 is exactly the kind of change that silently breaks one branch while 35 others keep working — this is precisely why step 4 is called out as the highest-regression-risk step and gated on the full selfcheck suite passing, not spot-checked.
3. **Conflict-detection policy (§8) needs a real UI surface to report through**, and none of `Backend.Notifier`'s existing call sites are "app startup, before any window content is meaningfully visible yet" — worth confirming during implementation that a startup-time notification actually reaches the user reliably (vs. a toast that fires before the window is mapped and is missed).
4. **`gg`'s timer-based chord (§7) is the one binding this design explicitly leaves unconfigurable** — if user feedback specifically asks to remap `g`, this design has no answer ready; flagged now so it isn't a surprise later.

---

## Verification

```
$ git status --short
?? docs/audits/P2_5_CUSTOM_KEYBINDINGS_AUDIT.md
```

No `.qml`, `.cpp`, `.h`, `.toml`, or `.md` file other than this new document was created or modified. `logic/KeyboardShortcuts.qml` and every other file listed in §1.1 is untouched. The 107 selfchecks were run anyway as an extra check (4 consecutive runs): 3/3 clean at 107/107; one run showed 9 transient failures that did not reproduce on immediate re-run and cannot be attributed to this task (zero production files were touched) — most likely contention from the user's own separately-running OmaFiles instance observed during the P2.4 pass, still running throughout this one. No commit was made.

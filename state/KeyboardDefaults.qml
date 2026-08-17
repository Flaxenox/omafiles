pragma Singleton
import QtQuick

// Default keyboard bindings for the active-panel shortcut surface
// (logic/KeyboardShortcuts.qml) -- P2.5, 2026-08-17. Pure data, no
// functions: the one authoritative list every consumer reads instead of
// three independently hand-maintained copies (the actual if/else logic,
// dialogs/ShortcutsHelp.qml's display list, and README.md's table all
// used to drift independently before this file existed -- see
// docs/audits/P2_5_CUSTOM_KEYBINDINGS_AUDIT.md §1.2/§9).
//
// Same pattern as state/FileTypeConfig.qml: static-ish configuration data
// that belongs in state/ specifically because both logic/KeyboardShortcuts.qml
// AND core/DialogLayer.qml (for the help overlay) already import "../state"
// freely -- putting this here needs zero new cross-layer edges. The
// business logic that PARSES ~/.config/omafiles/keybindings.toml and
// resolves an event against this list lives in logic/KeybindingResolver.qml
// (state/ stays a property bag; parsing/validation is orchestration, which
// belongs in logic/ per this project's own architecture rules).
//
// Each entry:
//   id      stable action identifier (snake_case, matches keybindings.toml)
//   label   human-readable name (ShortcutsHelp overlay)
//   fixed   true = not user-rebindable (OS/desktop clipboard-undo
//           conventions and the Ctrl+Tab "next tab" convention -- see the
//           audit §5 for the reasoning per action)
//   keys    ordered list of {key, mod} alternates, EXACTLY replicating
//           logic/KeyboardShortcuts.qml's original if/else chain:
//             mod: "any"   -- matches regardless of modifiers (the original
//                             code's bare `event.key === Qt.Key_X`, no
//                             modifier check at all -- e.g. the arrow keys)
//             mod: "none"  -- matches only with zero modifiers held
//                             (`event.modifiers === Qt.NoModifier`)
//             mod: "ctrl" / "shift" / "alt" / "ctrl+shift" -- matches when
//                             ALL listed modifiers are held, REGARDLESS of
//                             any other modifier also being held (the
//                             original code's `event.modifiers & Qt.XModifier`
//                             bitwise check, not `===`) -- this is why, e.g.,
//                             Ctrl+Shift+A must be listed BEFORE Ctrl+A
//                             below: both structurally match Ctrl+Shift+A,
//                             the first one in the list wins, exactly like
//                             the original if/else short-circuit order.
//
// A KNOWN, PRE-EXISTING, DELIBERATELY-NOT-FIXED quirk this list faithfully
// preserves rather than "fixing": Shift+j/k do NOT extend selection today
// (only Shift+Down/Up do), even though the help overlay and README both
// claim otherwise -- the original code requires exactly-no-modifier for
// the letter keys but has no modifier check at all for the arrow keys.
// This audit/implementation pass preserves current behavior exactly, per
// its own explicit instruction; it does not silently correct this.
QtObject {
  id: defaults

  readonly property var actions: [
    { id: "open_terminal",     label: "Open a terminal here",                fixed: false, keys: [{ key: "return", mod: "shift" }] },
    { id: "go_up",              label: "Go up a directory",                   fixed: false, keys: [{ key: "backspace", mod: "any" }, { key: "h", mod: "none" }] },
    { id: "open",                label: "Open (enter directory / launch file)", fixed: false, keys: [{ key: "return", mod: "any" }, { key: "l", mod: "none" }] },
    { id: "toggle_preview",     label: "Toggle preview (Quick Look)",         fixed: false, keys: [{ key: "space", mod: "any" }] },
    { id: "search",              label: "Search files",                        fixed: false, keys: [{ key: "/", mod: "any" }, { key: "f", mod: "ctrl" }] },
    { id: "command_palette",    label: "Command palette",                     fixed: false, keys: [{ key: ":", mod: "any" }, { key: "p", mod: "ctrl" }] },
    { id: "toggle_help",        label: "Toggle this help",                    fixed: false, keys: [{ key: "?", mod: "any" }] },
    { id: "go_bottom",           label: "Jump to bottom",                      fixed: false, keys: [{ key: "g", mod: "shift" }] },
    { id: "move_down",          label: "Move down",                           fixed: false, keys: [{ key: "down", mod: "any" }, { key: "j", mod: "none" }] },
    { id: "move_up",             label: "Move up",                             fixed: false, keys: [{ key: "up", mod: "any" }, { key: "k", mod: "none" }] },
    { id: "select_none",        label: "Select none",                         fixed: false, keys: [{ key: "a", mod: "ctrl+shift" }] },
    { id: "select_all",         label: "Select all",                          fixed: false, keys: [{ key: "a", mod: "ctrl" }] },
    { id: "invert_selection",  label: "Invert selection",                    fixed: false, keys: [{ key: "i", mod: "ctrl" }] },
    { id: "rename",              label: "Rename",                              fixed: false, keys: [{ key: "f2", mod: "any" }] },
    { id: "delete",              label: "Delete (to trash)",                   fixed: false, keys: [{ key: "delete", mod: "any" }] },
    { id: "refresh",             label: "Refresh",                             fixed: false, keys: [{ key: "f5", mod: "any" }] },
    { id: "reverse_sort",       label: "Reverse sort order",                  fixed: false, keys: [{ key: "s", mod: "shift" }] },
    { id: "cycle_sort",         label: "Cycle sort field",                    fixed: false, keys: [{ key: "s", mod: "none" }] },
    { id: "edit_path",          label: "Edit path",                           fixed: false, keys: [{ key: "l", mod: "ctrl" }] },
    { id: "new_folder",         label: "New folder",                          fixed: false, keys: [{ key: "n", mod: "ctrl+shift" }] },
    { id: "new_file",            label: "New file",                            fixed: false, keys: [{ key: "n", mod: "ctrl" }] },
    { id: "new_tab",             label: "New panel",                           fixed: false, keys: [{ key: "\\", mod: "ctrl" }, { key: "t", mod: "ctrl" }] },
    { id: "nav_back",            label: "Back",                                fixed: false, keys: [{ key: "left", mod: "alt" }] },
    { id: "nav_forward",        label: "Forward",                             fixed: false, keys: [{ key: "right", mod: "alt" }] },
    { id: "close_tab",           label: "Close active panel",                  fixed: false, keys: [{ key: "w", mod: "ctrl" }] },
    { id: "next_tab",             label: "Next panel",                          fixed: true,  keys: [{ key: "tab", mod: "ctrl" }] },
    { id: "toggle_hidden",      label: "Toggle hidden files",                 fixed: false, keys: [{ key: "h", mod: "ctrl" }] },
    { id: "copy",                 label: "Copy",                                fixed: true,  keys: [{ key: "c", mod: "ctrl" }] },
    { id: "cut",                  label: "Cut",                                 fixed: true,  keys: [{ key: "x", mod: "ctrl" }] },
    { id: "paste",                label: "Paste",                               fixed: true,  keys: [{ key: "v", mod: "ctrl" }] },
    { id: "redo",                 label: "Redo",                                fixed: false, keys: [{ key: "z", mod: "ctrl+shift" }, { key: "y", mod: "ctrl" }] },
    { id: "undo",                 label: "Undo",                                fixed: true,  keys: [{ key: "z", mod: "ctrl" }] }
  ]

  // Populated by logic/KeybindingResolver.qml's reload(): { actionId: "key string" }.
  // Empty (no user config, or nothing valid parsed) means every action uses
  // its default keys above, unchanged -- this is the whole compatibility
  // guarantee from the audit's §9 in one property.
  property var overrides: ({})
}

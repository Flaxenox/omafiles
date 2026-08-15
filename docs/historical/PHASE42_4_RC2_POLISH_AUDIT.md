# Phase 42.4: RC2 Polish Audit

## Objective
Final product-polish pass before releasing v0.9.0-rc2. The goal is to make OmaFiles feel effortless, applying the DHH philosophy of removing friction and unnecessary decisions.

## 1. Empty States Audit
Reviewed empty states across the application:
- **Active / Background Panels**: Upgraded `EmptyState` component to support an actionable `subMessage`.
- **Empty Directory**: "Folder is empty" / "Drop files here to add them".
- **Empty Trash**: "Trash is empty" / "Deleted items will appear here".
- **Empty Search**: "No results for X" / "Try a broader search or check spelling".
- **Command Palette**: Added an empty state for when no commands match the filter ("No commands available" / "Try a broader search").
- **Preview Panel**: Added an empty state when no item is selected ("No file selected" / "Select a file to preview its contents").

All empty states now explicitly guide the user on what to do next rather than simply stating a negative.

## 2. Error Messages Audit
Simplified and polished error messages across all file and mount operations:
- Removed redundant prefixes (e.g., "Could not mount:" -> "Couldn't mount drive", or just the native OS error string).
- Handled edge cases where native POSIX errors (`strerror`) were unnecessarily wrapped in "Action failed:" text. Native errors ("Permission denied", "File exists") are now presented directly.
- The UX feels less technical and more direct.

## 3. Interaction Consistency
- Core keyboard shortcuts (`Enter`, `Space`, `Delete`, `Shift+Delete`, `Ctrl+C/X/V`) behave identically across panels, archives, and trash.
- Moving between the file view, the Command Palette, and Dialogs is consistently manageable entirely via keyboard.

## 4. Visual Polish
- Standardized padding (`Style.spacing.sm`) and border treatments across all EmptyStates.
- ensured focus indicators correctly outline active elements without shifting layouts.

The application adheres strictly to its keyboard-first, native-performance design mandate.

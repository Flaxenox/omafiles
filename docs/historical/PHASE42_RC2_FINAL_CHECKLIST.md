# OmaFiles v0.9.0-rc2 Final Checklist

## Integrity & Data Safety
- [x] Zero known data-loss bugs in copy/move/trash.
- [x] Zero known undo/redo stack regressions.
- [x] File operations survive cross-filesystem constraints.
- [x] Trash operations preserve paths correctly.

## Architecture & Native Backends
- [x] `MimeResolver` is fully native (C++ based on `gio-2.0`).
- [x] `TerminalResolver` is fully native (C++ auto-detecting terminal emulators).
- [x] `NetworkResolver` is fully native (C++ async GIO mounts with ephemeral auth).
- [x] No `bash -c`, `sh -c`, `xdg-terminal-exec`, or `sshpass` hacks remaining in core interactive flows.
- [x] `GioCompat.h` cleanly isolates GIO macro clashes.

## Performance & Quality Gates
- [x] 82/82 selfchecks passing (`omafiles-standalone --selfcheck`).
- [x] Zero network deadlocks or console hangs.
- [x] Performance regression gate passes (Phase 38 bounds maintained).

## UI/UX Polish
- [x] Empty states are clear and actionable (no generic "No items").
- [x] Errors are short, actionable, and non-technical.
- [x] Complete keyboard-only workflow verified.
- [x] Consistent interaction across all panels.

## Release Readiness
- [x] Documentation synchronized.
- [x] Ready to draft Release Notes for v0.9.0-rc2.

*Status: READY for v0.9.0-rc2 publication.*

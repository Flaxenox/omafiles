# OmaFiles — Phase 42: RC2 Checklist

This checklist tracks the specific implementation items for the RC2 Friction Removal phase.
No item should be checked off until it passes the selfcheck suite and the performance regression gate.

## 42.1 Native Open With
- [ ] Implement `Backend.MimeResolver` to parse `mimeapps.list` and `.desktop` files.
- [ ] Implement `.desktop` execution (parsing `%f`/`%F`).
- [ ] Expose `getAppsForFile(path)` to QML.
- [ ] Update `ContextMenu.qml` to consume the new API.
- [ ] Delete `scripts/open-with-list.sh`.
- [ ] Pass `selfcheck` and ensure "Open With" menu opens instantly.

## 42.2 Terminal & Path Workflow
- [ ] Implement "Copy path" in the Context Menu (already exists, verify shell-safe quoting if necessary).
- [ ] Implement "Copy relative path" (from current panel root).
- [ ] Implement "Copy URI" (`file://...`).
- [ ] Implement "Open terminal here". Auto-detect `$TERMINAL`, `kitty`, `alacritty`, `foot`, `gnome-terminal`, `konsole`.
- [ ] Verify keyboard-first invocation (`Shift+Enter` or palette).

## 42.3 Intelligent Network Behavior
- [ ] Intercept network shares (SMB/SFTP) requiring passwords.
- [ ] Provide a minimal, ephemeral dialog (just a password field) *only* if `ssh-agent` or the Secret Service cannot handle it automatically.
- [ ] Do not build a standalone Network Accounts manager.

## 42.4 RC2 Polish (Friction Reduction)
- [ ] Improve empty directory visual state (no blank white panels).
- [ ] Improve permission denied visual state (clear human-readable text).
- [ ] Improve "Zero results" state for content/filename searches.
- [ ] Ensure archives can be double-clicked to browse inside.
- [ ] Verify external drives mount automatically on interaction.
- [ ] Review all D-Bus/Portal integrations to ensure silent, correct behavior.

---
**Constraint Checklist for every PR:**
- [ ] Is the codebase simpler after the change?
- [ ] Are we preferring convention over configuration?
- [ ] Does `--selfcheck` still pass `82/82` (or more)?
- [ ] Did we avoid adding new configuration toggles?

# OmaFiles — Phase 42: Friction Removal Audit (DHH Edition)

**Target Release:** `v0.9.0-rc2`  
**Philosophy:** Remove friction. Prefer directness over flexibility. Zero configuration.

## 1. Native Open With (Phase 42.1)
*   **Current Friction:** Shelling out to a bash script (`open-with-list.sh`) to query the XDG `mimeapps.list` and `.desktop` files introduces process overhead, potential string encoding issues, and is a brittle legacy layer. 
*   **DHH Approach:** Eliminate the shell glue. Parse XDG MIME definitions directly in C++. It makes the app faster, self-contained, and simpler to reason about. 

## 2. Terminal & Path Workflow (Phase 42.2)
*   **Current Friction:** A Hyprland user constantly needs to ferry paths between the file manager and the terminal. Currently, they might have to manually quote spaces or struggle to get relative paths.
*   **DHH Approach:** Provide "Copy shell-safe path", "Copy relative path", and "Copy URI" commands out of the box. Automatically detect the user's terminal emulator (e.g., kitty, alacritty, foot) so "Open terminal here" just works without a settings panel.

## 3. Intelligent Network Behavior (Phase 42.3)
*   **Current Friction:** Network shares (GVfs) fail silently if credentials aren't cached, or require dropping to a terminal to use `gio mount`.
*   **DHH Approach:** Do not build a massive credential manager. Reuse `ssh-agent` and the Secret Service API (gnome-keyring / kwallet). Only if a password is fundamentally required, show a minimal, ephemeral prompt to mount the share, then forget about it. No "Network Settings" dialog.

## 4. RC2 Polish (Phase 42.4)
*   **Empty States:** If a directory is empty, say it clearly. No blank white screens.
*   **Permission Errors:** Do not show cryptic POSIX errors. Say "You don't have permission to write here" directly.
*   **Search Zero-Results:** If `content:Foo` yields nothing, show a clear "No matches for 'Foo'" state instead of an empty list.
*   **Archive Drill-Down:** Clicking an archive should seamlessly show its contents without prompting "Extract here or open?". 
*   **External Drives:** Auto-mount on click if not mounted. Eject with a single shortcut.

**Conclusion:** By applying sharp knives and opinionated defaults, we can make OmaFiles dramatically faster and more pleasant to use, eliminating the need for a preferences window entirely.

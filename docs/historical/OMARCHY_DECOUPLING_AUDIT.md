# OmaFiles — Omarchy Decoupling Audit

## Executive Summary
OmaFiles has successfully evolved from a QuickShell plugin embedded within the Omarchy environment to a standalone Qt6 application. However, significant technical debt remains in the form of architectural structures, configuration files, and documentation/comments that still assume or describe its former life as a plugin.

This audit identifies every remaining dependency, historical artifact, and structural assumption tying OmaFiles to Omarchy or QuickShell, and provides a concrete migration plan to establish it as a fully independent, canonical Qt6 application.

## Omarchy Dependency Inventory

1. **`scripts/install-integrations.sh`**
   - **Line 105:** `Comment=Custom file manager for Omarchy` in the generated `.desktop` file. *(Optional / Historical Artifact)*
   - **Line 143:** `UseIn=omarchy;Hyprland;` in the generated `omafiles.portal` file. *(Optional / Historical Artifact)*
   - **Lines 48-55:** `LEGACY_ACTIONS` migration block from `~/.config/omarchy/omafiles/actions.toml`. *(Historical Artifact)*
2. **`main.cpp`**
   - **Lines 394-402:** Comments detailing how `ThemeSource` reads Omarchy's live theme files (`colors.toml`/`shell.toml`) to achieve "theme parity" with Quickshell. *(Historical Artifact)*

## QuickShell Legacy Inventory

1. **`scripts/omafiles-backend.conf`**
   - A systemd `environment.d` drop-in whose sole purpose is to inject `QML_IMPORT_PATH` into `quickshell` so it can load the OmaFiles C++ backend plugin. This is entirely useless for the standalone application which configures its own QML engine in `main.cpp`. *(Architectural Dependency / Historical Artifact)*
2. **`integrations/` Directory Structure**
   - The existence of `integrations/standalone/Main.qml` implies that the standalone binary is just one of multiple "integrations" (the other historically being `quickshell`). *(Architectural Dependency)*
3. **QML File Comments (`services/*.qml`, `state/*.qml`, `shared/*.qml`)**
   - Dozens of files contain comments referencing `Omafiles.qml` (the old plugin entrypoint), `HostBridge.qml`, and `Quickshell.Io.Process`. *(Historical Artifacts)*
4. **`CMakeLists.txt` and `ARCHITECTURE.md`**
   - Heavy documentation and build-system comments explaining how the backend compiles and loads into QuickShell vs the standalone frontend. *(Historical Artifacts)*

## Files Requiring Changes

### Safe Removals
- **`scripts/omafiles-backend.conf`**: Delete entirely.
- **`scripts/install-integrations.sh`**: Remove the `LEGACY_ACTIONS` copying block.

### Required Architectural Changes
- **Directory Restructuring**: Move the contents of `integrations/standalone/` (including `Main.qml`, `SelfCheck.qml`, and `qml_modules`) to a new root-level directory (e.g., `app/` or `main/`). Delete the `integrations/` folder.
- **`CMakeLists.txt`**: Update paths to point to the new `app/Main.qml` location. Remove all comments referencing QuickShell plugin builds.
- **`main.cpp`**: 
  - Update `resolveResourceDir()` (lines 73) and `engine.load()` (lines 310, 386) to point to the new `app/Main.qml` (or equivalent) path.
  - Remove all comment references comparing execution to the QuickShell frontend.
- **`scripts/install-integrations.sh`**: 
  - Change `.desktop` comment to "Custom Qt6 file manager".
  - Change `.portal` backend `UseIn` to `Hyprland;` or leave it empty to allow XDG Desktop Portal to handle default routing.

### Documentation / Comment Scrub
The following files require comment pruning to remove references to `Omafiles.qml`, `HostBridge`, and `Quickshell`:
- `panels/Sidebar.qml` (Omarchy Quattro aesthetic references)
- `services/Detached.qml`, `services/Env.qml`, `services/Notifier.qml`, `services/ProcessRunner.qml`, `services/ProcessWatcher.qml`
- `shared/BreadcrumbSegments.qml`, `shared/EmptyState.qml`, `shared/FileRowVisual.qml`, `shared/MarqueeCatcher.qml`, `shared/PanelNavButtons.qml`
- `state/*.qml`

## Canonical Standalone Layout
Once applied, the canonical runtime layout will be standard and agnostic:
- **Binary**: `omafiles` (installed to `~/.local/bin/` or system `bin/`)
- **Resources**: `~/.local/share/omafiles/`
  - `app/` (formerly `integrations/standalone`)
  - `core/`, `logic/`, `panels/`, `dialogs/`, `shared/`, `services/`, `state/`
  - `scripts/` (D-Bus activation scripts, installation scripts)
  - `assets/` (SVGs, Icons)
  - root-level `.sh` utilities
- **Integrations**: Standard XDG `.desktop`, D-Bus `.service` files, and `.portal` definitions.

## Migration Order

1. **Delete** `scripts/omafiles-backend.conf`.
2. **Move** `integrations/standalone` to `app/` and delete `integrations/`.
3. **Update** `main.cpp` and `CMakeLists.txt` to reflect the new `app/` path for QML loading.
4. **Patch** `install-integrations.sh` to remove legacy Omarchy migration blocks and update `.desktop`/`.portal` strings.
5. **Scrub** all `.qml`, `.cpp`, and `.md` files of QuickShell and Omarchy terminology.

## Estimated Risk
**Low**. 
The changes involve deleting unused files, moving one directory, and editing comments/strings. No core QML logic, C++ backend logic, or D-Bus communication is altered. 

## Estimated Code Reduction
- 1 unused config file (`omafiles-backend.conf`)
- ~10 lines of legacy bash migration scripts
- ~100-150 lines of historical comments across QML and C++ files

---

### Conclusion
**Can OmaFiles be considered a fully independent Qt6 application after these changes?**

**Yes.** Upon completing this migration plan, OmaFiles will contain zero structural, textual, or runtime ties to Omarchy or QuickShell. It will exist purely as a standard, canonical Qt6 application that integrates with any modern Wayland/X11 Linux desktop environment through standard XDG protocols.

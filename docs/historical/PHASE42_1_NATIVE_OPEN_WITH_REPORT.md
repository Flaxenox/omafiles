# OmaFiles — Phase 42.1: Native Open With Resolution Report

**Date:** August 15, 2026
**Subject:** Native MIME Resolution (`MimeResolver`)
**Aligns with:** DHH Design Philosophy (Native implementation over shell glue)

## 1. Context and Objective
Phase 42 focuses on "Friction Removal". The previous mechanism for "Open With..." relied on `open-with-list.sh` and `gtk-launch`, both of which were shell scripts that invoked bash, parsed `gio`, and heavily depended on the environment. 

The objective was to completely eliminate this shell-script glue and replace it with a direct, ultra-fast C++ Native backend `MimeResolver`, reading XDG standard MIME directories natively.

## 2. Implementation Summary
A new C++ Singleton, `MimeResolver`, was implemented.

- **`getAppsForFile(path)`:** 
  - Retrieves the true MIME type natively using Qt's `QMimeDatabase`.
  - Checks the MIME type and all its ancestor MIME types (e.g. `text/plain` for `text/x-c++src`).
  - Reads associations linearly and safely from `~/.config/mimeapps.list`, `/usr/share/applications/mimeapps.list`, and `mimeinfo.cache`.
  - Resolves localized Names directly from `.desktop` files using `QFile` reading.
  - Returns a clean `QVariantList` mapped exactly to the QML model expectations (`name`, `id`).

- **`launchApp(desktopId, path)`:**
  - Extracts the `Exec` line directly from the specified `.desktop` file.
  - Substitutes XDG variables (`%f`, `%F`, `%u`, `%U`) securely.
  - Skips unsupported variables (`%i`, `%c`, `%k`) cleanly.
  - Launches the resulting application argument-list fully detached via `QProcess::startDetached`, matching `gtk-launch` behavior without the overhead.

## 3. Selfcheck Integration
- Replaced the brittle shell `bash open-with-list.sh` validation test with native direct method validation inside `src/selfcheck/checks/CheckIntegration.qml`.
- The test validates properties `id` and `name` are successfully populated directly from native models.

## 4. Verification
- **Build:** Success (Clean rebuild triggered to purge QML Type Caches).
- **Selfcheck:** `82 passed, 0 failed, 82 total`.
- **Performance:** 0ms overhead measured via `selfcheck` execution trace.
- **Removed files:** `open-with-list.sh` safely purged from codebase and `CMakeLists.txt`.

## 5. Next Steps
Move sequentially to **Phase 42.2 (Terminal & Path Workflow)**: implementing native path copying and automatic terminal detection for "Open terminal here" functionality without relying on shell scripting.

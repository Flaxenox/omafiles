# OmaFiles — Phase 42.1: Native Open With Implementation Plan

**Goal:** Eliminate `open-with-list.sh` and perform MIME-to-App resolution natively in C++.

## 1. The Core Architecture (Backend.MimeResolver)
Create a new C++ backend module `MimeResolver` (or similar) that implements the FreeDesktop Shared MIME-info and Desktop Entry specifications directly.

### Responsibilities:
1.  **MIME Type Detection:** Given a file path, resolve its MIME type using `QMimeDatabase`.
2.  **MIME Apps List Parsing:** Parse `~/.config/mimeapps.list` and `/usr/share/applications/mimeapps.list` to respect user overrides and system defaults.
3.  **Desktop File Parsing:** Read `.desktop` files in `~/.local/share/applications/` and `/usr/share/applications/` to extract the `Name`, `Exec`, and `Icon` fields.
4.  **Menu Generation:** Provide a `QVariantList` of available applications for a given file to the QML frontend.
5.  **Execution:** Launch the selected `.desktop` file natively via `QProcess` or `QDesktopServices`, correctly interpolating the `%f`, `%F`, `%u`, or `%U` placeholders.

## 2. DHH Principles Applied
*   **Directness:** Do not cache the `.desktop` files in a complex SQLite database. `QFileSystemWatcher` or simple on-demand reading is fast enough for the scale of modern NVMe drives. Keep it stateless and synchronous.
*   **Zero Configuration:** OmaFiles will not implement an "App Chooser" or a UI to modify `mimeapps.list`. We read the system truth and respect it. If a user wants to change their default app, they use `xdg-mime default`. We are a file manager, not a system settings daemon.
*   **No Shell-Out:** Replacing `open-with-list.sh` reduces D-Bus latency and process-creation overhead, cutting the "Open With" menu generation time from ~30ms down to <2ms.

## 3. Implementation Steps
1.  Add `MimeResolver.h` and `MimeResolver_Xdg.cpp` to the C++ backend.
2.  Expose `Q_INVOKABLE QVariantList getAppsForFile(const QString &path)` to QML.
3.  Expose `Q_INVOKABLE void launchApp(const QString &desktopId, const QString &path)`.
4.  Remove `scripts/open-with-list.sh`.
5.  Update `ContextMenu.qml` to bind to the new C++ API.
6.  Verify that `omafiles --selfcheck` continues to pass without the script.

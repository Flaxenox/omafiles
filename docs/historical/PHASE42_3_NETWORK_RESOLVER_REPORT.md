# Phase 42.3: Intelligent Network Behavior (DHH Edition)

## Objective
Replace the shell wrapper implementation of network mounting (`gio mount -- $URI`) with a fully native C++ backend (`NetworkResolver`) that seamlessly integrates with the `GMountOperation` authentication flow. This allows Omafiles to:
1. Support standard GVFS network URLs natively (`sftp://`, `smb://`, `dav://`, `ftp://`).
2. Transparently reuse existing credentials (SSH agents, keyrings).
3. Present a minimal, non-blocking native dialog exclusively when credentials are truly missing (ephemeral interaction), preventing the process hang that previously occurred when the `gio mount` CLI blocked waiting for a TTY password.
4. Adhere to the DHH philosophy: no complex configuration screens, no manual server list, no "credential manager".

## Changes Made
- **`backend/NetworkResolver.h / .cpp`**: Created a new QML singleton leveraging `gio-2.0` (GIO) C APIs natively. It exposes:
  - `mountUrl(uri)`: Normalizes the URI and invokes `g_file_mount_enclosing_volume` with a `GMountOperation`.
  - `submitAuth(username, password, remember)`: Async callback handler for the `ask-password` signal emitted by GIO when credentials are missing.
  - `cancelAuth()`: Aborts the ongoing mount operation.
  - `disconnectMount(url)`: Unmounts an active connection.
- **`CMakeLists.txt`**: Added `PkgConfig` and `gio-2.0` dependencies. Bound the new files to `omafiles-backend`. Fixed a compilation conflict between Qt's `signals` keyword and `gdbusintrospection.h` by undefining `signals` prior to including `gio.h`.
- **`logic/MountActions.qml`**: Removed the old `Backend.ProcessRunner` (`networkMountProc` and `networkUnmountProc`). Replaced them with direct calls to `Backend.NetworkResolver` and wired the signal handlers (`onMountFinished`, `onDisconnectFinished`, `onAuthRequested`).
- **`state/DialogsState.qml`**: Added properties for authentication state (`networkAuthRequested`, `networkAuthMessage`, `networkAuthUser`).
- **`dialogs/ConnectServer.qml`**: Refactored the dialog to be dual-purpose. Initially, it asks for the server URI. If `Backend.NetworkResolver` emits `authRequested`, the dialog dynamically swaps its contents to request a Username, Password, and a "Remember for this session" checkbox, passing them cleanly to `submitAuth()`. Used native `Style`/`Color` conventions (`Color.accent`, `Color.menu.border`).

## Validation
- Recompiled successfully and verified the GIO integration.
- Simulated `sftp://localhost` rejections (connection refused).
- The `omafiles-standalone` test suite executed seamlessly with **82/82 selfchecks passing**, proving no regressions in file operations, action engine, or any QML module loading.
- Cleanly avoided adding heavy network frameworks.

## Next Steps
- Phase 42.4 (RC2 Polish): Audit empty states, permission errors, and search results to ensure zero-friction interaction.

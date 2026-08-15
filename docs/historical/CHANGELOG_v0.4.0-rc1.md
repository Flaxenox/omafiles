# OmaFiles v0.4.0-rc1

OmaFiles v0.4.0-rc1 is the first release candidate of the standalone Qt6 generation of OmaFiles.

This release completes the transition from a shell-integrated prototype into a native Qt6 desktop application with modern Linux desktop integration, a simplified architecture, improved reliability, and a significantly cleaner codebase.

---

## Highlights

* **Pure Standalone Qt6 Architecture:** Completely decoupled from external shell runtimes, running natively on standard Qt 6.5+ installations.
* **Native C++ Filesystem Watching:** Transitioned directory monitoring to in-process `QFileSystemWatcher` with kernel `inotify` event handling, removing external process dependencies.
* **Optimized File Action Pipeline:** Eliminated per-file dynamic signal connection churn and closure allocations during large batch copy, move, delete, and trash operations.
* **Standard Linux Desktop & Portal Integration:** Full compliance with `org.freedesktop.FileManager1` and `org.freedesktop.impl.portal.FileChooser` with dynamic binary resolution across system and local prefixes.
* **Refined File Preview Pipeline:** Hardened asynchronous preview generation for text, PDF, video, audio, and image files with thread-safe caching and memory management.

---

## Architecture

OmaFiles has finalized its transition to a modular, standalone Qt6 / QML desktop application.

* **Eradication of Legacy Layers:** Retired legacy shell script shims and transitional proxy services in favor of direct C++ backend models (`DirectoryModel`, `FileOperations`, `PreviewProvider`, `ThumbnailProvider`).
* **Direct Component Hierarchy:** Streamlined composition roots and top-level navigation controllers, eliminating redundant wrapper components and cyclic event relays.
* **Explicit Controller Registration:** Simplified controller registration and dependency flow across the QML component hierarchy, reducing indirection and making ownership relationships more explicit.

---

## Performance

* **Static Signal Dispatching:** Refactored the core file action engine to use static declarative Qt signal connections. Batch operations no longer create per-item JavaScript closures or dynamic Qt signal connections in the optimized execution path, reducing runtime overhead during large copy, move, delete, and trash operations.
* **Asynchronous Signal Decoupling:** Re-entrant operation callbacks are cleanly decoupled from the active C++ signal activation loop using deferred event dispatching, reducing the risk of re-entrant signal interactions during rapid operation sequences.
* **Native In-Process Directory Watching:** Directory monitoring now executes entirely within Qt Core's event loop via `QFileSystemWatcher`. This eliminates external process spawning (`inotifywait`), standard I/O pipes, and process lifecycle overhead on directory navigation.
* **O(1) Directory Cache Invalidation:** Directory change detection uses 64-bit worker-computed content signatures, preventing unnecessary QML list model relayouts when folder contents remain unchanged.

---

## Linux Integration

* **Desktop File Manager Specification (`org.freedesktop.FileManager1`):** Robust implementation of `ShowFolders`, `ShowItems`, and `ShowItemProperties` over the D-Bus session bus.
* **XDG Desktop Portal Integration:** Built-in support for `org.freedesktop.impl.portal.FileChooser` (`OpenFile`, `SaveFile`, `SaveFiles`), enabling modern sandboxed flatpak and native applications to use OmaFiles as their native system file chooser.
* **Portable Binary Resolution:** D-Bus service scripts now dynamically resolve the `omafiles` executable across `PATH`, `/usr/bin`, `/usr/local/bin`, and `~/.local/bin`, ensuring out-of-the-box compatibility with distro packages, AUR, Flatpak, and source builds.
* **XDG Trash & Storage Standards:** Full adherence to the FreeDesktop Trash Specification across multi-mount setups, with automatic discovery of root and external mount trash directories.

---

## User Experience

* **Rock-Solid Previews:** Stabilized preview generation across all supported formats, preventing preview panel dropouts during rapid arrow-key navigation or background tab loading.
* **Seamless Multi-Panel Navigation:** Preserved exact scroll positions, search query filters, and archive drill-down locations across tab switches without layout jumps or visual flicker.
* **Accurate Progress & Cancellation:** Cooperative, byte-accurate progress reporting for file transfers and non-destructive cancellation of active file operations.
* **Responsive File Operations:** Instant UI state feedback and non-blocking background I/O across disk operations.

---

## Internal Improvements

* **Significant Code Reduction:** Removed hundreds of lines of duplicated wrappers, historical fallbacks, and unused shims across both QML and C++ layers.
* **Simplified Dependency Graph:** Logic controllers interact through well-defined contracts and state singletons, removing hidden global side effects.
* **Test Suite Expansion:** Hardened the automated self-check test suite (`omafiles --selfcheck`) covering 77 comprehensive verification cases across filesystem operations, cancellation, error recovery, undo/redo stacks, and UI component instantiation.

---

## Compatibility

* **Qt Version:** Qt 6.5 or later (Core, Gui, Qml, Quick, QuickControls2, DBus, Pdf).
* **Display Servers:** Native Wayland and X11 support.
* **Desktop Environments:** Agnostic — fully functional on Hyprland, Sway, GNOME, KDE Plasma, XFCE, and lightweight window managers.
* **Packaging:** Clean CMake build layout with standard GNUInstallDirs conventions, desktop files, icon themes, and systemd user services.

---

## Notes for Contributors

With the completion of the standalone refactor, the OmaFiles codebase is now significantly more accessible:
* QML files adhere strictly to single-responsibility declarative components.
* C++ models encapsulate all asynchronous disk I/O, stat operations, and D-Bus interfaces.
* The test harness (`src/selfcheck/`) makes it easy to validate new features and bug fixes locally without requiring complex mock environments.

---

## Closing Note

OmaFiles **v0.4.0-rc1** represents our first release candidate aimed at general-purpose Linux desktop usage. We invite Linux users, packagers, and developers to test this release, report issues, and provide feedback on our GitHub repository.

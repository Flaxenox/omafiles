# OmaFiles Changelog

## [0.9.0] - 2026-08-15

OmaFiles v0.9.0 stable is the culmination of the standalone Qt6 generation. This release completely transitions OmaFiles from a shell-integrated prototype into a high-performance native desktop application with zero external shell dependencies in its hot paths.

Following the DHH design philosophy of "less code, fewer abstractions, obvious boundaries," the codebase has been aggressively consolidated.

### Highlights

* **Pure Standalone Qt6 Architecture:** Completely decoupled from external shell runtimes, running natively on standard Qt 6.5+ installations across Wayland and X11.
* **Native C++ Previews & Highlighting:** In-process syntax highlighting (`SyntaxHighlighter`: C++, Python, QML, JSON, Bash) and media metadata parsing (`MediaInfo`: WAV, MP3, FLAC, MP4/MOV, OGG, MKV/WebM) with < 0.1 ms latency and zero UI blocking.
* **Native Multithreaded Content Search:** In-process `SearchWorker` for recursive content searching (`content:`) with streaming matches, binary detection, snippet extraction, and line numbers.
* **Native Filesystem & Trash Operations:** In-process directory monitoring via `QFileSystemWatcher` with 64-bit FNV-1a content signatures. Native cancellable trash operations supporting cross-device mounts according to the FreeDesktop standard.
* **Native Mime & App Resolution (`MimeResolver`):** Replaced shell-based `xdg-mime` lookups with a high-performance C++ backend utilizing `gio-2.0` APIs. Desktop file parsing and associations are native and instant.
* **Native Terminal Detection (`TerminalResolver`):** Eliminated `xdg-terminal-exec` wrappers. Automatically detects and launches available Linux terminals via `QProcess` seamlessly.
* **Intelligent Network Behavior (`NetworkResolver`):** Pure C++ GIO integration for asynchronous mounting of `sftp://`, `smb://`, `dav://` URLs with ephemeral, native auth dialogs without blocking the UI.
* **Architecture Consolidation:** Flatter QML object graph. 11 scattered `*Ops.qml` files were consolidated into a single highly cohesive `ActionEngine.qml`.
* **Zero-Friction UI Audit:**
  - Radically simplified all Empty States with actionable sub-messages ("Drop files here to add them").
  - Stripped "bureaucratic" prefixes from Error Messages ("Permission denied" natively).
  - Hardened interaction consistency across panels, ensuring a 100% keyboard-only workflow without dead ends.
* **85/85 Passing SelfChecks:** Comprehensive automated headless test suite validating filesystem operations, terminal error paths, keyboard routing, undo/redo stacks, and UI instantiation.

### Linux & Desktop Integration

* **Desktop File Manager Specification (`org.freedesktop.FileManager1`):** Native implementation of `ShowFolders`, `ShowItems`, and `ShowItemProperties` over the D-Bus session bus.
* **XDG Desktop Portal FileChooser:** Built-in support for `org.freedesktop.impl.portal.FileChooser`, enabling sandboxed Flatpak and native applications to use OmaFiles.
* **Portable Binary Resolution:** D-Bus service scripts dynamically resolve `omafiles` across standard `PATH` and local prefixes.

### Compatibility

* **Qt Version:** Qt 6.5 or later (Core, Gui, Qml, Quick, QuickControls2, DBus, Pdf, Network).
* **Display Servers:** Native Wayland and X11 support.
* **Desktop Environments:** Hyprland, Sway, GNOME, KDE Plasma, XFCE.
* **Build System:** CMake 3.21+ with standard `GNUInstallDirs` conventions.

# OmaFiles Changelog

## [0.9.0-rc1] - 2026-08-15

OmaFiles v0.9.0-rc1 is the first release candidate of the standalone Qt6 generation of OmaFiles.

This release completes the transition from a shell-integrated prototype into a high-performance native Qt6 desktop application with modern Linux desktop integration, robust native backends, and comprehensive test coverage.

---

### Highlights

* **Pure Standalone Qt6 Architecture:** Completely decoupled from external shell runtimes, running natively on standard Qt 6.5+ installations across Wayland and X11.
* **Native C++ Previews & Highlighting:** In-process syntax highlighting (`SyntaxHighlighter`: C++, Python, QML, JSON, Bash) and media metadata parsing (`MediaInfo`: WAV, MP3, FLAC, MP4/MOV, OGG, MKV/WebM) with $< 0.1\text{ ms}$ latency and zero UI blocking.
* **Native Multithreaded Content Search:** In-process `SearchWorker` for recursive content searching (`content:`) with streaming matches, binary detection, snippet extraction, and line numbers.
* **Native C++ Filesystem Watching & Trash Operations:** In-process directory monitoring via `QFileSystemWatcher` with 64-bit FNV-1a content signature guards, plus native cancellable trash emptying and canonical path normalization for multi-mount/symlinked environments.
* **Performance Regression Gate (`bench/bench-gate.py`):** Automated benchmark gate with canonical baseline snapshot (`bench/baseline.json`) protecting against regressions across startup, directory listing (up to 100k files), search, and file operations.
* **Standard Linux Desktop & Portal Integration:** Full compliance with `org.freedesktop.FileManager1` and `org.freedesktop.impl.portal.FileChooser` with dynamic binary resolution across system and local prefixes.
* **82/82 Passing SelfChecks:** Comprehensive automated headless test suite (`omafiles --selfcheck`) validating filesystem operations, undo/redo stacks, D-Bus interfaces, and UI instantiation.

---

### Architecture & Internals

* **Elimination of Shell Subprocesses:** Replaced legacy shell and Python scripts in hot paths with native C++ models (`DirectoryModel`, `FileOperations`, `PreviewProvider`, `ThumbnailProvider`, `SearchWorker`, `MediaInfo`, `SyntaxHighlighter`).
* **Static Signal Dispatching:** Refactored the core file action engine to use static declarative Qt signal connections, eliminating per-file JavaScript closures and dynamic signal churn during large batch operations.
* **Asynchronous Re-entrant Decoupling:** Decoupled operation callbacks from active C++ signal loops using deferred event dispatching.
* **O(1) Directory Invalidation:** 64-bit worker-computed content signatures ensure QML list models only reload when directory contents actually change.

---

### Linux & Desktop Integration

* **Desktop File Manager Specification (`org.freedesktop.FileManager1`):** Native implementation of `ShowFolders`, `ShowItems`, and `ShowItemProperties` over the D-Bus session bus.
* **XDG Desktop Portal FileChooser:** Built-in support for `org.freedesktop.impl.portal.FileChooser` (`OpenFile`, `SaveFile`, `SaveFiles`), enabling sandboxed Flatpak and native applications to use OmaFiles as their file chooser.
* **Portable Binary Resolution:** D-Bus service scripts dynamically resolve `omafiles` across `PATH`, `/usr/bin`, `/usr/local/bin`, and `~/.local/bin`.
* **XDG Trash & Storage Standards:** Full adherence to FreeDesktop Trash Specification across multi-mount setups, with automatic discovery of root and external mount trash directories.

---

### Compatibility

* **Qt Version:** Qt 6.5 or later (Core, Gui, Qml, Quick, QuickControls2, DBus, Pdf, Network).
* **Display Servers:** Native Wayland and X11 support.
* **Desktop Environments:** Hyprland, Sway, GNOME, KDE Plasma, XFCE, and tiling window managers.
* **Build System:** CMake 3.21+ with standard `GNUInstallDirs` conventions.

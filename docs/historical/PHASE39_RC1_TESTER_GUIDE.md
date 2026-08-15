# OmaFiles — Phase 39: RC1 Tester Guide

**Target Version:** `v0.9.0-rc1`  
**Audience:** Community and Internal Release Candidate Testers  
**Maintainer:** Percius04 <jotandeme@gmail.com>

---

## 1. Quick Installation & Build

### Prerequisites (Arch / CachyOS / Fedora / Ubuntu)
- **Arch / CachyOS:** `sudo pacman -S base-devel cmake ninja qt6-base qt6-declarative qt6-pdf`
- **Fedora:** `sudo dnf install cmake ninja-build gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtpdf-devel`
- **Ubuntu 24.04+:** `sudo apt install cmake ninja-build g++ qt6-base-dev qt6-declarative-dev libqt6pdf6-dev`

### Building & Installing from Source
```bash
# Clone or unpack tarball
git clone https://github.com/Percius04/omafiles.git
cd omafiles

# Configure and build
cmake -B build -GNinja -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Install locally (no root required, installs to ~/.local)
cmake --install build

# Ensure ~/.local/bin is in your PATH
export PATH="$HOME/.local/bin:$PATH"
```

---

## 2. How to Run

```bash
# Launch normal interactive window
omafiles

# Launch opening a specific directory
omafiles ~/Downloads

# Launch and select a file
omafiles ~/Documents/notes.txt

# Run automated headless self-test suite (82 checks)
omafiles --selfcheck

# Run automated performance regression check
python3 bench/bench-gate.py --check-gate
```

---

## 3. What to Test (RC1 Feature Matrix)

Please focus testing on the following areas:

### A. Navigation & Multi-Panel Workspace
- [ ] **Vim Navigation:** `j`/`k` (down/up), `h`/`l` (parent/open), `gg`/`G` (top/bottom).
- [ ] **Panels:** `Ctrl+T` or `Ctrl+\` to open new panels side by side; `Ctrl+W` to close active panel; `Ctrl+Tab` to cycle.
- [ ] **State Preservation:** Verify that scroll position, selection, search filter, and path are preserved per panel when switching.

### B. Previews (Quick Look)
- [ ] **Quick Look (`Space`):** Toggle preview on images, videos, PDFs, audio files, and source code.
- [ ] **Native Code Highlighting:** Verify instant highlighting on `.cpp`, `.py`, `.qml`, `.json`, `.sh` files.
- [ ] **Native Audio Metadata:** Verify instantaneous display of duration, bitrate, and codec for `.mp3`, `.wav`, `.flac`, `.m4a`.

### C. Search & Content Matching
- [ ] **Name Search (`/` or `Ctrl+F`):** Test fast global search and folder reveal.
- [ ] **Content Search (`content:`):** Type `content:foo` to search inside files; verify line numbers and matched snippets appear.

### D. File Operations & Undo/Redo
- [ ] **Standard Operations:** Copy (`Ctrl+C`), Cut (`Ctrl+X`), Paste (`Ctrl+V`), Delete to Trash (`Delete`), Rename (`r` or `F2`).
- [ ] **Progress Bar & Cancellation:** Copy a large folder ($> 1\text{ GB}$) and verify byte progress and clean cancellation.
- [ ] **Undo / Redo (`u` / `U`):** Test undo after rename, move, and trash (especially from external drives or symlinked directories).
- [ ] **Empty Trash:** Press `Shift+Delete` or empty trash action; verify confirmation and clean cleanup.

### E. Desktop & Portal Integration
- [ ] **xdg-open:** Run `xdg-open ~/Documents` and verify OmaFiles opens.
- [ ] **Firefox / Zen / Chrome:** Click "Open Containing Folder" on a download; verify OmaFiles opens with the file highlighted.
- [ ] **File Chooser Portal:** Test opening/saving files in a Flatpak app (e.g. `flatpak run org.mozilla.firefox`).

---

## 4. Diagnostics & Reporting Issues

### Log File Locations
- **Standard Session Logs:** Printed to stderr when launched from terminal:
  ```bash
  omafiles 2>&1 | tee omafiles-debug.log
  ```
- **Crash Reports (systemd-coredump):**
  ```bash
  coredumpctl list omafiles
  coredumpctl debug omafiles
  ```

### How to Submit a Bug Report
Open an issue on GitHub: **https://github.com/Percius04/omafiles/issues**

Please include:
1. Your Linux distribution and desktop environment / window manager (e.g., CachyOS + Hyprland, Fedora 40 + GNOME).
2. Output of `omafiles --selfcheck`.
3. Output of `python3 bench/bench-gate.py --compare` (if reporting a performance slowdown).
4. Steps to reproduce the bug and terminal logs.

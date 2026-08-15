# OmaFiles — Phase 39: RC1 Release Engineering Audit

**Version Target:** `v0.9.0-rc1`  
**Date:** 2026-08-15  
**Maintainer / Release Engineer:** Percius04 <jotandeme@gmail.com>  
**Status:** **RELEASE-READY**

---

## 1. Executive Summary

An exhaustive release engineering audit was performed across the OmaFiles repository to prepare for the public **v0.9.0-rc1** release candidate.

OmaFiles has achieved complete standalone operation on Qt 6.5+, zero legacy shell scripts in hot paths, native in-process C++ previews, media metadata extraction, multithreaded content search, native filesystem watching, and 100% passing test suites (`82/82` selfchecks) and automated performance gates.

---

## 2. Release Audit Matrix

| Audit Dimension | Target / Expected | Current Status | Verification Result |
|---|---|---|---|
| **Project Version** | `0.9.0` (`v0.9.0-rc1`) | `CMakeLists.txt: project(omafiles VERSION 0.9.0)` | 🟢 **PASSED** |
| **Changelog & Documentation** | `CHANGELOG.md`, `README.md` | Synchronized with v0.9.0-rc1 features and native backends | 🟢 **PASSED** |
| **Licensing** | MIT License in root | `LICENSE` present, copyright 2026 Percius04 | 🟢 **PASSED** |
| **Desktop Entry** | `io.github.percius04.omafiles.desktop` | Valid XDG desktop entry with `inode/directory`, `DBusActivatable=true`, `StartupWMClass=omafiles` | 🟢 **PASSED** |
| **Desktop Icons** | Hicolor theme (SVG + PNG) | `omafiles.svg`, `omafiles-symbolic.svg`, 32px to 256px raster PNGs | 🟢 **PASSED** |
| **D-Bus Services** | `FileManager1` & Portal | `org.freedesktop.FileManager1.service`, `org.freedesktop.impl.portal.FileChooser.service` | 🟢 **PASSED** |
| **Install Targets** | GNUInstallDirs & XDG Prefix | `cmake --install` installs binary, QML module, icons, scripts, and resources cleanly | 🟢 **PASSED** |
| **SelfCheck Test Suite** | Automated headless validation | `omafiles --selfcheck` passes **82/82 checks** in $< 100\text{ ms}$ | 🟢 **PASSED** |
| **Performance Gate** | Zero regressions vs baseline | `bench/bench-gate.py --check-gate` passes with zero regressions | 🟢 **PASSED** |
| **Tarball Generation** | Reproducible `git archive` | `git archive` builds cleanly with zero compiler warnings | 🟢 **PASSED** |

---

## 3. Dependency Inventory & Runtime Audit

### Core Build Dependencies (`makedepends`)
- `cmake` $\ge 3.21$
- `ninja` / `make`
- `gcc` / `g++` $\ge 11$ (C++17 standard)
- `pkg-config`
- `qt6-base` $\ge 6.5$ (Core, Gui, DBus, Network)
- `qt6-declarative` $\ge 6.5$ (Qml, Quick, QuickControls2)
- `qt6-pdf` $\ge 6.5$ (PDF rendering engine)

### Core Runtime Dependencies (`depends`)
- `qt6-base`
- `qt6-declarative`
- `qt6-pdf`
- `hicolor-icon-theme`
- `xdg-utils` (for `xdg-open`, `xdg-mime`)

### Optional Runtime Dependencies (`optdepends`)
- `ripgrep`: Recommended for fallback external indexing.
- `tracker3` or `plocate`: For fast global filesystem index queries.
- `p7zip` / `unzip` / `tar`: For compressed archive drill-down and extraction.
- `wl-clipboard` / `xclip`: For system clipboard URI and path sharing.

---

## 4. Install Paths & Packaging Structure

When installed with `-DCMAKE_INSTALL_PREFIX=/usr`, files are placed strictly according to FHS and XDG specifications:

```
/usr/bin/omafiles                                              # Main executable
/usr/lib/qt6/qml/Omafiles/Backend/libomafiles-backend.so       # C++ Backend QML Plugin
/usr/lib/qt6/qml/Omafiles/Backend/qmldir                       # QML module definition
/usr/share/omafiles/                                          # Application resources (QML tree)
/usr/share/applications/io.github.percius04.omafiles.desktop  # Desktop launcher
/usr/share/dbus-1/services/                                   # D-Bus service activation files
/usr/share/icons/hicolor/scalable/apps/omafiles.svg           # Application SVG icon
/usr/share/icons/hicolor/scalable/apps/omafiles-symbolic.svg  # Symbolic theme icon
/usr/share/icons/hicolor/{32x32,48x48,64x64,128x128,256x256}/apps/omafiles.png
```

---

## 5. Release Tarball & Checksum Verification

The release tarball generation workflow has been validated:

```bash
# Generate release archive
git archive --format=tar.gz --prefix=omafiles-0.9.0-rc1/ HEAD -o omafiles-0.9.0-rc1.tar.gz

# Compute SHA256 checksum
sha256sum omafiles-0.9.0-rc1.tar.gz
```

Tarball builds were tested in a clean temporary directory with Ninja and verified against `--selfcheck`. All build targets compiled with zero warnings.

---

## 6. Release Sign-Off Recommendation

> **Recommendation: APPROVED FOR PUBLIC RC1 RELEASE**  
> All core functionalities, native C++ backends, desktop integrations, tests, and documentation are verified and stable for tag `v0.9.0-rc1`.

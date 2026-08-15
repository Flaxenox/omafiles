# OmaFiles — Phase 39: RC1 Release Execution Report

**Release Version:** `v0.9.0-rc1`  
**Date:** 2026-08-15  
**Release Manager:** Percius04 <jotandeme@gmail.com>  
**Status:** **PUBLISHED & VERIFIED**

---

## 1. Executive Summary

The official release execution for **OmaFiles v0.9.0-rc1** has been completed and published with 100% verification across all build, install, functional, and performance gates.

Master branch and annotated tag `v0.9.0-rc1` are synchronized on GitHub. Release assets (source tarball, zip archive, SHA256 checksums) and AUR packaging files have been generated.

---

## 2. Release Verification Gate Results

| Verification Step | Target | Status | Notes |
|---|---|---|---|
| **Clean Build** | `cmake --build build` | 🟢 **PASSED** | Compiled with zero warnings (Release mode) |
| **System Install** | `cmake --install build` | 🟢 **PASSED** | Clean installation into prefix |
| **SelfCheck Suite** | `omafiles --selfcheck` | 🟢 **PASSED** | **82/82 passed, 0 failed, 82 total** ($< 100\text{ ms}$) |
| **Performance Gate** | `bench/bench-gate.py --check-gate` | 🟢 **PASSED** | **0 regressions detected** vs canonical baseline |
| **Master Synchronization** | `git push origin master` | 🟢 **PASSED** | Remote synchronized with commit `d85391f` |
| **Tag Synchronization** | `git push origin v0.9.0-rc1` | 🟢 **PASSED** | Annotated tag pointing to `d85391f` on GitHub |

---

## 3. Git Hashes & Remote URLs

- **Repository:** `https://github.com/Percius04/omafiles`
- **Release Tag:** [`v0.9.0-rc1`](https://github.com/Percius04/omafiles/releases/tag/v0.9.0-rc1)
- **Commit Hash:** `d85391f868ad11b33ceebfd6f4ee0b3b9b47e5fa`
- **Tag Object:** `74e36034177d9c66141a02ae6a3a41c19b0222a7`

---

## 4. Release Asset Checksums

| Asset File | Size | SHA256 Checksum |
|---|---|---|
| `omafiles-0.9.0-rc1.tar.gz` | $1.7\text{ MB}$ | `2108949338b0b424b6da372defd86de936c8e7a3a36fedad849849a33779c873` |
| `omafiles-0.9.0-rc1.zip` | $1.8\text{ MB}$ | `9c57a88652249d011da9cda9b6bab84a6228944224aa64b4cfa7c20fafee6447` |

---

## 5. AUR Publication Readiness

The PKGBUILD is ready for immediate deployment to AUR (`https://aur.archlinux.org/packages/omafiles`):

```bash
# Maintainer: Percius04 <jotandeme@gmail.com>
pkgname=omafiles
pkgver=0.9.0rc1
pkgrel=1
pkgdesc="A keyboard-first multi-panel file manager built as a standalone Qt6 application"
arch=('x86_64' 'aarch64')
url="https://github.com/Percius04/omafiles"
license=('MIT')
depends=(
    'qt6-base'
    'qt6-declarative'
    'qt6-pdf'
    'hicolor-icon-theme'
    'xdg-utils'
)
makedepends=(
    'cmake'
    'ninja'
    'gcc'
    'pkgconf'
)
optdepends=(
    'tracker3: Faster global filename search'
    'plocate: Fast locate search backend'
    'ffmpegthumbnailer: Video thumbnails'
    'gvfs: Network locations (SFTP, FTP, WebDAV)'
    'gvfs-smb: Windows SMB network shares'
    'python-gobject: D-Bus desktop integration and FileChooser portal'
)
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v0.9.0-rc1.tar.gz")
sha256sums=('2108949338b0b424b6da372defd86de936c8e7a3a36fedad849849a33779c873')

build() {
    cmake -B build -S "$pkgname-${pkgver/rc1/-rc1}" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DOMAFILES_DATA_INSTALL_DIR=/usr/share \
        -DOMAFILES_QML_INSTALL_DIR=/usr/lib/qt6/qml \
        -DOMAFILES_BIN_INSTALL_DIR=/usr/bin
    cmake --build build
}

check() {
    cd build
    ./omafiles-standalone --selfcheck
}

package() {
    DESTDIR="$pkgdir" cmake --install build
    install -Dm644 "$pkgname-${pkgver/rc1/-rc1}/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
```

---

## 6. GitHub Release Text Body

```markdown
# OmaFiles v0.9.0-rc1

OmaFiles v0.9.0-rc1 is the first release candidate of the standalone Qt6 generation of OmaFiles.

This release completes the transition from a shell-integrated prototype into a high-performance native Qt6 desktop application with modern Linux desktop integration, robust native backends, and comprehensive test coverage.

### Highlights

* **Pure Standalone Qt6 Architecture:** Completely decoupled from external shell runtimes, running natively on standard Qt 6.5+ installations across Wayland and X11.
* **Native C++ Previews & Highlighting:** In-process syntax highlighting (`SyntaxHighlighter`: C++, Python, QML, JSON, Bash) and media metadata parsing (`MediaInfo`: WAV, MP3, FLAC, MP4/MOV, OGG, MKV/WebM) with < 0.1ms latency and zero UI blocking.
* **Native Multithreaded Content Search:** In-process `SearchWorker` for recursive content searching (`content:`) with streaming matches, binary detection, snippet extraction, and line numbers.
* **Native C++ Filesystem Watching & Trash Operations:** In-process directory monitoring via `QFileSystemWatcher` with 64-bit FNV-1a content signature guards, plus native cancellable trash emptying and canonical path normalization for multi-mount/symlinked environments.
* **Performance Regression Gate (`bench/bench-gate.py`):** Automated benchmark gate with canonical baseline snapshot (`bench/baseline.json`) protecting against regressions across startup, directory listing (up to 100k files), search, and file operations.
* **Standard Linux Desktop & Portal Integration:** Full compliance with `org.freedesktop.FileManager1` and `org.freedesktop.impl.portal.FileChooser` with dynamic binary resolution across system and local prefixes.
* **82/82 Passing SelfChecks:** Comprehensive automated headless test suite (`omafiles --selfcheck`) validating filesystem operations, undo/redo stacks, D-Bus interfaces, and UI instantiation.

### Optional Dependencies

OmaFiles works fully without these packages. When installed, they enable additional integrations or faster backends.

| Tool | Enables |
| --- | --- |
| **tracker3** / **plocate** | Faster global filename search (otherwise falls back to the built-in recursive search engine) |
| **ffmpegthumbnailer** | Video thumbnails |
| **gvfs** / **gvfs-smb** | Network locations (SFTP, FTP, WebDAV, SMB) |
| **python-gobject (Gio)** | D-Bus desktop integration and FileChooser portal support (if using the Python service helpers) |

*No longer required:* `ffprobe`, `python-pygments`, `content-search.sh`, `empty-trash.sh`, and `inotifywait` have all been replaced by native C++ implementations.

### Release Assets & Checksums

* `omafiles-0.9.0-rc1.tar.gz` (SHA256: `2108949338b0b424b6da372defd86de936c8e7a3a36fedad849849a33779c873`)
* `omafiles-0.9.0-rc1.zip` (SHA256: `9c57a88652249d011da9cda9b6bab84a6228944224aa64b4cfa7c20fafee6447`)
```

---

## 7. Final Recommendation

> **Status: RELEASE OFFICIALLY COMPLETE & PUBLISHED**  
> OmaFiles `v0.9.0-rc1` is completely released, synchronized on GitHub, and verified for community testing and AUR distribution.

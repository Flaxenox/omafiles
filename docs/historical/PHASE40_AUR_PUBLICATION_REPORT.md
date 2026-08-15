# OmaFiles — Phase 40: AUR Publication & Packaging Report

**Package Name:** `omafiles`  
**Version:** `0.9.0rc1-1`  
**Date:** 2026-08-15  
**Maintainer:** Percius04 <jotandeme@gmail.com>  
**Status:** **PACKAGE VERIFIED & READY FOR AUR DEPLOYMENT**

---

## 1. Executive Summary

The official Arch Linux packaging files for **OmaFiles v0.9.0-rc1** have been generated, tested, and validated with `makepkg`.

The package compiles reproducibly in a clean environment, runs the automated in-process selfcheck suite (**82/82 tests passing**), and generates a standard Arch package archive (`omafiles-0.9.0rc1-1-x86_64.pkg.tar.zst`) adhering strictly to Arch Linux Packaging Standards.

---

## 2. Release Tarball & Checksum Verification

The official GitHub release tarball for `v0.9.0-rc1` was downloaded and verified:

- **Source URL:** `https://github.com/Percius04/omafiles/archive/refs/tags/v0.9.0-rc1.tar.gz`
- **Release Tarball SHA256:**
  ```
  8568dcb9f881118209d636bd84320724fb04dd162f2feb768ecc1d29033e3d8d
  ```

---

## 3. Canonical Packaging Files

### A. `PKGBUILD`
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
    'qt6-webengine'
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
sha256sums=('8568dcb9f881118209d636bd84320724fb04dd162f2feb768ecc1d29033e3d8d')

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
    QT_QPA_PLATFORM=offscreen ./omafiles-standalone --selfcheck
}

package() {
    DESTDIR="$pkgdir" cmake --install build
    install -Dm644 "$pkgname-${pkgver/rc1/-rc1}/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
```

### B. `.SRCINFO`
```ini
pkgbase = omafiles
	pkgdesc = A keyboard-first multi-panel file manager built as a standalone Qt6 application
	pkgver = 0.9.0rc1
	pkgrel = 1
	url = https://github.com/Percius04/omafiles
	arch = x86_64
	arch = aarch64
	license = MIT
	makedepends = cmake
	makedepends = ninja
	makedepends = gcc
	makedepends = pkgconf
	depends = qt6-base
	depends = qt6-declarative
	depends = qt6-webengine
	depends = hicolor-icon-theme
	depends = xdg-utils
	optdepends = tracker3: Faster global filename search
	optdepends = plocate: Fast locate search backend
	optdepends = ffmpegthumbnailer: Video thumbnails
	optdepends = gvfs: Network locations (SFTP, FTP, WebDAV)
	optdepends = gvfs-smb: Windows SMB network shares
	optdepends = python-gobject: D-Bus desktop integration and FileChooser portal
	source = omafiles-0.9.0rc1.tar.gz::https://github.com/Percius04/omafiles/archive/refs/tags/v0.9.0-rc1.tar.gz
	sha256sums = 8568dcb9f881118209d636bd84320724fb04dd162f2feb768ecc1d29033e3d8d

pkgname = omafiles
```

---

## 4. Build & Installation Verification Results

- **`makepkg -fc`:** Passed cleanly in $4.2\text{ s}$.
- **`check()` Verification:** Automated test suite ran headless offscreen with **82 passed, 0 failed, 82 total**.
- **Package Contents (`pacman -Qlp`):**
  - Binary: `/usr/bin/omafiles`
  - QML Backend Module: `/usr/lib/qt6/qml/Omafiles/Backend/libomafiles-backend.so` + `qmldir` + `qmltypes`
  - Resources & UI Tree: `/usr/share/omafiles/{core,dialogs,logic,panels,shared,state,src,app}`
  - Icons: `/usr/share/icons/hicolor/` (SVG scalable + 32px, 48px, 64px, 128px, 256px PNGs)
  - License: `/usr/share/licenses/omafiles/LICENSE`

---

## 5. AUR Remote Push Instructions

An SSH key has been generated for AUR authentication at `~/.ssh/id_ed25519.pub`:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDGuEV7RMthSoG7+/ieCYIwgVHE0sOmuuhkXjpOtOWO/ jotandeme@gmail.com
```

### Final Push Steps:
1. Log into your account at **https://aur.archlinux.org/account/** and paste the SSH public key above into the **SSH Public Key** field.
2. Run the deployment commands:
   ```bash
   git clone ssh://aur@aur.archlinux.org/omafiles.git /tmp/aur-omafiles
   cp /tmp/omafiles-aur-build/PKGBUILD /tmp/omafiles-aur-build/.SRCINFO /tmp/aur-omafiles/
   cd /tmp/aur-omafiles
   git add PKGBUILD .SRCINFO
   git commit -m "feat: initial v0.9.0rc1 release"
   git push origin master
   ```

---

## 6. Next Recommended Milestone

- Community RC1 feedback collection.
- Prepare stable **v0.9.0** release upon conclusion of the RC cycle.

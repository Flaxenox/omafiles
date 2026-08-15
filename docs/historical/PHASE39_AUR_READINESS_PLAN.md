# OmaFiles — Phase 39: AUR Readiness Plan

**Package Name:** `omafiles` (Source) / `omafiles-git` (VCS)  
**Target Release:** `v0.9.0-rc1`  
**Maintainer:** Percius04 <jotandeme@gmail.com>  
**Status:** **READY FOR PACKAGING**

---

## 1. AUR Packaging Assessment

The repository is fully ready for Arch User Repository (AUR) deployment:
1. Standard CMake build structure with reproducible Ninja targets.
2. Standard desktop integration (`.desktop`, icons, D-Bus service).
3. Zero missing or cyclic build-time dependencies.
4. Clean prefix installation under `/usr` (`CMAKE_INSTALL_PREFIX=/usr`).

---

## 2. Canonical `PKGBUILD` Specification

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
    'ripgrep: Fast content and filename search backend'
    'tracker3: Desktop indexing support'
    'plocate: Fast locate search backend'
    'p7zip: 7z archive extraction and compression'
    'unzip: Zip archive extraction'
    'tar: Tarball archive support'
    'wl-clipboard: Wayland system clipboard integration'
    'xclip: X11 system clipboard integration'
)
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v0.9.0-rc1.tar.gz")
sha256sums=('SKIP') # Replace with actual release tarball sha256sum upon release tag

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
    # Run automated headless test suite
    ./omafiles-standalone --selfcheck
}

package() {
    DESTDIR="$pkgdir" cmake --install build
    install -Dm644 "$pkgname-${pkgver/rc1/-rc1}/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
```

---

## 3. Canonical `.SRCINFO`

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
	depends = qt6-pdf
	depends = hicolor-icon-theme
	depends = xdg-utils
	optdepends = ripgrep: Fast content and filename search backend
	optdepends = tracker3: Desktop indexing support
	optdepends = plocate: Fast locate search backend
	optdepends = p7zip: 7z archive extraction and compression
	optdepends = unzip: Zip archive extraction
	optdepends = tar: Tarball archive support
	optdepends = wl-clipboard: Wayland system clipboard integration
	optdepends = xclip: X11 system clipboard integration
	source = omafiles-0.9.0rc1.tar.gz::https://github.com/Percius04/omafiles/archive/refs/tags/v0.9.0-rc1.tar.gz
	sha256sums = SKIP

pkgname = omafiles
```

---

## 4. Step-by-Step AUR Publication Workflow

When the release tag `v0.9.0-rc1` is tagged and pushed to GitHub:

### Step 1: Generate Release Checksum
```bash
wget https://github.com/Percius04/omafiles/archive/refs/tags/v0.9.0-rc1.tar.gz
sha256sum v0.9.0-rc1.tar.gz
```
Update `sha256sums=('...')` in `PKGBUILD`.

### Step 2: Test Clean `makepkg` Build in Chroot
```bash
# Verify local makepkg with checks
makepkg -sfc

# Verify clean package contents
pacman -Qlp omafiles-0.9.0rc1-1-x86_64.pkg.tar.zst
```

### Step 3: Publish to AUR Git Repository
```bash
git clone ssh://aur@aur.archlinux.org/omafiles.git
cp PKGBUILD omafiles/
cd omafiles
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO
git commit -m "feat: release v0.9.0-rc1"
git push origin master
```

---

## 5. Ongoing Update Workflow

For subsequent releases (`v0.9.0-rc2`, `v0.9.0`):
1. Update `pkgver` and reset `pkgrel=1`.
2. Update `sha256sums`.
3. Regenerate `.SRCINFO` with `makepkg --printsrcinfo > .SRCINFO`.
4. Validate build with `makepkg -si`.
5. Push commit to AUR Git repo.

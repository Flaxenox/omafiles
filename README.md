# OmaFiles

**A fast, keyboard-first file manager for Arch Linux on Hyprland/Wayland.**

Built on Qt6 / QML with a lightweight C++ core. Tabs, split preview, grid and
list views, network mounts, archives, ratings-grade search, a file-chooser
portal, and a Nautilus-style sidebar — without the bloat or the wait.

---

## Why OmaFiles

File managers should be fast enough that you forget they exist. OmaFiles is:

- **Native** — Qt Quick rendering with a C++ backend; property dialogs use
  real `stat(2)`/`du` data, no shelling out.
- **Keyboard-first** — every action has a key or a palette entry; press `/`
  anywhere to search every command.
- **Built for a tiling desktop** — works beautifully in quarter and half
  splits, scrolls its own chrome instead of running off-screen, and plays
  nice with Hyprland rules.

It's the file manager I wanted: mine, on my terms, tuned to my workflow.

---

## Features

- **Tabs & split preview** — folders in tabs, files previewed side-by-side,
  with text highlighting and media metadata.
- **Grid & list views** — crossfading thumbnailed grid or dense list; Ctrl+scroll
  zooms grid cells.
- **Sidebar** — bookmarks (drag to reorder, drop folders *or* files to add,
  file bookmarks open with their default app), drives, and network locations.
- **Network mounts** — SFTP, FTP, WebDAV, SMB over GVfs with a Nautilus-like
  connect flow.
- **Native properties** — file sizes, types, disk usage from the kernel, not
  from a shell pipeline.
- **Archives** — compress to `.zip`; extract `.zip`/`.7z`/`.rar` via opt-in
  backends.
- **Duplicate finder** — content-based duplicate detection in any folder.
- **Global search** — instant filename search over `tracker3`/`plocate` when
  installed.
- **File-chooser portal** — replaces the GTK picker in every app, and
  *remembers* the last folder you used for quick re-opens.
- **Mouse side buttons** — back/forward history, Nautilus style.

---

## Requirements

| Package | Purpose |
|---|---|
| `qt6-base` | Qt6 Core/Gui/Qml/Quick/DBus/Network |
| `qt6-declarative` | Quick/QuickControls2 + QML tooling |
| `qt6-webengine` | Provides `Qt6::Pdf` |
| `glib2` | GIO (GVfs mounting, network) |
| `zip` `unzip` | Compress/Extract (`.zip`) |
| `python-gobject` | D-Bus integration scripts |
| `cmake` `ninja` | Build time |

**Optional** (graceful without): `tracker3`/`plocate` (global search),
`ffmpegthumbnailer` (video thumbnails), `gvfs`/`gvfs-smb` (network mounts),
`p7zip`/`unrar` (extra archive formats), `xdg-mime` (default-file-manager
registration).

---

## Install

```bash
# Dependencies (Arch)
sudo pacman -S --needed qt6-base qt6-declarative qt6-webengine glib2 zip unzip python-gobject cmake ninja

# Clone, configure, build
git clone https://github.com/Flaxenox/omafiles.git
cd omafiles
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Per-user install (no root) and launch
cmake --install build
omafiles
```

On first launch the app registers itself as the default file manager and the
file-chooser portal. To fire it from Hyprland or Omarchy: bind
`SUPER + SHIFT + F` → `omafiles --new-window`.

Rebuilding after a pull: `cmake --build build && cmake --install build`. QML
changes apply on next launch without a rebuild; C++ changes (`main.cpp`,
`backend/`) need one. An Arch `PKGBUILD` lives in `packaging/arch/`.

---

## Usage

| Action | How |
|---|---|
| Navigate | click / arrows / mouse back-forward buttons |
| New tab | `Ctrl+T` |
| Preview | select a file — preview opens beside it |
| Toggle view | list ↔ grid |
| Compress | select → right-click → Compress |
| Connect to a server | sidebar **Connect** (SFTP/FTP/WebDAV/SMB) |
| Open with | right-click a file → **Open With** |
| Summit the command palette | `/` |

---

## License

MIT — see [LICENSE](LICENSE).
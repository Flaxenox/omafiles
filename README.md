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

## Keybindings

Defaults below — every non-`fixed` binding can be remapped in
`~/.config/omafiles/keybindings.toml` (see `docs/audits/P2_5_CUSTOM_KEYBINDINGS_AUDIT.md`).
`Shift+↑/↓` extends the selection; `Shift+Delete` deletes permanently instead of trashing.

### Navigation & open

| Key | Action |
|---|---|
| `Return` / `l` | Open — enter folder / launch file |
| `Backspace` / `h` | Go up a directory |
| `Alt+←` / `Alt+→` | Back / forward through history |
| `Space` | Toggle preview (Quick Look) |
| `Shift+Return` | Open a terminal here |
| `Ctrl+L` | Edit current path |
| `Esc` | Escapes in order: exit search → close preview → cancel picker → close panel |

### Selection & view

| Key | Action |
|---|---|
| `Arrow keys` / `j` `k` | Move selection (arrows step grid cells) |
| `g` `g` (chord) | Jump to top |
| `Shift+G` | Jump to bottom |
| `Ctrl+A` / `Ctrl+Shift+A` | Select all / select none |
| `Ctrl+I` | Invert selection |
| `Ctrl+G` | Toggle grid / list view |
| `S` / `Shift+S` | Cycle sort field / reverse sort order |
| `Ctrl+H` | Toggle hidden files |
| `F5` | Refresh |

### File actions

| Key | Action |
|---|---|
| `F2` | Rename |
| `Delete` | Move to trash (`Shift+Delete` = permanent) |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copy / cut / paste |
| `Ctrl+N` / `Ctrl+Shift+N` | New file / new folder |
| `Ctrl+Z` — `Ctrl+Y` (or `Ctrl+Shift+Z`) | Undo / redo |

### Panels & tools

| Key | Action |
|---|---|
| `Ctrl+T` / `Ctrl+\` | New panel (tab) |
| `Ctrl+Tab` | Next panel |
| `Ctrl+W` | Close active panel |
| `/` / `Ctrl+F` | Search files |
| `:` / `Ctrl+P` | Command palette |
| `?` | Toggle this help |
| `Alt+N` | Recent notifications |

### Mouse

| Input | Action |
|---|---|
| Side buttons | Back / forward |
| Right-click | Context menu (Open With, Compress, Properties…) |
| Drag onto the sidebar | Add bookmark (folders or files) |

---

## Usage

| Task | How |
|---|---|
| Compress | select → right-click → **Compress** |
| Connect to a server | sidebar **Connect** (SFTP/FTP/WebDAV/SMB) |

---

## License

MIT — see [LICENSE](LICENSE).
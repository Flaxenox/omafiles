# Omafiles

A fast, keyboard-first **Qt6 / QML** file manager for **Arch Linux (Hyprland/Wayland)** — tabs, split
preview, list & grid views, network mounts, archives, a file-chooser portal, and a Nautilus-style
sidebar, all on a lightweight C++ backend.

Maintained by **Flaxenox**.

---

## ✨ Features

- **Tabs & split preview** — open folders in tabs and preview files side-by-side.
- **Dual view modes** — dense *list* view and thumbnailed *grid* view, with a crossfade animation.
- **Sidebar** — bookmarks (reorder by drag, drop folders/files to add), drives/mounts, network locations.
- **Network mounts** — SFTP, FTP, WebDAV, SMB via GVfs, with a Nautilus-like connect flow.
- **Native properties** — real `stat`/`du` sizing and a disk-usage bar, no shelling out.
- **Archives** — compress to `.zip`; extract `.zip`/`.7z`/`.rar` (opt-in backends).
- **Duplicate finder** — find duplicate files by content.
- **Global search** — fast filename search via `tracker3` / `plocate` when installed.
- **File chooser portal** — integrates as `org.freedesktop.impl.portal.FileChooser` on Hyprland.
- **Mouse back/forward buttons** — history navigation, Nautilus-style.

---

## 🔧 What this fork changes

- Fixes a startup **crash** (use-after-free) and always starts on `$HOME` by default.
- **"Open With"** now actually launches apps; `Terminal=true` apps (`nvim`, `vim`, …) run inside a terminal.
- `--new-window` flag for opening a second window (e.g. on another Hyprland workspace).
- Network mounts (SFTP/FTP/WebDAV/SMB) **mount and unmount reliably**, and connect to the mount's home.
- Mouse **back/forward** buttons drive history.
- Sidebar, file list, and **context menus scroll instead of running off-screen** — no cut-off menus at
  quarter/half splits.
- XDG `[Removed Associations]` respected — no duplicate "Open With" entries.
- Background-tab back/forward no longer drops saved tab state; previews no longer ghost a stale file's
  text into a directory listing.
- Bookmarks: drag to **reorder**, drop folders/files to **add**, file bookmarks **open with their
  default app** (plus "Reveal in folder"), and **remove** via right-click.

Full per-file detail lives in the git history (`master`).

---

## 🛠 Dependencies

**Required:**

| Package | Purpose |
|---|---|
| `qt6-base` | Qt6 Core/Gui/Qml/Quick/DBus/Network |
| `qt6-declarative` | Quick/QuickControls2 + QML tooling |
| `qt6-webengine` | Provides `Qt6::Pdf` |
| `glib2` | GIO (GVfs mounting, network) |
| `zip` `unzip` | Compress/Extract (`.zip`, no fallback) |
| `python-gobject` | D-Bus integration scripts |
| `cmake` `ninja` | Build system (build-time) |

**Optional** (each degrades gracefully without it):

| Package | Purpose |
|---|---|
| `tracker3` / `plocate` | faster global filename search |
| `ffmpegthumbnailer` | video thumbnails |
| `gvfs` / `gvfs-smb` | network locations (SFTP/FTP/WebDAV/SMB) |
| `p7zip` / `unrar` | extract `.7z` / `.rar` |
| `xdg-mime` | register as default file manager / resolve "open with default" |

---

## 🚀 Installation

### Option A — Manual build & per-user install (recommended, no root)

```bash
# 1. Install dependencies (Arch)
sudo pacman -S --needed qt6-base qt6-declarative qt6-webengine glib2 zip unzip python-gobject cmake ninja

# 2. Clone, configure, build
git clone https://github.com/Flaxenox/omafiles.git
cd omafiles
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build

# 3. Install (to ~/.local — no root needed) and run
cmake --install build
omafiles
```

On first launch the app registers itself as the default file manager and the FileChooser portal
automatically (via `scripts/install-integrations.sh`).

> Optional: bind it on Hyprland/Omarchy with `SUPER + SHIFT + F` in `~/.config/hypr/bindings.lua`:
> ```lua
> o.bind("SUPER + SHIFT + F", "OmaFiles", "omafiles --new-window")
> ```

### Rebuilding after pulling changes

```bash
cmake --build build
cmake --install build     # re-syncs ~/.local/bin/omafiles + backend .so + QML resources
```

> QML files load live from the source tree at runtime, so `.qml` changes apply on next launch without
> a rebuild. C++ changes (`main.cpp`, `backend/*`) do require the rebuild above.

### Option B — Arch package

```bash
cd packaging/arch
makepkg -si
```

---

## 🧭 Usage

| Action | How |
|---|---|
| Navigate | click / arrow keys / mouse back–forward buttons |
| New tab | `Ctrl+T` |
| Preview | select a file, preview opens beside it |
| Toggle view | list ↔ grid |
| Compress | select items → right-click → Compress |
| Connect to server | sidebar **Connect** (SFTP/FTP/WebDAV/SMB) |
| Open with | right-click a file → **Open With** |

Press `/` for the command palette to browse all shortcuts.

---

## 📝 License

MIT — see `LICENSE`.
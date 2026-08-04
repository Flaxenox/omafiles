# Omafiles

A keyboard-first file manager for [Omarchy](https://omarchy.org), built as a native Quickshell plugin — not a wrapper around Nautilus/Dolphin/Thunar, and not a layer-shell popup either. It's a real, tileable window that opens and behaves like any other app on your desktop, using Omarchy's own design system (`qs.Commons`/`qs.Ui`) end to end: same typography, same borders, same hover/selection chrome, same Nerd Font icons as the rest of the shell.

![Omafiles screenshot](preview.png)

## Why

Omarchy is opinionated by design — one good default per decision instead of a wall of settings. Omafiles follows the same spirit: no view-mode dropdowns, no icon-size sliders, no settings panel. Sorting is a key that cycles (`s`/`S`), not a combo box. Everything has a keyboard path first; the mouse works too, but it's not the point.

## Features

- Tiled, real window (`FloatingWindow`) — not a modal overlay, not layer-shell. Lives alongside your terminal/editor like a normal app.
- Vim-style keyboard navigation (`j`/`k`, `gg`/`G`, `h`/`l`), plus arrow keys.
- Basic screen-reader support — `Accessible.role`/`Accessible.name` on the file list, sidebar entries, nav buttons, text inputs, and dialog buttons. Not exhaustive (context menus, the palette results list, and a few dialog internals still don't have it) but the main flows are covered.
- Command palette (`:` or `Ctrl+P`) for every action, fuzzy-searchable.
- Tabs shown as side-by-side panels — every open tab is visible at once, separated by a hairline divider, not a one-at-a-time switcher. Whichever panel has the mouse over it is the active one: that's where keyboard shortcuts, selection, and the context menu apply.
- Editable bookmarks — folders or individual files, opening a file bookmark jumps to its folder with it selected.
- Mounted-drives sidebar (mount/eject, distinguishes internal disks from removable/USB by icon).
- Network locations (SFTP/SMB/WebDAV/FTP via GVfs) — "Connect..." in the sidebar or command palette, active connections listed and browsable like any local folder. Needs credentials already cached (SSH key, saved keyring entry) — there's no in-app password prompt.
- Sort by name/size/date/type — a key cycles it, no dropdown. Name sort (and the name tiebreaker for the others) is natural-order aware: `file2.txt` before `file10.txt`, not the other way around.
- Copy/cut sync with the system clipboard (`wl-copy`, `text/uri-list`) — paste files copied in Omafiles into another app, or files copied elsewhere into Omafiles (`Ctrl+V` falls back to reading the system clipboard when nothing's copied inside the app). "Copy path" puts the plain-text path(s) on the clipboard instead, for pasting into a terminal/chat.
- Rename, new folder, new file, make link, delete (to trash, with confirm), copy/cut/paste, drag-and-drop, extract, compress, and bulk rename all refuse to silently clobber an existing name. Copy/cut/paste/drag show a real overwrite/skip/cancel dialog; extract/compress/bulk rename show their own equivalent (overwrite / skip the conflicting ones and continue); rename shows an overwrite confirmation; new folder/new file/make link just refuse with a clear error instead of silently doing nothing or failing (no choice to make there — there's nothing to overwrite by design). A "still working" indicator with Cancel covers copy/move, with a real percentage and progress bar for those two (estimated from source size vs. how much has landed at the destination so far — `cp`/`mv` don't report progress themselves).
- Trash shows each item's original location and deletion time (read from `.trashinfo`), not just a plain file listing.
- Undo (`Ctrl+Z`) and redo (`Ctrl+Shift+Z` or `Ctrl+Y`) for rename, new folder, new file, make link, delete, move, bulk rename, and chmod (chmod undo restores each selected item's own previous mode, not its contents' if applied recursively).
- Archive compress/extract (zip/7z/rar/tar family), bulk rename with `{name}`/`{ext}`/`{n}` patterns (recent patterns saved as one-click chips), chmod (multi-selection, with an "Apply to subfolders" toggle for `chmod -R`), a read-only Properties panel (real folder size via `du`, permissions, owner, dates — or combined item count and total size for a multi-selection).
- Browse inside a zip/7z/rar/tar archive without extracting it — opening a file inside extracts just that one file to a temp cache and opens it with your default app. Read-only view (no rename/delete/copy/etc. inside).
- Image and video thumbnails (video via `ffmpegthumbnailer`, cached).
- Preview (`Space`): images, video thumbnails, syntax-highlighted text (Pygments), first-page PDF render (`pdftoppm`), and audio metadata (duration/codec/bitrate/tags via `ffprobe`).
- Recursive search, "open with", context menus everywhere.
- Every icon is a verified Nerd Font glyph (checked against the installed font's cmap) — no emoji.
- Broken symlinks are flagged clearly (distinct icon, red name, "Broken link" instead of a fake size/date) instead of looking like an ordinary 0-byte file from 1970; valid symlinks show their real target's size.
- Registers itself as the system's default file manager on first load — no manual setup (see below).
- Drag and drop: drag files out to other apps, drag files in from other apps to copy them here, or drag between folders/bookmarks/drives inside Omafiles to move them — with the same overwrite/skip conflict handling as copy/paste.
- Rubber-band selection: click and drag over empty space (including the margins around the sidebar and each row) to select multiple items, Ctrl adds to the existing selection instead of replacing it, auto-scrolls when dragged to a list edge with more items than fit on screen.
- Back/forward navigation history (`Alt+←`/`Alt+→`) and preview state, independent per tab.
- The active panel's folder refreshes live (via `inotifywait`, optional — degrades to manual refresh if `inotify-tools` isn't installed) instead of only on `F5`. Mounted drives and network locations are polled every few seconds.
- Recent files in the sidebar, persisted across sessions — opening one jumps to its folder with it selected.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `j` / `k` / `↓` / `↑` | Move down / up |
| `h` / `Backspace` | Go up a directory |
| `Alt+←` / `Alt+→` | Back / forward |
| `l` / `Enter` | Open (enter directory / launch file) |
| `gg` / `Shift+G` | Jump to top / bottom |
| `Space` | Toggle preview |
| `/` | Search here (`Ctrl+Enter` searches recursively) |
| `:` / `Ctrl+P` | Command palette |
| `Ctrl+A` | Select all |
| `F2` | Rename |
| `Delete` | Delete (to trash) |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copy / cut / paste |
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z` / `Ctrl+Y` | Redo |
| `s` / `Shift+S` | Cycle sort field / reverse order |
| `Ctrl+L` | Edit path directly |
| `Ctrl+Shift+N` | New folder |
| `Ctrl+N` | New file |
| `Ctrl+T` / `Ctrl+\` | New tab (new panel) |
| `Ctrl+W` / `Ctrl+Tab` | Close tab / next tab |
| `Ctrl+H` | Toggle hidden files |
| `Shift+Enter` | Open a terminal here |
| `F5` | Refresh |
| `Escape` | Close preview, or close the window |

## Installation

```bash
omarchy plugin add https://github.com/Percius04/omafiles --enable
```

Or clone it manually:

```bash
git clone https://github.com/Percius04/omafiles ~/.config/omarchy/plugins/omafiles
omarchy plugin enable io.github.percius04.omafiles
```

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + F", "Omafiles (file manager)", "omarchy-shell shell toggle io.github.percius04.omafiles '{}'")
```

## Default file manager

Enabling the plugin sets Omafiles as the system's default file manager automatically — nothing to run by hand. On first load it registers both handoff mechanisms Linux apps use for "the" file manager:

- **Opening directories** (`xdg-open`, "Open folder" actions): a `~/.local/share/applications/omafiles.desktop` with `MimeType=inode/directory`, set via `xdg-mime default`.
- **"Show in file manager"** (Firefox downloads, GTK/Qt "reveal in folder"): these go over the `org.freedesktop.FileManager1` D-Bus interface, not `.desktop`/`xdg-mime`, and Nautilus normally owns it. Omafiles ships a user-level service file for the same bus name (`~/.local/share/dbus-1/services/`), which takes priority over Nautilus's system one, backed by `scripts/dbus-filemanager1.py` (needs `python-gobject`/`Gio` — already a dependency of most GTK-based desktops).

This is idempotent and only runs once (tracked in `~/.local/state/omafiles/integrations-version`), so it won't fight you if you later switch the default back by hand. If you ever want to undo it: `xdg-mime default nautilus.desktop inode/directory`, then remove the two files above.

## Requirements

- Omarchy 4 (Quickshell-based shell).
- `ffmpegthumbnailer` for video thumbnails, `ffprobe` (ffmpeg) for audio metadata, `pygmentize` (python-pygments) for syntax-highlighted previews, `pdftoppm` (poppler) for PDF previews, `inotifywait` (inotify-tools) for live folder refresh — all optional, each falls back gracefully without it.
- `gio` with the relevant GVfs backend for network locations (`gvfs` covers SFTP/FTP/WebDAV; SMB needs `gvfs-smb` too).
- `gio`, `udisksctl`, `wl-clipboard`, standard coreutils (all present on a stock Omarchy install).

## Status

Under active development — feedback and issues welcome.

## License

MIT — see [LICENSE](LICENSE).

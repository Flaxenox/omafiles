pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Canonical XDG paths and persistent storage locations for Omafiles.
//
// Phase 29 (josema): Omafiles is decoupled from Omarchy and the repository. The
// paths follow the XDG standard (honoring XDG_CONFIG_HOME / XDG_STATE_HOME /
// XDG_CACHE_HOME with fallback to ~/.config, ~/.local/state, ~/.cache), the
// and `resourceDir` (where the .sh scripts and the QML tree live) is NO longer the
// delivers it via the OMAFILES_RESOURCE_DIR environment variable.
QtObject {
  id: paths

  readonly property string homeDir: Backend.Env.get("HOME")

  // --- XDG base (with fallback to the spec's default values) ---------
  function _xdg(varName, fallbackSubdir) {
    var v = Backend.Env.get(varName)
    return (v && v.charAt(0) === "/") ? v : homeDir + fallbackSubdir
  }
  readonly property string xdgConfigHome: _xdg("XDG_CONFIG_HOME", "/.config")
  readonly property string xdgStateHome: _xdg("XDG_STATE_HOME", "/.local/state")
  readonly property string xdgCacheHome: _xdg("XDG_CACHE_HOME", "/.cache")
  readonly property string xdgDataHome: _xdg("XDG_DATA_HOME", "/.local/share")

  // --- Omafiles' own directories (XDG) --------------------------------
  readonly property string configDir: xdgConfigHome + "/omafiles"
  readonly property string stateDir: xdgStateHome + "/omafiles"
  readonly property string cacheDir: xdgCacheHome + "/omafiles"

  // RESOURCE root (.sh scripts, QML tree): main.cpp sets it via env, depending
  // on whether it runs from the development tree or from the installation in
  // $XDG_DATA_HOME/omafiles. Defensive fallback to the standard installed path
  // in case the env didn't arrive (it shouldn't).
  readonly property string resourceDir: {
    var r = Backend.Env.get("OMAFILES_RESOURCE_DIR")
    return (r && r.charAt(0) === "/") ? r : xdgDataHome + "/omafiles"
  }

  readonly property string trashDir: xdgDataHome + "/Trash/files"
  readonly property string thumbCacheDir: cacheDir + "/thumbnails"

  // User-defined custom actions config path.
  // config (Phase 29: before it lived under ~/.config/omarchy/omafiles). The app
  // doesn't write it -- the user edits it by hand; the migration from the old
    readonly property string actionsFile: configDir + "/actions.toml"

  // User-defined keyboard rebindings (P2.5, 2026-08-17). Same contract as
  // actionsFile: optional, hand-edited, never written by the app.
  readonly property string keybindingsFile: configDir + "/keybindings.toml"

  // Persistent state (JsonStore reads/writes them via Persistence).
  readonly property string bookmarksFile: stateDir + "/bookmarks.json"
  readonly property string recentFile: stateDir + "/recent.json"
  readonly property string sessionFile: stateDir + "/session.json"
  readonly property string bulkRenameHistoryFile: stateDir + "/bulk-rename-history.json"
  // Saved network-connection profiles (V1.1, headline #4) -- the URI only
  // (address/protocol/path, and the username when embedded as user@host),
  // never a password: NetworkResolver already asks for that separately via
  // its own auth flow, so the URI string saved here never contains one.
  readonly property string networkProfilesFile: stateDir + "/network-profiles.json"

  // Factory bookmarks (used when bookmarks.json doesn't exist yet).
  readonly property var defaultBookmarks: [
    { label: "Home", path: homeDir },
    { label: "Documents", path: homeDir + "/Documents" },
    { label: "Downloads", path: homeDir + "/Downloads" },
    { label: "Pictures", path: homeDir + "/Pictures" },
    { label: "Videos", path: homeDir + "/Videos" },
    { label: "Music", path: homeDir + "/Music" },
    { label: "Projects", path: homeDir + "/Projects" },
    { label: "Trash", path: trashDir }
  ]
}

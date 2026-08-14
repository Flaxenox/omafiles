pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// File paths and locations of Omafiles (Phase 14.B, josema): before they
// lived as properties of OmafilesContent (homeDir/pluginDir/trashDir,
// the four state *.json, the thumbnail cache and the default
// bookmarks), read via `property Item root` from half a dozen
// controllers. They are configuration/paths derived from $HOME, not
// composition-root state: here they stay as the single source, without a god object.
//
// Phase 29 (josema): Omafiles is decoupled from Omarchy and the repository. The
// paths follow the XDG standard (honoring XDG_CONFIG_HOME / XDG_STATE_HOME /
// XDG_CACHE_HOME with fallback to ~/.config, ~/.local/state, ~/.cache), the
// user config moves from ~/.config/omarchy/omafiles to ~/.config/omafiles,
// and `resourceDir` (where the .sh scripts and the QML tree live) is NO longer the
// plugin directory: main.cpp resolves it (dev-tree vs installed) and
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

  // User-defined actions (Phase 26): optional TOML in Omafiles' XDG
  // config (Phase 29: before it lived under ~/.config/omarchy/omafiles). The app
  // doesn't write it -- the user edits it by hand; the migration from the old
  // location is done by logic/LegacyMigration.qml on the first startup.
  readonly property string actionsFile: configDir + "/actions.toml"

  // Persistent state (JsonStore reads/writes them via Persistence).
  readonly property string bookmarksFile: stateDir + "/bookmarks.json"
  readonly property string recentFile: stateDir + "/recent.json"
  readonly property string sessionFile: stateDir + "/session.json"
  readonly property string bulkRenameHistoryFile: stateDir + "/bulk-rename-history.json"

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

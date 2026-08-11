pragma Singleton
import QtQuick
import "../services"

// Rutas y ubicaciones de ficheros de Omafiles (Fase 14.B, josema): antes
// vivían como properties de OmafilesContent (homeDir/pluginDir/trashDir,
// los cuatro *.json de estado, la caché de miniaturas y los marcadores por
// defecto), leídas vía `property Item root` desde media docena de
// controladores. Son configuración/rutas derivadas de $HOME, no estado del
// composition root: aquí quedan como única fuente, sin god object.
//
// Fase 29 (josema): Omafiles se desacopla de Omarchy y del repositorio. Las
// rutas siguen el estándar XDG (honrando XDG_CONFIG_HOME / XDG_STATE_HOME /
// XDG_CACHE_HOME con fallback a ~/.config, ~/.local/state, ~/.cache), la
// config de usuario pasa de ~/.config/omarchy/omafiles a ~/.config/omafiles,
// y `resourceDir` (donde viven los scripts .sh y el árbol QML) ya NO es el
// directorio del plugin: lo resuelve main.cpp (dev-tree vs instalado) y lo
// entrega por la variable de entorno OMAFILES_RESOURCE_DIR.
//
// Importa services/ (Env) igual que NavState/TabsState -- patrón ya
// documentado para la capa state/. Env.get resuelve el backend C++
// (services/Env.qml -> Omafiles.Backend.Env), no una env var de QML.
QtObject {
  id: paths

  readonly property string homeDir: Env.get("HOME")

  // --- Base XDG (con fallback a los valores por defecto de la spec) ---------
  function _xdg(varName, fallbackSubdir) {
    var v = Env.get(varName)
    return (v && v.charAt(0) === "/") ? v : homeDir + fallbackSubdir
  }
  readonly property string xdgConfigHome: _xdg("XDG_CONFIG_HOME", "/.config")
  readonly property string xdgStateHome: _xdg("XDG_STATE_HOME", "/.local/state")
  readonly property string xdgCacheHome: _xdg("XDG_CACHE_HOME", "/.cache")
  readonly property string xdgDataHome: _xdg("XDG_DATA_HOME", "/.local/share")

  // --- Directorios propios de Omafiles (XDG) --------------------------------
  readonly property string configDir: xdgConfigHome + "/omafiles"
  readonly property string stateDir: xdgStateHome + "/omafiles"
  readonly property string cacheDir: xdgCacheHome + "/omafiles"

  // Raíz de RECURSOS (scripts .sh, árbol QML): la fija main.cpp por env, según
  // corra desde el árbol de desarrollo o desde la instalación en
  // $XDG_DATA_HOME/omafiles. Fallback defensivo a la ruta instalada estándar
  // por si la env no llegara (no debería).
  readonly property string resourceDir: {
    var r = Env.get("OMAFILES_RESOURCE_DIR")
    return (r && r.charAt(0) === "/") ? r : xdgDataHome + "/omafiles"
  }

  readonly property string trashDir: xdgDataHome + "/Trash/files"
  readonly property string thumbCacheDir: cacheDir + "/thumbnails"

  // Acciones definidas por el usuario (Fase 26): TOML opcional en la config XDG
  // de Omafiles (Fase 29: antes vivía bajo ~/.config/omarchy/omafiles). No lo
  // escribe la app -- lo edita el usuario a mano; la migración de la ubicación
  // antigua la hace logic/LegacyMigration.qml en el primer arranque.
  readonly property string actionsFile: configDir + "/actions.toml"

  // Estado persistente (JsonStore los lee/escribe vía Persistence).
  readonly property string bookmarksFile: stateDir + "/bookmarks.json"
  readonly property string recentFile: stateDir + "/recent.json"
  readonly property string sessionFile: stateDir + "/session.json"
  readonly property string bulkRenameHistoryFile: stateDir + "/bulk-rename-history.json"

  // Marcadores de fábrica (se usan cuando bookmarks.json no existe todavía).
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

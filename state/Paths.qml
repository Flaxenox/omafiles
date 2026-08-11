pragma Singleton
import QtQuick
import "../services"

// Rutas y ubicaciones de ficheros del plugin (Fase 14.B, josema): antes
// vivían como properties de OmafilesContent (homeDir/pluginDir/trashDir,
// los cuatro *.json de estado, la caché de miniaturas y los marcadores por
// defecto), leídas vía `property Item root` desde media docena de
// controladores. Son configuración/rutas derivadas de $HOME, no estado del
// composition root: aquí quedan como única fuente, sin god object.
//
// Importa services/ (Env) igual que NavState/TabsState -- patrón ya
// documentado para la capa state/. Env.get("HOME") resuelve el backend C++
// (services/Env.qml -> Omafiles.Backend.Env), no una env var de QML.
QtObject {
  readonly property string homeDir: Env.get("HOME")
  readonly property string pluginDir: homeDir + "/.config/omarchy/plugins/omafiles"
  readonly property string trashDir: homeDir + "/.local/share/Trash/files"
  readonly property string thumbCacheDir: homeDir + "/.cache/omafiles/thumbnails"

  // Acciones definidas por el usuario (Fase 26): TOML opcional en la config de
  // Omarchy, leído por logic/CustomActions.qml. No lo escribe la app -- lo edita
  // el usuario a mano.
  readonly property string actionsFile: homeDir + "/.config/omarchy/omafiles/actions.toml"

  // Estado persistente del plugin (JsonStore los lee/escribe vía Persistence).
  readonly property string bookmarksFile: homeDir + "/.local/state/omafiles/bookmarks.json"
  readonly property string recentFile: homeDir + "/.local/state/omafiles/recent.json"
  readonly property string sessionFile: homeDir + "/.local/state/omafiles/session.json"
  readonly property string bulkRenameHistoryFile: homeDir + "/.local/state/omafiles/bulk-rename-history.json"

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

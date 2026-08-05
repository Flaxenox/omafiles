pragma Singleton
import QtQuick

// Marcadores, recientes e historial de renombrado en lote -- decimosexto
// singleton de la capa state/, completa logic/BookmarkOps.qml y
// logic/Persistence.qml (que ya tenían la lógica extraída, pero
// manipulaban este estado a través de root). Las rutas de fichero
// (bookmarksFile/recentFile/sessionFile/bulkRenameHistoryFile) se quedan
// en Omafiles.qml -- son config derivada de homeDir, no estado mutable.
QtObject {
  property var bookmarks: []
  // { path, name } -- más reciente primero, tope 20. Persistido aparte
  // (no en bookmarks.json, semántica distinta: esto lo escribe la propia
  // app sola al abrir ficheros, el usuario no lo edita a mano).
  property var recentFiles: []
  property bool recentLoaded: false
  // Patrones usados de verdad en Bulk rename, más reciente primero, tope
  // 8 -- mostrados como accesos rápidos en el propio diálogo en vez de
  // tener que volver a teclearlos cada vez.
  property var bulkRenameHistory: []
  property bool bulkRenameHistoryLoaded: false
  property bool bookmarksLoaded: false
}

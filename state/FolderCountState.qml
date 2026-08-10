pragma Singleton
import QtQuick

// Caché de nº de items por carpeta (Fase 23, josema). path -> nº de entradas
// directas (o -1 si no se pudo abrir). La alimenta el camino async
// FolderCounter.counted; la leen los subtítulos de fila vía FileMeta.metaFor.
//
// Reactividad como VideoThumbState: `counts` se reasigna ENTERO al actualizar
// (Object.assign) para disparar los bindings, y se acota LRU-256 para que esa
// copia sea barata y no crezca sin fin en sesiones largas. `_pending` evita
// pedir dos veces la misma carpeta mientras una petición está en vuelo.
QtObject {
  property var counts: ({})
  property var _pending: ({})

  // ¿Hace falta pedir el conteo de `path`? (no cacheado y sin petición viva).
  function needsRequest(path) {
    return counts[path] === undefined && _pending[path] !== true
  }
  function markPending(path) { _pending[path] = true }

  // Guarda el resultado (reasigna entero -> re-evalúa los subtítulos).
  function set(path, n) {
    var c = Object.assign({}, counts)
    c[path] = n
    var keys = Object.keys(c)
    while (keys.length > 256) { delete c[keys[0]]; keys.shift() }
    counts = c
    delete _pending[path]
  }
}

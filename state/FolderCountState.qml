pragma Singleton
import QtQuick

// Cache of item count per folder (Phase 23, josema). path -> number of direct
// entries (or -1 if it could not be opened). Fed by the async path
// FolderCounter.counted; read by the row subtitles via FileMeta.metaFor.
//
// Reactivity like VideoThumbState: `counts` is reassigned WHOLE on update
// (Object.assign) to trigger the bindings, and bounded LRU-256 so that
// copy is cheap and does not grow without end in long sessions. `_pending` avoids
// requesting the same folder twice while a request is in flight.
QtObject {
  property var counts: ({})
  property var _pending: ({})

  // Does the count of `path` need requesting? (not cached and no live request).
  function needsRequest(path) {
    return counts[path] === undefined && _pending[path] !== true
  }
  function markPending(path) { _pending[path] = true }

  // Stores the result (reassigns whole -> re-evaluates the subtitles).
  function set(path, n) {
    var c = Object.assign({}, counts)
    c[path] = n
    var keys = Object.keys(c)
    while (keys.length > 256) { delete c[keys[0]]; keys.shift() }
    counts = c
    delete _pending[path]
  }
}

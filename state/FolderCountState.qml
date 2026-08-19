pragma Singleton
import QtQuick

// Cache of item count per folder. path -> number of direct
// entries (or -1 if it could not be opened). Fed by the async path
// FolderCounter.counted; read by the row subtitles via FileMeta.metaFor.
//
// Reactivity like VideoThumbState: `counts` is reassigned WHOLE on update
// (Object.assign) to trigger the bindings, and bounded LRU-256 so that
// copy is cheap and does not grow without end in long sessions. `_pending` avoids
// requesting the same folder twice while a request is in flight.
//
// V1.2 general-perf audit (docs/audits/V1_2_GENERAL_PERFORMANCE_REPORT.md):
// set() used to reassign `counts` SYNCHRONOUSLY on every single counted()
// result. QML tracks `counts` as one property, not per-key, so each
// reassignment invalidates EVERY visible row's FileMeta.metaFor() subtitle
// binding, not just the row whose count actually arrived. Entering a folder
// with N visible subfolders fires N async FolderCounter.request() calls,
// each completing on its own thread-pool schedule -- measured empirically
// (temporary selfcheck instrumentation): 41 reassignments x ~23 visible
// rows depending on `counts` = ~940 binding re-evaluations for just 23
// results, entering a 60-subfolder directory. _flushTimer coalesces
// same-window results into ONE reassignment: same eventual counts, same
// "no visible jump" reactivity contract, ~16ms max added latency per
// result (imperceptible, well under a frame at typical refresh rates).
QtObject {
  property var counts: ({})
  property var _pending: ({})
  property var _pendingResults: ({})

  // Does the count of `path` need requesting? (not cached, no live request,
  // and not already resolved but still waiting on the next flush).
  function needsRequest(path) {
    return counts[path] === undefined && _pending[path] !== true && _pendingResults[path] === undefined
  }
  function markPending(path) { _pending[path] = true }

  // Buffers the result; the actual `counts` reassignment happens on
  // _flushTimer below, coalescing a burst of near-simultaneous results.
  function set(path, n) {
    _pendingResults[path] = n
    delete _pending[path]
    if (!_flushTimer.running) _flushTimer.start()
  }

  property Timer _flushTimer: Timer {
    interval: 16
    repeat: false
    onTriggered: {
      var c = Object.assign({}, counts)
      for (var p in _pendingResults) c[p] = _pendingResults[p]
      _pendingResults = ({})
      var keys = Object.keys(c)
      while (keys.length > 256) { delete c[keys[0]]; keys.shift() }
      counts = c
    }
  }
}

import QtQuick
import "../state"
import Omafiles.Backend as Backend
import "../shared/Utils.js" as Utils

// Video thumbnails (ffmpegthumbnailer, up to maxConcurrent at a time) --
// sixteenth component extracted from core. The three panels that
// paint rows (active panel, background panel, PreviewLoader) request a
// thumbnail with requestVideoThumb() and wait for videoThumbReady (still
// a property of root, read from many places) to fill on its own.
Item {
  property Item root: null

  // A small fixed pool instead of unbounded parallelism: each slot spawns
  // its own ffmpegthumbnailer, which decodes video frames (real CPU/IO
  // cost) -- running dozens at once on a folder full of videos would
  // contend with itself for no gain. 3 keeps a big folder's thumbnails
  // arriving noticeably faster than one-at-a-time without saturating the
  // machine the way an unbounded pool would.
  readonly property var _slots: [_slot0, _slot1, _slot2]

  function requestVideoThumb(entry, basePath) {
    basePath = basePath || NavState.currentPath
    var key = Utils.thumbKeyFor(entry, basePath)
    if (VideoThumbState.videoThumbReady[key]) return
    if (VideoThumbState.thumbQueue.some(function (q) { return Utils.thumbKeyFor(q.entry, q.basePath) === key })) return
    VideoThumbState.thumbQueue = VideoThumbState.thumbQueue.concat([{ entry: entry, basePath: basePath }])
    processThumbQueue()
  }

  function processThumbQueue() {
    while (VideoThumbState.thumbQueue.length > 0) {
      var slot = _freeSlot()
      if (!slot) break
      var next = VideoThumbState.thumbQueue.slice()
      var queued = next.shift()
      VideoThumbState.thumbQueue = next
      _dispatch(slot, queued.entry, queued.basePath)
    }
    VideoThumbState.thumbBusy = _slots.some(function (s) { return s.busy })
  }

  function _freeSlot() {
    for (var i = 0; i < _slots.length; i++)
      if (!_slots[i].busy) return _slots[i]
    return null
  }

  function _dispatch(slot, entry, basePath) {
    var src = Utils.joinPath(basePath, entry.name)
    // Cache file name by the backend's canonical hash (SHA-1),
    // the same scheme as the image/PDF thumbnails. The
    // invalidation key is still path|mtime (thumbKeyFor); only the
    // hash changes. .jpg extension because ffmpegthumbnailer generates it.
    var dest = Paths.thumbCacheDir + "/" + Backend.ThumbnailProvider.cacheKey(Utils.thumbKeyFor(entry, basePath)) + ".jpg"
    slot.currentKey = Utils.thumbKeyFor(entry, basePath)
    slot.currentDest = dest
    slot.start(["bash", Paths.resourceDir + "/scripts/runtime/thumbnail-video.sh", src, dest])
  }

  function _onSlotFinished(slot, result) {
    // Real bug: previously it was marked "ready" no matter what, even if
    // ffmpegthumbnailer failed (weird format, corrupt file, out of
    // memory for a moment) -- requestVideoThumb() never retried
    // because videoThumbReady[key] was already true (with a path that
    // actually does not exist), so that video was left without a
    // real thumbnail the rest of the session. Now it is only marked ready
    // if the process finished well, so a next visit to the folder
    // (new key by mtime, or simply request() again) can
    // retry.
    if (result.exitCode === 0) {
      // Reassigning the object (new reference) is what triggers the
      // bindings of the delegates that read videoThumbReady[key]. Phase
      // 10.A: the map is BOUNDED (LRU-256) so (a) it does not grow without
      // limit in long sessions and (b) this copy is O(1) instead of
      // O(n) -- previously it copied a dictionary that grew without end per
      // thumbnail (quadratic cost over the session).
      var ready = Object.assign({}, VideoThumbState.videoThumbReady)
      ready[slot.currentKey] = slot.currentDest
      var keys = Object.keys(ready)
      while (keys.length > 256) { delete ready[keys[0]]; keys.shift() }
      VideoThumbState.videoThumbReady = ready
    }
    processThumbQueue()
  }

  Backend.ProcessRunner {
    id: _slot0
    property string currentKey: ""
    property string currentDest: ""
    onFinished: function (result) { _onSlotFinished(_slot0, result) }
  }
  Backend.ProcessRunner {
    id: _slot1
    property string currentKey: ""
    property string currentDest: ""
    onFinished: function (result) { _onSlotFinished(_slot1, result) }
  }
  Backend.ProcessRunner {
    id: _slot2
    property string currentKey: ""
    property string currentDest: ""
    onFinished: function (result) { _onSlotFinished(_slot2, result) }
  }
}

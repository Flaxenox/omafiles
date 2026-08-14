import QtQuick
import "../state"
import "../services"
import "../Utils.js" as Utils

// Video thumbnails (ffmpegthumbnailer, queued 1 at a time) --
// sixteenth component extracted from core. The three panels that
// paint rows (active panel, background panel, PreviewLoader) request a
// thumbnail with requestVideoThumb() and wait for videoThumbReady (still
// a property of root, read from many places) to fill on its own.
Item {
  property Item root: null

  function requestVideoThumb(entry, basePath) {
    basePath = basePath || NavState.currentPath
    var key = Utils.thumbKeyFor(entry, basePath)
    if (VideoThumbState.videoThumbReady[key]) return
    if (VideoThumbState.thumbQueue.some(function (q) { return Utils.thumbKeyFor(q.entry, q.basePath) === key })) return
    VideoThumbState.thumbQueue = VideoThumbState.thumbQueue.concat([{ entry: entry, basePath: basePath }])
    processThumbQueue()
  }

  function processThumbQueue() {
    if (VideoThumbState.thumbBusy || VideoThumbState.thumbQueue.length === 0) return
    VideoThumbState.thumbBusy = true
    var next = VideoThumbState.thumbQueue.slice()
    var queued = next.shift()
    VideoThumbState.thumbQueue = next
    var entry = queued.entry
    var basePath = queued.basePath
    var src = Utils.joinPath(basePath, entry.name)
    // Cache file name by the backend's canonical hash (SHA-1),
    // the same scheme as the image/PDF thumbnails (Phase B1). The
    // invalidation key is still path|mtime (thumbKeyFor); only the
    // hash changes. .jpg extension because ffmpegthumbnailer generates it.
    var dest = Paths.thumbCacheDir + "/" + ThumbnailProvider.cacheKey(Utils.thumbKeyFor(entry, basePath)) + ".jpg"
    thumbProc.currentKey = Utils.thumbKeyFor(entry, basePath)
    thumbProc.currentDest = dest
    thumbProc.start(["bash", Paths.resourceDir + "/thumbnail-video.sh", src, dest])
  }

  ProcessRunner {
    id: thumbProc
    property string currentKey: ""
    property string currentDest: ""
    onFinished: function (result) {
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
        ready[thumbProc.currentKey] = thumbProc.currentDest
        var keys = Object.keys(ready)
        while (keys.length > 256) { delete ready[keys[0]]; keys.shift() }
        VideoThumbState.videoThumbReady = ready
      }
      VideoThumbState.thumbBusy = false
      processThumbQueue()
    }
  }
}

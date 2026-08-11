pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Thumbnails -- thin adapter over the C++ singleton
// Omafiles.Backend.ThumbnailProvider (QImageReader/QPdfDocument + on-disk
// cache, see backend/ThumbnailProvider.cpp). Phase 8 (josema).
//
// It forwards request() and re-emits ready() so logic/ and the UI do not import
// Omafiles.Backend (rule 8). Like the rest of services/.
QtObject {
  id: thumbs

  // The thumbnail of `path` (max side `size` px) if it is already cached, or
  // "" if not (it is generated async and arrives via ready). "" also for
  // unsupported types.
  function request(path, size) { return Backend.ThumbnailProvider.request(path, size || 256) }

  // Canonical on-disk cache-key hash (SHA-1 hex) -- the ONLY hash scheme
  // of Omafiles (Phase B1). Consumed by the QML paths that previously
  // used Utils.simpleHash: video thumbnails (logic/VideoThumbnails.qml)
  // and archive extraction cache (logic/ArchiveActions.qml).
  function cacheKey(input) { return Backend.ThumbnailProvider.cacheKey(input) }

  // Fires when a previously requested thumbnail becomes ready.
  signal ready(string path, string thumbPath)

  property Connections _backend: Connections {
    target: Backend.ThumbnailProvider
    function onReady(path, thumbPath) { thumbs.ready(path, thumbPath) }
  }
}

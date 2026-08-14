pragma Singleton
import QtQuick

// Queue and cache of video thumbnails (ffmpegthumbnailer, one at a time)
// -- fourteenth singleton of the state/ layer, completes
// logic/VideoThumbnails.qml. thumbCacheDir stays in core --
// it is config (a path derived from homeDir), not mutable state.
QtObject {
  // "path|mtime" -> local .jpg file, see Utils.thumbKeyFor().
  property var videoThumbReady: ({})
  property var thumbQueue: []
  property bool thumbBusy: false
}

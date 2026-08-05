pragma Singleton
import QtQuick

// Cola y caché de miniaturas de vídeo (ffmpegthumbnailer, de una en una)
// -- decimocuarto singleton de la capa state/, completa
// logic/VideoThumbnails.qml. thumbCacheDir se queda en Omafiles.qml --
// es config (una ruta derivada de homeDir), no estado mutable.
QtObject {
  // "ruta|mtime" -> fichero .jpg local, ver Utils.thumbKeyFor().
  property var videoThumbReady: ({})
  property var thumbQueue: []
  property bool thumbBusy: false
}

import QtQuick
import "../state"
import "../services"
import "../Utils.js" as Utils

// Miniaturas de vídeo (ffmpegthumbnailer, en cola de 1 a la vez) --
// decimosexto componente extraído de Omafiles.qml. Los tres paneles que
// pintan filas (panel activo, panel de fondo, PreviewLoader) piden una
// miniatura con requestVideoThumb() y esperan a que videoThumbReady (sigue
// siendo propiedad de root, se lee desde muchos sitios) se rellene solo.
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
    // Nombre de fichero de caché por el hash canónico del backend (SHA-1),
    // el mismo esquema que las miniaturas de imagen/PDF (Fase B1). La clave
    // de invalidación sigue siendo ruta|mtime (thumbKeyFor); solo cambia el
    // hash. Extensión .jpg porque lo genera ffmpegthumbnailer.
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
      // Bug real: antes se marcaba "lista" pase lo que pase, aunque
      // ffmpegthumbnailer fallara (formato raro, fichero corrupto, sin
      // memoria un instante) -- requestVideoThumb() nunca reintentaba
      // porque videoThumbReady[key] ya era verdadero (con una ruta que
      // en realidad no existe), así que ese vídeo se quedaba sin
      // miniatura real el resto de la sesión. Ahora solo se marca lista
      // si el proceso terminó bien, así una próxima visita a la carpeta
      // (nueva key por mtime, o simplemente request() de nuevo) puede
      // reintentar.
      if (result.exitCode === 0) {
        // Reasignar el objeto (nueva referencia) es lo que dispara los
        // bindings de los delegados que leen videoThumbReady[key]. Fase
        // 10.A: el mapa se ACOTA (LRU-256) para que (a) no crezca sin
        // límite en sesiones largas y (b) esta copia sea O(1) en vez de
        // O(n) -- antes copiaba un diccionario que crecía sin fin por cada
        // miniatura (coste cuadrático a lo largo de la sesión).
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

import QtQuick
import Quickshell.Io
import "../Utils.js" as Utils

// Miniaturas de vídeo (ffmpegthumbnailer, en cola de 1 a la vez) --
// decimosexto componente extraído de Omafiles.qml. Los tres paneles que
// pintan filas (panel activo, panel de fondo, PreviewLoader) piden una
// miniatura con requestVideoThumb() y esperan a que videoThumbReady (sigue
// siendo propiedad de root, se lee desde muchos sitios) se rellene solo.
Item {
  property Item root: null

  function requestVideoThumb(entry, basePath) {
    basePath = basePath || root.currentPath
    var key = Utils.thumbKeyFor(entry, basePath)
    if (root.videoThumbReady[key]) return
    if (root.thumbQueue.some(function (q) { return Utils.thumbKeyFor(q.entry, q.basePath) === key })) return
    root.thumbQueue = root.thumbQueue.concat([{ entry: entry, basePath: basePath }])
    processThumbQueue()
  }

  function processThumbQueue() {
    if (root.thumbBusy || root.thumbQueue.length === 0) return
    root.thumbBusy = true
    var next = root.thumbQueue.slice()
    var queued = next.shift()
    root.thumbQueue = next
    var entry = queued.entry
    var basePath = queued.basePath
    var src = root.joinPath(basePath, entry.name)
    var dest = Utils.videoThumbPath(entry, basePath, root.thumbCacheDir)
    thumbProc.currentKey = Utils.thumbKeyFor(entry, basePath)
    thumbProc.currentDest = dest
    thumbProc.command = ["bash", root.pluginDir + "/thumbnail-video.sh", src, dest]
    thumbProc.running = true
  }

  Process {
    id: thumbProc
    property string currentKey: ""
    property string currentDest: ""
    onExited: function (exitCode) {
      // Bug real: antes se marcaba "lista" pase lo que pase, aunque
      // ffmpegthumbnailer fallara (formato raro, fichero corrupto, sin
      // memoria un instante) -- requestVideoThumb() nunca reintentaba
      // porque videoThumbReady[key] ya era verdadero (con una ruta que
      // en realidad no existe), así que ese vídeo se quedaba sin
      // miniatura real el resto de la sesión. Ahora solo se marca lista
      // si el proceso terminó bien, así una próxima visita a la carpeta
      // (nueva key por mtime, o simplemente request() de nuevo) puede
      // reintentar.
      if (exitCode === 0) {
        var ready = Object.assign({}, root.videoThumbReady)
        ready[thumbProc.currentKey] = thumbProc.currentDest
        root.videoThumbReady = ready
      }
      root.thumbBusy = false
      processThumbQueue()
    }
  }
}

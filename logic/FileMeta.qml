import QtQuick
import "../Utils.js" as Utils

// Metadatos de fichero: subtítulo de fila (tamaño + fecha, o info de
// papelera) e info de audio para la vista previa -- vigésimo segundo
// componente extraído de Omafiles.qml.
Item {
  property Item root: null

  function parseAudioInfo(text) {
    var out = []
    var data
    try { data = JSON.parse(text) } catch (e) { return out }
    var fmt = (data && data.format) || {}
    var stream = (data && data.streams && data.streams[0]) || {}
    var dur = parseFloat(fmt.duration || stream.duration || 0)
    if (dur > 0) {
      var mins = Math.floor(dur / 60)
      var secs = Math.round(dur % 60)
      out.push({ label: "Duration", value: mins + ":" + (secs < 10 ? "0" : "") + secs })
    }
    if (stream.codec_name) out.push({ label: "Codec", value: String(stream.codec_name).toUpperCase() })
    if (fmt.bit_rate) out.push({ label: "Bitrate", value: Math.round(fmt.bit_rate / 1000) + " kbps" })
    if (stream.sample_rate) out.push({ label: "Sample rate", value: Math.round(stream.sample_rate / 1000) + " kHz" })
    if (stream.channels) {
      out.push({ label: "Channels", value: stream.channels === 1 ? "Mono" : stream.channels === 2 ? "Stereo" : String(stream.channels) })
    }
    var tags = fmt.tags || {}
    if (tags.artist) out.push({ label: "Artist", value: tags.artist })
    if (tags.title) out.push({ label: "Title", value: tags.title })
    if (tags.album) out.push({ label: "Album", value: tags.album })
    return out
  }

  // Subtítulo de la fila -- tamaño + fecha relativa para ficheros, solo
  // fecha para carpetas (mismo espíritu que el "Connected" de los ejemplos
  // reales de fila compuesta de Omarchy: nombre + una línea de contexto).
  // basePath: la ruta del panel que está pintando esta fila -- por
  // defecto root.currentPath (panel activo), pero un panel de fondo debe
  // pasar la suya propia (bgPanel.modelData.path) o el aviso de "en la
  // papelera" saldría según la carpeta del panel ACTIVO, no la de este
  // panel (mismo tipo de bug ya documentado para thumbKeyFor/etc.).
  // root.trashInfo es compartida entre el panel activo y todos los de
  // fondo (ver bgTrashInfoProc en BackgroundPanel.qml) -- quien la
  // rellene primero (activo o cualquier panel de fondo) sirve para todos,
  // así que esta función siempre lee la misma copia sin importar quién
  // pinta la fila.
  function metaFor(entry, basePath) {
    if (entry.link === "broken") return "Broken link"
    var atPath = basePath !== undefined ? basePath : root.currentPath
    if (atPath === root.trashDir) {
      var parts = []
      if (entry.type !== "dir") parts.push(Utils.formatSize(entry.size))
      var info = root.trashInfo[entry.name]
      if (info) {
        var rel = Utils.relativeTime(info.epoch)
        parts.push(rel ? "Deleted " + rel : "Deleted")
        if (info.origPath) {
          var slash = info.origPath.lastIndexOf("/")
          parts.push("from " + (slash > 0 ? info.origPath.substring(0, slash) : "/"))
        }
      }
      return parts.join(" · ")
    }
    var parts = []
    if (entry.type !== "dir") parts.push(Utils.formatSize(entry.size))
    var rel = Utils.relativeTime(entry.mtime)
    if (rel) parts.push(rel)
    return parts.join(" · ")
  }
}

.pragma library

// Funciones puras sacadas de Omafiles.qml (sin referencias a "root" --
// un módulo .js de Qt6 con ".pragma library" no ve el scope del
// componente que lo importa, a diferencia de Qt.include(), que en este
// motor directamente falla). thumbKeyFor/videoThumbPath ya no admiten
// basePath/cacheDir opcionales con fallback implícito a
// root.currentPath/root.thumbCacheDir -- quien llama tiene que pasarlos
// siempre.

function formatSize(bytes) {
  if (bytes < 1024) return bytes + " B"
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " K"
  if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " M"
  return (bytes / 1024 / 1024 / 1024).toFixed(1) + " G"
}

function relativeTime(epochSeconds) {
  if (!epochSeconds) return ""
  var diff = Math.floor(Date.now() / 1000) - epochSeconds
  if (diff < 60) return "just now"
  if (diff < 3600) return Math.floor(diff / 60) + " min ago"
  if (diff < 86400) return Math.floor(diff / 3600) + " h ago"
  if (diff < 86400 * 30) return Math.floor(diff / 86400) + " d ago"
  if (diff < 86400 * 365) return Math.floor(diff / (86400 * 30)) + " mo ago"
  return Math.floor(diff / (86400 * 365)) + " yr ago"
}

// Compara los números como números, no letra a letra -- sin esto
// "file2.txt" salía después de "file10.txt" (lexicográfico puro: "1" <
// "2"), y lo mismo con fechas/capítulos/versiones numeradas. Algoritmo
// compacto ya conocido (trocea con una regex, compara tramo a tramo).
function naturalCompare(a, b) {
  var ax = [], bx = []
  a.replace(/(\d+)|(\D+)/g, function (_, d, s) { ax.push([d || Infinity, s || ""]) })
  b.replace(/(\d+)|(\D+)/g, function (_, d, s) { bx.push([d || Infinity, s || ""]) })
  while (ax.length && bx.length) {
    var an = ax.shift(), bn = bx.shift()
    var nn = (an[0] - bn[0]) || an[1].localeCompare(bn[1])
    if (nn) return nn
  }
  return ax.length - bx.length
}

// El hash de clave de caché en disco vive en el backend C++
// (ThumbnailProvider.cacheKey, SHA-1) y es el ÚNICO esquema del proyecto
// (Fase B1). Antes había un simpleHash JS aquí que convivía con ese SHA-1
// (dos formatos de nombre de fichero para la misma carpeta de caché); se
// retiró. Las rutas de caché se componen en QML llamando a
// ThumbnailProvider.cacheKey (ver VideoThumbnails.qml y ArchiveActions.qml).

// Une un directorio base y un nombre en una ruta absoluta, tratando "/"
// como caso especial (evita "//name"). Función pura; era un wrapper de
// OmafilesContent (root.joinPath) que 45 sitios llamaban por la fachada del
// composition root pese a no ser suyo (Fase 14.D): ahora vive aquí, junto
// al resto de utilidades puras, y logic/ ya no depende del root por esto.
function joinPath(base, name) {
  return base === "/" ? "/" + name : base + "/" + name
}

// Clave EN MEMORIA del dict VideoThumbState.videoThumbReady (ruta|mtime) --
// no es un hash de fichero, solo un identificador único por (vídeo, mtime)
// para deduplicar peticiones y leer el resultado. El nombre del fichero de
// caché en disco lo da ThumbnailProvider.cacheKey (SHA-1), ver
// VideoThumbnails.qml.
function thumbKeyFor(entry, basePath) {
  return joinPath(basePath, entry.name) + "|" + entry.mtime
}

// Compara dos listas de entradas por CONTENIDO, barato (O(n), sin
// asignaciones). Fase 10.A: sustituye a JSON.stringify(a) !== JSON.stringify(b)
// -- que serializaba ~330 KB por comparación y se hacía 4 veces por refresco
// (medido en 74 ms sobre /usr/bin). Aquí solo se recorren los campos que la
// UI puede mostrar y que decidirían un relayout.
function entriesEqual(a, b) {
  if (a === b) return true
  if (!a || !b || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    var x = a[i], y = b[i]
    if (x.name !== y.name || x.type !== y.type || x.size !== y.size
        || x.mtime !== y.mtime || x.link !== y.link) return false
  }
  return true
}

// parseMounts sigue vivo: list-mounts.sh (enumeración de dispositivos vía
// lsblk/findmnt) es un "system adapter" que NO se migra (ver BACKEND_DESIGN.md).
// El TSV que produce se parsea aquí. Los montajes de RED, en cambio, pasaron a
// backend nativo (NetworkMounts) en la Fase 16, así que parseNetworkMounts se
// retiró (ya no había consumidor).
// Decodifica una etiqueta de dispositivo (Fase 20, josema). findmnt -r (modo
// raw, que list-mounts.sh usa para partir campos por tabulador de forma
// fiable) escapa espacios y UTF-8 como \xNN; algunos proveedores usan %NN.
// Se convierten los \xNN a %NN y se decodifica todo de una vez con
// decodeURIComponent, que es UTF-8-aware (equivalente a QUrl::fromPercentEncoding),
// así "Mafia\x20The\x20Old" -> "Mafia The Old" y "caf\xc3\xa9" -> "café".
function decodeDeviceLabel(s) {
  var raw = String(s || "")
  var pct = raw.replace(/\\x([0-9A-Fa-f]{2})/g, "%$1")
  try {
    return decodeURIComponent(pct)
  } catch (e) {
    // % suelto no válido para decodeURIComponent: decodifica solo los \xNN.
    return raw.replace(/\\x([0-9A-Fa-f]{2})/g, function (_, h) {
      return String.fromCharCode(parseInt(h, 16))
    })
  }
}

function parseMounts(text) {
  var lines = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
  return lines.map(function (l) {
    var parts = l.split("\t")
    // path también decodificado: findmnt -r escapa los espacios del punto de
    // montaje (/run/media/.../Mafia\x20The\x20Old); sin decodificar, navegar a
    // la unidad fallaría (el directorio real lleva espacios, no \x20).
    return { label: decodeDeviceLabel(parts[0]), path: decodeDeviceLabel(parts[1]), device: parts[2] || "", removable: parts[3] === "1", mounted: parts[4] !== "0", fstype: parts[5] || "" }
  })
}

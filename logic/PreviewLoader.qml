import QtQuick
import "../state"
import "../services"

// Carga de la vista previa (Espacio) -- decimoséptimo componente extraído
// de Omafiles.qml. PreviewPanel.qml pinta PreviewContentState.previewText/
// previewHighlighted/previewPdfImage/previewImage/previewAudioInfo; este
// componente es quien los rellena.
//
// Fase 9 (josema): el preview pasa a NATIVO donde tiene sentido.
//   - Texto plano: PreviewProvider.requestText (QFile/QTextStream, hasta
//     256 KB, async con cancelación) -- ya no `head`.
//   - Imagen y PDF: ThumbnailProvider a tamaño de preview (QImageReader/
//     QPdfDocument + caché en disco) -- ya no se carga la imagen completa
//     ni se usa pdftoppm. Reusa la caché de thumbnails (clave por
//     ruta+tamaño), sin tocar ThumbnailProvider.
// Se quedan en shell por paridad visual / fuera de alcance: el resaltado
// de sintaxis (Pygments, highlight-preview.sh), la miniatura de vídeo
// (ffmpegthumbnailer) y los metadatos de audio (ffprobe).
Item {
  property Item root: null
  property Item videoThumbs: null
  property Item fileMeta: null

  // Lado máximo (px) del render de imagen/PDF de la preview -- generoso para
  // que se vea nítido en el panel (≈45% de ancho) de un monitor grande.
  readonly property int previewSize: 1600

  function togglePreview() {
    if (PreviewState.previewOpen) {
      PreviewState.previewOpen = false
      return
    }
    if (SelectionState.selectedIndex < 0 || SelectionState.selectedIndex >= NavState.visibleEntries.length) return
    loadPreview(NavState.visibleEntries[SelectionState.selectedIndex])
  }

  function loadPreview(entry) {
    if (!entry || entry.type === "dir") return
    PreviewContentState.previewRequestId += 1
    var reqId = PreviewContentState.previewRequestId
    PreviewContentState.previewEntry = entry
    PreviewState.previewOpen = true
    PreviewContentState.previewText = ""
    PreviewContentState.previewHighlighted = ""
    PreviewContentState.previewPdfImage = ""
    PreviewContentState.previewImage = ""
    PreviewContentState.previewAudioInfo = []
    var ext = root.extOf(entry.name)
    var path = root.joinPath(NavState.currentPath, entry.name)
    PreviewContentState.previewIsText = root.codeExt.indexOf(ext) >= 0 || ext === "txt" || ext === "conf" || ext === ""
    if (PreviewContentState.previewIsText && !root.isImage(entry)) {
      // Texto plano NATIVO (PreviewProvider): lee hasta 256 KB en un hilo,
      // con cancelación por generación si se cambia de selección. El
      // resultado llega por textReady (ver la Connections de abajo).
      PreviewContentState._previewTextOwner = reqId
      PreviewProvider.requestText(path)
      // Resaltado de sintaxis SOLO para extensiones de código conocidas --
      // se queda en shell (Pygments) para conservar exactamente el mismo
      // resaltado; en paralelo al texto plano (no en cadena): si falla,
      // previewHighlighted se queda vacío y se ve el texto plano.
      if (root.codeExt.indexOf(ext) >= 0) {
        PreviewContentState._previewHighlightOwner = reqId
        highlightPreviewProc.start([root.pluginDir + "/highlight-preview.sh", path, "4000", ext])
      }
    }
    // Imagen y PDF: render escalado + caché vía ThumbnailProvider. request()
    // devuelve la ruta si ya está en caché, o "" y la genera async -> la
    // Connections de ThumbnailProvider.ready la recoge (re-pide a tamaño de
    // preview, cuya clave de caché no coincide con la miniatura de 256px de
    // la lista).
    if (root.isImage(entry)) {
      PreviewContentState._previewImageOwner = reqId
      PreviewContentState.previewImage = ThumbnailProvider.request(path, previewSize)
    }
    if (root.isPdf(entry)) {
      PreviewContentState._previewPdfOwner = reqId
      PreviewContentState.previewPdfImage = ThumbnailProvider.request(path, previewSize)
    }
    if (root.isVideo(entry)) videoThumbs.requestVideoThumb(entry)
    if (root.isAudio(entry)) {
      PreviewContentState._previewAudioOwner = reqId
      audioInfoProc.start(["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", "--", path])
    }
  }

  // Texto plano listo (PreviewProvider). Guard de dueño igual que antes: si
  // se pasó a otro ítem, se descarta (y PreviewProvider ya lo cancela por su
  // cuenta con la generación).
  Connections {
    target: PreviewProvider
    function onTextReady(path, content, encoding, bytes, lines, truncated) {
      if (PreviewContentState._previewTextOwner === PreviewContentState.previewRequestId)
        PreviewContentState.previewText = content
    }
  }

  // Miniatura de imagen/PDF a tamaño de preview lista. La señal ready no
  // lleva el tamaño, así que se re-pide a previewSize: devuelve la ruta solo
  // cuando ESE tamaño está en caché (ignora la de 256px de la lista).
  Connections {
    target: ThumbnailProvider
    function onReady(path, thumbPath) {
      var e = PreviewContentState.previewEntry
      if (!e || path !== root.joinPath(NavState.currentPath, e.name)) return
      if (root.isImage(e) && PreviewContentState._previewImageOwner === PreviewContentState.previewRequestId) {
        var p = ThumbnailProvider.request(path, previewSize)
        if (p) PreviewContentState.previewImage = p
      } else if (root.isPdf(e) && PreviewContentState._previewPdfOwner === PreviewContentState.previewRequestId) {
        var q = ThumbnailProvider.request(path, previewSize)
        if (q) PreviewContentState.previewPdfImage = q
      }
    }
  }

  ProcessRunner {
    id: highlightPreviewProc
    // Vacío/fallido -> previewHighlighted se queda "" y la UI cae al Text
    // plano (previewText) sin más -- ver el "visible:" de cada bloque en el
    // panel de previsualización.
    onFinished: function (result) { if (PreviewContentState._previewHighlightOwner === PreviewContentState.previewRequestId) PreviewContentState.previewHighlighted = result.stdout }
  }

  ProcessRunner {
    id: audioInfoProc
    onFinished: function (result) { if (PreviewContentState._previewAudioOwner === PreviewContentState.previewRequestId) PreviewContentState.previewAudioInfo = fileMeta.parseAudioInfo(result.stdout) }
  }
}

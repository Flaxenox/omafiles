import QtQuick
import qs.Commons
import "../state"
import "../services"
import "../Utils.js" as Utils

// Carga de la vista previa (Espacio) -- decimoséptimo componente extraído
// de Omafiles.qml. Junta loadPreview()/togglePreview() con los cuatro
// Process que alimentan (texto, resaltado de sintaxis, PDF, audio), que
// antes vivían a 1200 líneas de distancia de la función que los lanzaba.
// PreviewPanel.qml (ya extraído antes) solo pinta PreviewContentState.previewText/
// previewHighlighted/previewPdfImage/previewAudioInfo -- este componente
// es quien los rellena.
Item {
  property Item root: null
  property Item videoThumbs: null
  property Item fileMeta: null

  function togglePreview() {
    if (PreviewState.previewOpen) {
      PreviewState.previewOpen = false
      return
    }
    if (SelectionState.selectedIndex < 0 || SelectionState.selectedIndex >= root.visibleEntries.length) return
    loadPreview(root.visibleEntries[SelectionState.selectedIndex])
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
    PreviewContentState.previewAudioInfo = []
    var ext = root.extOf(entry.name)
    var path = root.joinPath(root.currentPath, entry.name)
    PreviewContentState.previewIsText = root.codeExt.indexOf(ext) >= 0 || ext === "txt" || ext === "conf" || ext === ""
    if (PreviewContentState.previewIsText && !root.isImage(entry)) {
      PreviewContentState._previewTextOwner = reqId
      previewProc.start(["head", "-c", "4000", path])
      // Resaltado de sintaxis SOLO para extensiones de código conocidas
      // (codeExt) -- .txt/.conf/sin extensión se quedan en texto plano, no
      // hay lenguaje real que adivinar ahí. Se lanza en paralelo al texto
      // plano de arriba (no en cadena): si highlight-preview.sh falla o
      // Pygments no reconoce el lenguaje, previewHighlighted se queda
      // vacío y el texto plano ya cargado sigue siendo lo que se ve, sin
      // parpadeo ni hueco en blanco de por medio.
      if (root.codeExt.indexOf(ext) >= 0) {
        PreviewContentState._previewHighlightOwner = reqId
        highlightPreviewProc.start([root.pluginDir + "/highlight-preview.sh", path, "4000", ext])
      }
    }
    if (root.isVideo(entry)) videoThumbs.requestVideoThumb(entry)
    if (root.isPdf(entry)) {
      // Cacheado por hash(ruta+mtime), igual que las miniaturas de vídeo --
      // no vuelve a renderizar la primera página si ya existe de una vista
      // previa anterior del mismo fichero sin cambios.
      var outDir = root.homeDir + "/.cache/omafiles/pdf-preview/" + Utils.simpleHash(path + "|" + entry.mtime)
      var outFile = outDir + "/preview.png"
      pdfPreviewProc.outFile = outFile
      PreviewContentState._previewPdfOwner = reqId
      // "page-*.png" en vez de asumir "page-1.png" -- pdftoppm añade ceros
      // de relleno al número de página según hagan falta para el total de
      // páginas del PDF (de 10 páginas en adelante ya sería "page-01.png"),
      // así que se renombra al único fichero que haya salido en vez de
      // adivinar el nombre exacto.
      pdfPreviewProc.start(["bash", "-c",
        "test -e " + Util.shellQuote(outFile) + " && exit 0; mkdir -p -- " + Util.shellQuote(outDir)
        + " && pdftoppm -png -f 1 -l 1 -scale-to 1000 -- " + Util.shellQuote(path) + " " + Util.shellQuote(outDir + "/page")
        + " && mv -f -- " + Util.shellQuote(outDir) + "/page-*.png " + Util.shellQuote(outFile)])
    }
    if (root.isAudio(entry)) {
      PreviewContentState._previewAudioOwner = reqId
      audioInfoProc.start(["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", "--", path])
    }
  }

  ProcessRunner {
    id: previewProc
    // Descarta si el usuario ya pasó a otro ítem mientras "head" estaba
    // en vuelo -- mismo guard que propertiesDuProc, ver previewRequestId.
    onFinished: function (result) { if (PreviewContentState._previewTextOwner === PreviewContentState.previewRequestId) PreviewContentState.previewText = result.stdout }
  }

  ProcessRunner {
    id: highlightPreviewProc
    // Vacío/fallido -> previewHighlighted se queda "" y la UI cae al
    // Text plano (previewText) sin más -- ver el "visible:" de cada
    // bloque en el panel de previsualización.
    onFinished: function (result) { if (PreviewContentState._previewHighlightOwner === PreviewContentState.previewRequestId) PreviewContentState.previewHighlighted = result.stdout }
  }

  ProcessRunner {
    id: pdfPreviewProc
    property string outFile: ""
    onFinished: function (result) {
      if (result.exitCode === 0 && PreviewContentState._previewPdfOwner === PreviewContentState.previewRequestId) PreviewContentState.previewPdfImage = pdfPreviewProc.outFile
    }
  }

  ProcessRunner {
    id: audioInfoProc
    onFinished: function (result) { if (PreviewContentState._previewAudioOwner === PreviewContentState.previewRequestId) PreviewContentState.previewAudioInfo = fileMeta.parseAudioInfo(result.stdout) }
  }
}

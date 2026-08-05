import QtQuick
import Quickshell.Io
import qs.Commons
import "../Utils.js" as Utils

// Carga de la vista previa (Espacio) -- decimoséptimo componente extraído
// de Omafiles.qml. Junta loadPreview()/togglePreview() con los cuatro
// Process que alimentan (texto, resaltado de sintaxis, PDF, audio), que
// antes vivían a 1200 líneas de distancia de la función que los lanzaba.
// PreviewPanel.qml (ya extraído antes) solo pinta root.previewText/
// previewHighlighted/previewPdfImage/previewAudioInfo -- este componente
// es quien los rellena.
Item {
  property Item root: null
  property Item videoThumbs: null
  property Item fileMeta: null

  function togglePreview() {
    if (root.previewOpen) {
      root.previewOpen = false
      return
    }
    if (root.selectedIndex < 0 || root.selectedIndex >= root.visibleEntries.length) return
    loadPreview(root.visibleEntries[root.selectedIndex])
  }

  function loadPreview(entry) {
    if (!entry || entry.type === "dir") return
    root.previewRequestId += 1
    var reqId = root.previewRequestId
    root.previewEntry = entry
    root.previewOpen = true
    root.previewText = ""
    root.previewHighlighted = ""
    root.previewPdfImage = ""
    root.previewAudioInfo = []
    var ext = root.extOf(entry.name)
    var path = root.joinPath(root.currentPath, entry.name)
    root.previewIsText = root.codeExt.indexOf(ext) >= 0 || ext === "txt" || ext === "conf" || ext === ""
    if (root.previewIsText && !root.isImage(entry)) {
      root._previewTextOwner = reqId
      previewProc.command = ["head", "-c", "4000", path]
      previewProc.running = true
      // Resaltado de sintaxis SOLO para extensiones de código conocidas
      // (codeExt) -- .txt/.conf/sin extensión se quedan en texto plano, no
      // hay lenguaje real que adivinar ahí. Se lanza en paralelo al texto
      // plano de arriba (no en cadena): si highlight-preview.sh falla o
      // Pygments no reconoce el lenguaje, previewHighlighted se queda
      // vacío y el texto plano ya cargado sigue siendo lo que se ve, sin
      // parpadeo ni hueco en blanco de por medio.
      if (root.codeExt.indexOf(ext) >= 0) {
        root._previewHighlightOwner = reqId
        highlightPreviewProc.command = [root.pluginDir + "/highlight-preview.sh", path, "4000", ext]
        highlightPreviewProc.running = true
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
      root._previewPdfOwner = reqId
      // "page-*.png" en vez de asumir "page-1.png" -- pdftoppm añade ceros
      // de relleno al número de página según hagan falta para el total de
      // páginas del PDF (de 10 páginas en adelante ya sería "page-01.png"),
      // así que se renombra al único fichero que haya salido en vez de
      // adivinar el nombre exacto.
      pdfPreviewProc.command = ["bash", "-c",
        "test -e " + Util.shellQuote(outFile) + " && exit 0; mkdir -p -- " + Util.shellQuote(outDir)
        + " && pdftoppm -png -f 1 -l 1 -scale-to 1000 -- " + Util.shellQuote(path) + " " + Util.shellQuote(outDir + "/page")
        + " && mv -f -- " + Util.shellQuote(outDir) + "/page-*.png " + Util.shellQuote(outFile)]
      pdfPreviewProc.running = true
    }
    if (root.isAudio(entry)) {
      root._previewAudioOwner = reqId
      audioInfoProc.command = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", "--", path]
      audioInfoProc.running = true
    }
  }

  Process {
    id: previewProc
    stdout: StdioCollector {
      waitForEnd: true
      // Descarta si el usuario ya pasó a otro ítem mientras "head" estaba
      // en vuelo -- mismo guard que propertiesDuProc, ver previewRequestId.
      onStreamFinished: if (root._previewTextOwner === root.previewRequestId) root.previewText = text
    }
  }

  Process {
    id: highlightPreviewProc
    stdout: StdioCollector {
      waitForEnd: true
      // Vacío/fallido -> previewHighlighted se queda "" y la UI cae al
      // Text plano (previewText) sin más -- ver el "visible:" de cada
      // bloque en el panel de previsualización.
      onStreamFinished: if (root._previewHighlightOwner === root.previewRequestId) root.previewHighlighted = text
    }
  }

  Process {
    id: pdfPreviewProc
    property string outFile: ""
    onExited: function (exitCode) {
      if (exitCode === 0 && root._previewPdfOwner === root.previewRequestId) root.previewPdfImage = pdfPreviewProc.outFile
    }
  }

  Process {
    id: audioInfoProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root._previewAudioOwner === root.previewRequestId) root.previewAudioInfo = fileMeta.parseAudioInfo(text)
    }
  }
}

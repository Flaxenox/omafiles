import "../Utils.js" as Utils
import QtQuick
import "../state"
import Omafiles.Backend as Backend

// Preview loading (Space) -- seventeenth component extracted from
// core. PreviewPanel.qml paints PreviewContentState.previewText/
// previewHighlighted/previewPdfImage/previewImage/previewAudioInfo; this
// component is the one that fills them.
//
//   - Plain text & Syntax Highlighting: PreviewProvider.requestText + SyntaxHighlighter
//     (in-process C++, async with cancellation) -- sub-millisecond, no subprocesses.
//   - Image and PDF: ThumbnailProvider at preview size (QImageReader/
//     QPdfDocument + on-disk cache).
// Video thumbnail uses ffmpegthumbnailer and audio metadata uses ffprobe.
Item {
  property Item root: null

  property Item videoThumbs: null
  property Item fileMeta: null

  // Max side (px) of the image/PDF render of the preview -- generous so it
  // looks sharp in the panel (≈45% width) of a large monitor.
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
    var ext = Utils.extOf(entry.name)
    var path = Utils.entryPath(NavState.currentPath, entry)
    PreviewContentState.previewIsText = FileTypeConfig.codeExt.indexOf(ext) >= 0 || ext === "txt" || ext === "conf" || ext === ""
    if (PreviewContentState.previewIsText && !Utils.isImage(entry)) {
      // NATIVE text & syntax highlighting (PreviewProvider): reads and highlights
      // on a worker thread in-process, with cancellation by generation.
      PreviewContentState._previewTextOwner = reqId
      Backend.PreviewProvider.requestText(path)
    }
    // Image and PDF: scaled render + cache via ThumbnailProvider.
    if (Utils.isImage(entry)) {
      PreviewContentState._previewImageOwner = reqId
      PreviewContentState.previewImage = Backend.ThumbnailProvider.request(path, previewSize)
    }
    if (Utils.isPdf(entry)) {
      PreviewContentState._previewPdfOwner = reqId
      PreviewContentState.previewPdfImage = Backend.ThumbnailProvider.request(path, previewSize)
    }
    if (Utils.isVideo(entry)) videoThumbs.requestVideoThumb(entry)
    if (Utils.isAudio(entry)) {
      PreviewContentState._previewAudioOwner = reqId
      audioInfoProc.start(["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", "--", path])
    }
  }

  // Plain text & syntax highlighted ready (PreviewProvider).
  Connections {
    target: Backend.PreviewProvider
    function onTextReady(path, content, highlighted, encoding, bytes, lines, truncated) {
      if (PreviewContentState._previewTextOwner === PreviewContentState.previewRequestId) {
        PreviewContentState.previewText = content
        PreviewContentState.previewHighlighted = highlighted
      }
    }
  }

  // Image/PDF thumbnail at preview size ready.
  Connections {
    target: Backend.ThumbnailProvider
    function onReady(path, thumbPath) {
      var e = PreviewContentState.previewEntry
      if (!e || path !== Utils.entryPath(NavState.currentPath, e)) return
      if (Utils.isImage(e) && PreviewContentState._previewImageOwner === PreviewContentState.previewRequestId) {
        var p = Backend.ThumbnailProvider.request(path, previewSize)
        if (p) PreviewContentState.previewImage = p
      } else if (Utils.isPdf(e) && PreviewContentState._previewPdfOwner === PreviewContentState.previewRequestId) {
        var q = Backend.ThumbnailProvider.request(path, previewSize)
        if (q) PreviewContentState.previewPdfImage = q
      }
    }
  }

  Backend.ProcessRunner {
    id: audioInfoProc
    onFinished: function (result) { if (PreviewContentState._previewAudioOwner === PreviewContentState.previewRequestId) PreviewContentState.previewAudioInfo = fileMeta.parseAudioInfo(result.stdout) }
  }
}

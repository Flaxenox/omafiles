import "../Utils.js" as Utils
import QtQuick
import "../state"
import "../services"

// Preview loading (Space) -- seventeenth component extracted from
// Omafiles.qml. PreviewPanel.qml paints PreviewContentState.previewText/
// previewHighlighted/previewPdfImage/previewImage/previewAudioInfo; this
// component is the one that fills them.
//
// Phase 9 (josema): the preview goes NATIVE where it makes sense.
//   - Plain text: PreviewProvider.requestText (QFile/QTextStream, up to
//     256 KB, async with cancellation) -- no more `head`.
//   - Image and PDF: ThumbnailProvider at preview size (QImageReader/
//     QPdfDocument + on-disk cache) -- the full image is no longer loaded
//     nor is pdftoppm used. It reuses the thumbnail cache (keyed by
//     path+size), without touching ThumbnailProvider.
// Left in the shell for visual parity / out of scope: syntax highlighting
// (Pygments, highlight-preview.sh), the video thumbnail
// (ffmpegthumbnailer) and the audio metadata (ffprobe).
Item {
  property Item root: null
  property Item fileTypeUtils: null

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
    var ext = fileTypeUtils.extOf(entry.name)
    var path = Utils.entryPath(NavState.currentPath, entry)
    PreviewContentState.previewIsText = FileTypeConfig.codeExt.indexOf(ext) >= 0 || ext === "txt" || ext === "conf" || ext === ""
    if (PreviewContentState.previewIsText && !fileTypeUtils.isImage(entry)) {
      // NATIVE plain text (PreviewProvider): reads up to 256 KB on a thread,
      // with cancellation by generation if the selection changes. The
      // result arrives via textReady (see the Connections below).
      PreviewContentState._previewTextOwner = reqId
      PreviewProvider.requestText(path)
      // Syntax highlighting ONLY for known code extensions --
      // left in the shell (Pygments) to keep exactly the same
      // highlighting; parallel to the plain text (not chained): if it fails,
      // previewHighlighted stays empty and the plain text is shown.
      if (FileTypeConfig.codeExt.indexOf(ext) >= 0) {
        PreviewContentState._previewHighlightOwner = reqId
        highlightPreviewProc.start([Paths.resourceDir + "/highlight-preview.sh", path, "4000", ext])
      }
    }
    // Image and PDF: scaled render + cache via ThumbnailProvider. request()
    // returns the path if it is already cached, or "" and generates it async ->
    // the Connections of ThumbnailProvider.ready picks it up (re-requests at
    // preview size, whose cache key does not match the 256px thumbnail of
    // the list).
    if (fileTypeUtils.isImage(entry)) {
      PreviewContentState._previewImageOwner = reqId
      PreviewContentState.previewImage = ThumbnailProvider.request(path, previewSize)
    }
    if (fileTypeUtils.isPdf(entry)) {
      PreviewContentState._previewPdfOwner = reqId
      PreviewContentState.previewPdfImage = ThumbnailProvider.request(path, previewSize)
    }
    if (fileTypeUtils.isVideo(entry)) videoThumbs.requestVideoThumb(entry)
    if (fileTypeUtils.isAudio(entry)) {
      PreviewContentState._previewAudioOwner = reqId
      audioInfoProc.start(["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", "--", path])
    }
  }

  // Plain text ready (PreviewProvider). Owner guard same as before: if it
  // moved to another item, it is discarded (and PreviewProvider already
  // cancels it on its own via the generation).
  Connections {
    target: PreviewProvider
    function onTextReady(path, content, encoding, bytes, lines, truncated) {
      if (PreviewContentState._previewTextOwner === PreviewContentState.previewRequestId)
        PreviewContentState.previewText = content
    }
  }

  // Image/PDF thumbnail at preview size ready. The ready signal does not
  // carry the size, so it is re-requested at previewSize: it returns the path
  // only when THAT size is cached (ignores the 256px one of the list).
  Connections {
    target: ThumbnailProvider
    function onReady(path, thumbPath) {
      var e = PreviewContentState.previewEntry
      if (!e || path !== Utils.entryPath(NavState.currentPath, e)) return
      if (fileTypeUtils.isImage(e) && PreviewContentState._previewImageOwner === PreviewContentState.previewRequestId) {
        var p = ThumbnailProvider.request(path, previewSize)
        if (p) PreviewContentState.previewImage = p
      } else if (fileTypeUtils.isPdf(e) && PreviewContentState._previewPdfOwner === PreviewContentState.previewRequestId) {
        var q = ThumbnailProvider.request(path, previewSize)
        if (q) PreviewContentState.previewPdfImage = q
      }
    }
  }

  ProcessRunner {
    id: highlightPreviewProc
    // Empty/failed -> previewHighlighted stays "" and the UI falls back to the
    // plain Text (previewText) without more ado -- see the "visible:" of each
    // block in the preview panel.
    onFinished: function (result) { if (PreviewContentState._previewHighlightOwner === PreviewContentState.previewRequestId) PreviewContentState.previewHighlighted = result.stdout }
  }

  ProcessRunner {
    id: audioInfoProc
    onFinished: function (result) { if (PreviewContentState._previewAudioOwner === PreviewContentState.previewRequestId) PreviewContentState.previewAudioInfo = fileMeta.parseAudioInfo(result.stdout) }
  }
}

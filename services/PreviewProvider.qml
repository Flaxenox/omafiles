pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Preview -- thin adapter over the C++ singleton
// Omafiles.Backend.PreviewProvider (async text + metadata, see
// backend/PreviewProvider.cpp). Phase 9 (josema).
//
// It forwards info()/requestText() and re-emits textReady() so logic/ and the
// UI do not import Omafiles.Backend (rule 8). The preview's image/PDF is
// still provided by ThumbnailProvider (at preview size), not this adapter.
QtObject {
  id: preview

  function info(path) { return Backend.PreviewProvider.info(path) }
  function requestText(path, maxBytes) {
    Backend.PreviewProvider.requestText(path, maxBytes || 262144)
  }

  signal textReady(string path, string content, string encoding, var bytes, int lines, bool truncated)

  property Connections _backend: Connections {
    target: Backend.PreviewProvider
    function onTextReady(path, content, encoding, bytes, lines, truncated) {
      preview.textReady(path, content, encoding, bytes, lines, truncated)
    }
  }
}

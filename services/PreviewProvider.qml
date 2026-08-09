pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Previsualización -- adaptador fino sobre el singleton C++
// Omafiles.Backend.PreviewProvider (texto async + metadatos, ver
// backend/PreviewProvider.cpp). Fase 9 (josema).
//
// Reenvía info()/requestText() y re-emite textReady() para que logic/ y la
// UI no importen Omafiles.Backend (regla 8). La imagen/PDF de la preview la
// sigue dando ThumbnailProvider (a tamaño de preview), no este adaptador.
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

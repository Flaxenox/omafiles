pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Miniaturas -- adaptador fino sobre el singleton C++
// Omafiles.Backend.ThumbnailProvider (QImageReader/QPdfDocument + caché en
// disco, ver backend/ThumbnailProvider.cpp). Fase 8 (josema).
//
// Reenvía request() y re-emite ready() para que logic/ y la UI no importen
// Omafiles.Backend (regla 8). Igual que el resto de services/.
QtObject {
  id: thumbs

  // La miniatura de `path` (lado máximo `size` px) si ya está en caché, o
  // "" si no (se genera async y llega por ready). "" también para tipos no
  // soportados.
  function request(path, size) { return Backend.ThumbnailProvider.request(path, size || 256) }

  // Hash canónico de clave de caché en disco (SHA-1 hex) -- el ÚNICO esquema
  // de hash de Omafiles (Fase B1). Lo consumen las rutas de QML que antes
  // usaban Utils.simpleHash: miniaturas de vídeo (logic/VideoThumbnails.qml)
  // y caché de extracción de archivos (logic/ArchiveActions.qml).
  function cacheKey(input) { return Backend.ThumbnailProvider.cacheKey(input) }

  // Se dispara cuando una miniatura pedida antes queda lista.
  signal ready(string path, string thumbPath)

  property Connections _backend: Connections {
    target: Backend.ThumbnailProvider
    function onReady(path, thumbPath) { thumbs.ready(path, thumbPath) }
  }
}

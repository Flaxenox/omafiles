pragma Singleton
import QtQuick

// Listas de extensiones por tipo de fichero (Fase 14.B, josema): eran
// properties readonly de OmafilesContent leídas por logic/FileTypeUtils
// (icono/isImage/isVideo/isAudio), PreviewLoader (texto/código),
// ArchiveActions y ConflictActions (tar). Configuración estática pura, no
// estado del composition root -- aquí quedan como única fuente.
//
// O2 (BACKEND_DESIGN.md 6.B) prevé un MimeDb en C++ que decida el tipo por
// contenido/mime en vez de por extensión; hasta entonces esta es la tabla
// canónica y el único sitio donde tocar para añadir un tipo.
QtObject {
  readonly property var imageExt: ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
  readonly property var videoExt: ["mp4", "mkv", "webm", "avi", "mov", "flv", "m4v"]
  readonly property var audioExt: ["mp3", "flac", "wav", "ogg", "m4a", "opus"]
  readonly property var archiveExt: ["zip", "tar", "gz", "xz", "rar", "7z", "bz2", "zst"]
  readonly property var codeExt: ["js", "ts", "py", "lua", "sh", "c", "cpp", "h", "rs", "go", "html", "css", "json", "qml", "md", "yml", "yaml", "toml"]
  readonly property var tarExt: ["tar", "gz", "tgz", "bz2", "tbz", "xz", "txz"]
}

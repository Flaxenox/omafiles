pragma Singleton
import QtQuick

// Extension lists per file type: static configuration for PreviewLoader,
// ArchiveActions, and ConflictActions. Pure static configuration, not
// composition-root state -- here they stay as the single source.
//
// O2 (BACKEND_DESIGN.md 6.B) foresees a MimeDb in C++ that decides the type by
// content/mime instead of by extension; until then this is the canonical
// table and the only place to touch to add a type.
QtObject {
  readonly property var imageExt: ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
  readonly property var videoExt: ["mp4", "mkv", "webm", "avi", "mov", "flv", "m4v"]
  readonly property var audioExt: ["mp3", "flac", "wav", "ogg", "m4a", "opus"]
  readonly property var archiveExt: ["zip", "tar", "gz", "xz", "rar", "7z", "bz2", "zst"]
  readonly property var codeExt: ["js", "ts", "py", "lua", "sh", "c", "cpp", "h", "rs", "go", "html", "css", "json", "qml", "md", "yml", "yaml", "toml"]
  readonly property var tarExt: ["tar", "gz", "tgz", "bz2", "tbz", "xz", "txz"]
}

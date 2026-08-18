pragma Singleton
import QtQuick

// Extension lists per file type: static configuration for
// logic/PreviewLoader.qml and logic/ActionEngine.qml (corrected
// 2026-08-17, P2.1 follow-up -- ArchiveActions.qml/ConflictActions.qml
// were folded into ActionEngine.qml on 2026-08-15). Pure static
// configuration, not composition-root state -- here they stay as the
// single source.
//
// O2 (BACKEND_DESIGN.md) foresees a MimeDb in C++ that decides the type by
// content/mime instead of by extension; until then this is the canonical
// table and the only place to touch to add a type.
QtObject {
  readonly property var imageExt: ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
  readonly property var videoExt: ["mp4", "mkv", "webm", "avi", "mov", "flv", "m4v"]
  readonly property var audioExt: ["mp3", "flac", "wav", "ogg", "m4a", "opus"]
  readonly property var archiveExt: ["zip", "tar", "gz", "xz", "rar", "7z", "bz2", "zst"]
  readonly property var codeExt: ["js", "ts", "py", "lua", "sh", "c", "cpp", "h", "rs", "go", "html", "css", "json", "qml", "md", "yml", "yaml", "toml"]
  // "zst" added (V1.1 P2): was already in archiveExt (icon) above but
  // missing here (browse/extract), so a .tar.zst/.zst showed an archive
  // icon that did nothing when opened. GNU tar (confirmed 1.35 here)
  // auto-detects zstd compression from content on read, same as it
  // already does for gz/bz2/xz above -- no extra flag needed, verified
  // directly against a real .tar.zst (tar tf/xvf both worked unmodified).
  // "tbz2" added (cleanup pass): this list only had "tbz", while
  // scripts/runtime/list-archive.sh's own independent extension list only
  // had "tbz2" -- neither tar+bzip2 extension is more "correct" than the
  // other in the wild, so a .tbz2 passed isArchive() here but silently
  // failed to list, and a .tbz would have hit the opposite mismatch had
  // the script's list been the one used to gate isArchive(). Both extensions
  // are now in both lists.
  readonly property var tarExt: ["tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst"]
}

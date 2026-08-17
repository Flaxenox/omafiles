pragma Singleton
import QtQuick

// "Inside an archive" mode (.zip/.7z/.rar/.tar browsed without extracting)
// -- twentieth singleton of the state/ layer, completes the archive
// browsing block of logic/ActionEngine.qml (corrected 2026-08-17, P2.1
// follow-up -- used to name logic/ArchiveActions.qml, folded into
// ActionEngine.qml on 2026-08-15). Read as a guard ("if (inArchive)
// return") by almost all file operations -- it makes no sense to
// rename/delete/copy/etc. inside an archive without extracting first.
QtObject {
  property bool inArchive: false
  property string archivePath: ""
  property string archiveSubPath: ""
}

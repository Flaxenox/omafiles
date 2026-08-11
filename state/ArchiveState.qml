pragma Singleton
import QtQuick

// "Inside an archive" mode (.zip/.7z/.rar/.tar browsed without extracting)
// -- twentieth singleton of the state/ layer, completes
// logic/ArchiveActions.qml. Read as a guard ("if (inArchive) return")
// by almost all file operations -- it makes no sense to
// rename/delete/copy/etc. inside an archive without extracting first.
QtObject {
  property bool inArchive: false
  property string archivePath: ""
  property string archiveSubPath: ""
}

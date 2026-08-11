pragma Singleton
import QtQuick

// Inline edit mode of the active panel -- rename a row, new
// folder, new file, edit the path by hand -- eighteenth singleton
// of the state/ layer. Mutually exclusive (each startX() in
// logic/RenameOps.qml/SearchOps.qml turns off the others), already used by
// hasPendingEdit to block tab/panel changes while there is
// something half-written.
QtObject {
  property int renamingIndex: -1
  property bool creatingFolder: false
  property bool creatingFile: false
  property bool editingPath: false
}

pragma Singleton
import QtQuick

// Inline edit mode of the active panel -- rename a row, new
// folder, new file, edit the path by hand -- eighteenth singleton
// of the state/ layer. Mutually exclusive (each startX() in
// logic/ActionEngine.qml/SearchOps.qml turns off the others -- corrected
// 2026-08-17, P2.1 follow-up, this used to name logic/RenameOps.qml,
// folded into ActionEngine.qml on 2026-08-15), already used by
// hasPendingEdit to block tab/panel changes while there is
// something half-written.
QtObject {
  property int renamingIndex: -1
  property bool creatingFolder: false
  property bool creatingFile: false
  property bool editingPath: false
}

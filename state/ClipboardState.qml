pragma Singleton
import QtQuick

// State of the internal clipboard (copy/cut/paste) -- second
// singleton of the state/ layer, same pattern validated with
// SelectionState.qml (pragma Singleton + its own qmldir). The logic that
// manipulates it stays in logic/ActionEngine.qml (corrected 2026-08-17,
// P2.1 follow-up -- used to name logic/ClipboardOps.qml, folded into
// ActionEngine.qml on 2026-08-15).
QtObject {
  property var clipboardPaths: []
  property string clipboardMode: "" // "copy" | "cut"
}

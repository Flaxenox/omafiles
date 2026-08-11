pragma Singleton
import QtQuick

// State of the internal clipboard (copy/cut/paste) -- second
// singleton of the state/ layer, same pattern validated with
// SelectionState.qml (pragma Singleton + its own qmldir). The logic that
// manipulates it stays in logic/ClipboardOps.qml.
QtObject {
  property var clipboardPaths: []
  property string clipboardMode: "" // "copy" | "cut"
}

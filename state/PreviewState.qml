pragma Singleton
import QtQuick

// State of "viewing" a file: quick preview (Space) and the "Open with"
// selector -- seventh singleton of the state/ layer. They go together because
// both are ways of interacting with the selected item and share
// call sites (see logic/PreviewLoader.qml and logic/OpenWithOps.qml).
QtObject {
  property bool previewOpen: false
  property bool openWithOpen: false
  property var openWithApps: []
  property var openWithEntry: null
}

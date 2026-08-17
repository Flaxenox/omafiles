pragma Singleton
import QtQuick

// State of "viewing" a file: quick preview (Space) and the "Open with"
// selector -- seventh singleton of the state/ layer. They go together because
// both are ways of interacting with the selected item and share
// call sites (see logic/PreviewLoader.qml and core/CommandFacade.qml's
// showOpenWith()/launchWith(), corrected 2026-08-17, P2.1 follow-up --
// that logic used to live in logic/OpenWithOps.qml, folded away on
// 2026-08-15).
QtObject {
  property bool previewOpen: false
  property bool openWithOpen: false
  property var openWithApps: []
  property var openWithEntry: null
}

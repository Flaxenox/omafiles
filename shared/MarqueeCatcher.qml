import QtQuick

// Selection marquee catcher (press+drag draws a selection
// rectangle, like Nautilus/any icon manager) -- the same block
// of 4 handlers was repeated 4 times before this extraction (the
// top empty area of the ListView, footer/bottom empty area, and the two gutters
// left/right of each row in FileListRow.qml). Found
// auditing core against rule 4 of the architecture prompt
// ("avoid code duplication even if it means creating a new
// component").
//
// Property names WITHOUT the `host` prefix on purpose, but chosen
// so as not to coincide with any id/property of the files that
// instantiate it (`listView`/`selectionOps` in panels/ActiveFileList.qml,
// `hostListView`/`hostSelectionOps` in panels/FileListRow.qml) -- if
// they coincided with either of the two, QML would auto-bind the property
// to itself instead of to the passed value (see
// [[project_omafiles_architecture_rules]], same bug as
// BackgroundPanel.qml/KeyboardShortcuts.qml).
//
// No `import "../state"` on purpose (architectural audit 2026-08-17, P2.1
// follow-up): this used to call SelectionState.startMarquee/moveMarquee/
// endMarquee directly, one of the two documented shared/-contract
// violations in docs/architecture/ARCHITECTURE.md. `marqueeTarget` takes
// its place -- any object exposing the same three methods (SelectionState
// today; both call sites just pass `marqueeTarget: SelectionState`), so
// this component knows a generic marquee-target shape, not the specific
// singleton. Same idiom `catcherListView` already used for the ListView
// reference, just extended to the selection side too.
MouseArea {
  property Item catcherListView: null
  property real measuredRowHeight: 32
  // Must expose startMarquee(x, y, viewportY, additive), moveMarquee(x, y,
  // viewportY, rowHeight), endMarquee() -- SelectionState's own shape.
  property var marqueeTarget: null

  acceptedButtons: Qt.LeftButton
  onPressed: function (mouse) {
    var p = mapToItem(catcherListView.contentItem, mouse.x, mouse.y)
    var vp = mapToItem(catcherListView, mouse.x, mouse.y)
    marqueeTarget.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
  }
  onPositionChanged: function (mouse) {
    var p = mapToItem(catcherListView.contentItem, mouse.x, mouse.y)
    var vp = mapToItem(catcherListView, mouse.x, mouse.y)
    marqueeTarget.moveMarquee(p.x, p.y, vp.y, measuredRowHeight)
  }
  onReleased: marqueeTarget.endMarquee()
  onCanceled: marqueeTarget.endMarquee()
}

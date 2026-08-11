pragma Singleton
import QtQuick

// Row selection state (single + drag marquee) --
// first singleton of the state/ layer, a pilot to validate the
// pragma Singleton pattern within the plugin itself (same mechanism that
// Util/Color/Style of qs.Commons already use) before moving more state here. The
// logic that manipulates it stays in logic/SelectionOps.qml -- this is ONLY
// the state, without functions.
QtObject {
  property int selectedIndex: -1
  property var selectedIndices: []
  property int anchorIndex: -1

  // ---------- Selection marquee (drag over empty space) ----------
  // Coordinates in the ListView's content space (independent
  // of the scroll), not the viewport -- so the rectangle stays correct if
  // the user drags into the scrolled area.
  property bool marqueeActive: false
  property real marqueeStartX: 0
  property real marqueeStartY: 0
  property real marqueeCurrentX: 0
  property real marqueeCurrentY: 0
  property bool marqueeAdditive: false
  property var marqueeBaseSelection: []
  // Cursor position relative to `list`'s viewport (0 = very top,
  // list.height = very bottom) -- for the auto-scroll when the
  // marquee reaches an edge with more rows than fit on screen.
  property real marqueeViewportY: 0
}

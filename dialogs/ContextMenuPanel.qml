import QtQuick
import qs.Commons
import qs.Ui

// Context menu (right-click). Eighth component extracted from
// core. The actions already arrive as a list of objects
// { label, action, enabled, destructive } built by
// root.itemActions()/emptyAreaActions()/etc. -- each `action` is already a
// function ready to call, so this component does not need
// per-action signals, only to execute it and request closing.
Item {
  id: root

  property bool open: false
  property real menuX: 0
  property real menuY: 0
  property var actions: []

  signal closeRequested()

  // Measures the labels WITHOUT instantiating any visible Text -- avoids the
  // problem of depending on real children to compute the width
  // (circular: the width of each row would depend on the menu width, which
  // in turn should depend on the width of each row). Same font that
  // each row's real Text uses (see below).
  FontMetrics {
    id: menuFontMetrics
    font.pixelSize: Style.font.title
    font.family: Style.font.family
    font.weight: Font.Medium
  }

  readonly property real maxLabelWidth: {
    var m = 0
    for (var i = 0; i < root.actions.length; i++) {
      m = Math.max(m, menuFontMetrics.advanceWidth(root.actions[i].label))
    }
    return m
  }

  MouseArea {
    anchors.fill: parent
    visible: root.open
    z: 15
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: root.closeRequested()
  }

  BorderSurface {
    id: contextMenu
    visible: root.open
    x: root.menuX
    y: root.menuY
    // Minimum width 200 (like before) so a menu with few short
    // actions ("Open"/"Delete"...) does not look scrawny, but
    // it grows with the real content -- previously it was a fixed 200, and a
    // long label ("Open (extracts a temp copy)", the "Open" of a
    // file inside an archive) overflowed the box.
    width: Math.max(200, root.maxLabelWidth + Style.spacing.sm * 2 + contentLeftInset + contentRightInset)
    height: contextMenuColumn.implicitHeight + contentTopInset + contentBottomInset
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    // popupPadding (14): the token dedicated to popups, like the rest of the
    // system surfaces, instead of the sm (4) that stuck the items to the
    // edge and made the menu look tighter than the others.
    padding: Style.spacing.popupPadding
    z: 20

    Column {
      id: contextMenuColumn
      anchors.fill: parent
      anchors.topMargin: contextMenu.contentTopInset
      anchors.rightMargin: contextMenu.contentRightInset
      anchors.bottomMargin: contextMenu.contentBottomInset
      anchors.leftMargin: contextMenu.contentLeftInset
      spacing: Style.spacing.sm

      Repeater {
        model: root.actions

        CursorSurface {
          required property var modelData
          readonly property bool actionEnabled: modelData.enabled !== false
          width: contextMenuColumn.width
          implicitHeight: Style.spacing.controlHeight
          foreground: Color.menu.text
          accent: Color.accent
          hasCursor: itemMouse.containsMouse && actionEnabled

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            text: parent.modelData.label
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            font.weight: Font.Medium
            color: parent.modelData.destructive ? Color.urgent : (parent.actionEnabled ? Color.menu.text : Qt.darker(Color.menu.text, 1.8))
          }

          MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.actionEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.closeRequested()
              parent.modelData.action()
            }
          }
        }
      }
    }
  }
}

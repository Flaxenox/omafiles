import QtQuick
import qs.Commons
import qs.Ui
import "../state"

// "New folder"/"new file" rows of the active panel (Phase 19: the
// search moved out of here to the expandable magnifier of the top bar,
// panels/SearchBar.qml). The two are mutually exclusive
// (EditModeState.creatingFolder/creatingFile -- startNewFolder()/
// startNewFile() turns the other off before turning on its own), so as a
// Column with the two Row visible-conditional, the total height of this
// component (accessible from outside via its id) is that of the single row visible
// at each moment, or 0 if none is -- Column already discards invisible
// children from the calculation. listContainer in MainLayout subtracts that height once
// instead of summing conditional terms separately.
Column {
  property Item root: null
  // The main ListView (id "list" in MainLayout) -- each field returns
  // focus to it when hidden (Escape/Enter), and without passing it explicitly
  // it isn't visible from this file.
  property Item list: null
  property Item conflictActions: null
  width: parent.width
  spacing: Style.spacing.rowGap

  Row {
    id: newFolderRow
    visible: EditModeState.creatingFolder
    width: parent.width
    height: Style.spacing.controlHeight
    spacing: Style.spacing.controlGap

    TextField {
      id: newFolderField
      width: parent.width - 160
      anchors.verticalCenter: parent.verticalCenter
      placeholderText: "New folder name…"
      Accessible.role: Accessible.EditableText
      Accessible.name: "New folder name"
      onVisibleChanged: if (visible) { text = ""; forceActiveFocus() } else list.forceActiveFocus()
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          conflictActions.commitNewFolder(text)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          EditModeState.creatingFolder = false
          event.accepted = true
        }
      }
    }

    Button {
      text: "Create"
      bordered: true
      anchors.verticalCenter: parent.verticalCenter
      Accessible.role: Accessible.Button
      Accessible.name: "Create folder"
      onClicked: conflictActions.commitNewFolder(newFolderField.text)
    }
  }

  Row {
    id: newFileRow
    visible: EditModeState.creatingFile
    width: parent.width
    height: Style.spacing.controlHeight
    spacing: Style.spacing.controlGap

    TextField {
      id: newFileField
      width: parent.width - 160
      anchors.verticalCenter: parent.verticalCenter
      placeholderText: "New file name…"
      Accessible.role: Accessible.EditableText
      Accessible.name: "New file name"
      onVisibleChanged: if (visible) { text = ""; forceActiveFocus() } else list.forceActiveFocus()
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          conflictActions.commitNewFile(text)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          EditModeState.creatingFile = false
          event.accepted = true
        }
      }
    }

    Button {
      text: "Create"
      bordered: true
      anchors.verticalCenter: parent.verticalCenter
      Accessible.role: Accessible.Button
      Accessible.name: "Create file"
      onClicked: conflictActions.commitNewFile(newFileField.text)
    }
  }
}

pragma Singleton
import QtQuick

// Visual "dragging over..." feedback during a
// drag&drop -- seventeenth singleton of the state/ layer. dropHoverIndex
// is for rows of the main list (FileListRow.qml, indexed by
// position); dropHoverPath is for bookmarks/drives in the
// sidebar (Sidebar.qml, indexed by path) -- two forms of the same
// concept, with the key that fits each UI.
QtObject {
  property int dropHoverIndex: -1
  property string dropHoverPath: ""
}

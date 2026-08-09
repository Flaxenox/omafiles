import QtQuick
import qs.Commons
import qs.Ui
import "../state"

// Filas de "nueva carpeta"/"nuevo fichero"/"búsqueda" del panel activo,
// vigésimo componente extraído de Omafiles.qml. Las tres son mutuamente
// excluyentes (EditModeState.creatingFolder/creatingFile/searching -- cada
// startNewFolder()/startNewFile()/startSearch() en Omafiles.qml apaga las
// otras dos antes de encender la suya), así que como Column con las tres
// Row visible-condicional, la altura total de este componente (accesible
// desde fuera por su id) es la de la única fila visible en cada momento,
// o 0 si ninguna lo está -- Column ya descarta hijos invisibles del
// cálculo. listContainer en Omafiles.qml resta esa altura una sola vez en
// vez de sumar tres términos condicionales por separado (antes leía
// newFolderRow.height/newFileRow.height/searchRow.height directo por id,
// algo que ya no es posible al vivir en otro fichero).
Column {
  property Item root: null
  // La ListView principal (id "list" en Omafiles.qml) -- cada campo le
  // devuelve el foco al ocultarse (Escape/Enter), y sin pasarlo explícito
  // no es visible desde este fichero.
  property Item list: null
  property Item conflictActions: null
  property Item searchOps: null
  property Item selectionOps: null
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

  Row {
    id: searchRow
    visible: NavState.searching
    width: parent.width
    height: Style.spacing.controlHeight
    spacing: Style.spacing.controlGap

    // Mismo sangrado que pathArea en navRow (dos botones cuadrados + sus
    // huecos), para que el campo de búsqueda quede alineado bajo la ruta
    // en vez de arrancar en el borde izquierdo.
    Item {
      width: 2 * Style.spacing.controlHeight + Style.spacing.controlGap
      height: 1
    }

    Text {
      text: "/"
      anchors.verticalCenter: parent.verticalCenter
      font.pixelSize: Style.font.title
      font.family: Style.font.family
      color: Color.menu.text
      opacity: 0.6
    }

    TextField {
      id: searchField
      width: parent.width - 30
      anchors.verticalCenter: parent.verticalCenter
      verticalPadding: 2
      placeholderText: "Search here… (Ctrl+Enter searches subfolders)"
      Accessible.role: Accessible.EditableText
      Accessible.name: "Search"
      text: NavState.searchQuery
      onTextChanged: NavState.searchQuery = text
      onVisibleChanged: if (visible) forceActiveFocus(); else list.forceActiveFocus()
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          searchOps.exitSearch()
          event.accepted = true
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
          searchOps.runDeepSearch()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          NavState.searching = false
          selectionOps.selectOnly(NavState.visibleEntries.length > 0 ? 0 : -1)
          event.accepted = true
        }
      }
    }
  }
}

import QtQuick
import qs.Commons
import qs.Ui
import "../state"

// Filas de "nueva carpeta"/"nuevo fichero" del panel activo (Fase 19: la
// búsqueda salió de aquí a la lupa expandible de la barra superior,
// panels/SearchBar.qml). Las dos son mutuamente excluyentes
// (EditModeState.creatingFolder/creatingFile -- startNewFolder()/
// startNewFile() apaga la otra antes de encender la suya), así que como
// Column con las dos Row visible-condicional, la altura total de este
// componente (accesible desde fuera por su id) es la de la única fila visible
// en cada momento, o 0 si ninguna lo está -- Column ya descarta hijos
// invisibles del cálculo. listContainer en MainLayout resta esa altura una
// sola vez en vez de sumar términos condicionales por separado.
Column {
  property Item root: null
  // La ListView principal (id "list" en MainLayout) -- cada campo le
  // devuelve el foco al ocultarse (Escape/Enter), y sin pasarlo explícito
  // no es visible desde este fichero.
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

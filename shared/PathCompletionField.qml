import QtQuick
import qs.Commons
import qs.Ui
import "../state"
import "../services"

// Barra de dirección con autocompletado NATIVO (Ctrl+L, Fase 26). Sustituye al
// TextField suelto que había en MainLayout: mismo comportamiento base (Enter
// navega, Escape cancela) más un desplegable de sugerencias en vivo, Tab para
// completar el tramo y flechas para recorrer las opciones. Toda la resolución
// de rutas es C++ (services/PathCompleter -> QDir), sin procesos externos:
// resuelve ~, rutas absolutas y relativas a la carpeta actual.
Item {
  id: field
  property Item root: null // para root.navigateTo
  property Item list: null // para devolver el foco al ocultarse

  property var suggestions: []
  property int highlight: -1
  // El desplegable solo se ve con el campo enfocado y con algo que sugerir. Al
  // abrir NO se autocompleta (el campo trae la ruta actual seleccionada): las
  // sugerencias aparecen en cuanto el usuario teclea.
  readonly property bool dropdownVisible: input.activeFocus && suggestions.length > 0

  // El foco/selección se dispara desde AQUÍ (no desde input.onVisibleChanged):
  // `visible` es una property de este Item raíz (la pone MainLayout con
  // editingPath); el `visible` local del TextField interior nunca cambia, así
  // que su onVisibleChanged no llegaría a dispararse al abrir.
  onVisibleChanged: {
    if (visible) {
      input.text = NavState.currentPath
      input.forceActiveFocus()
      input.selectAll()
    } else {
      suggestions = []
      if (list)
        list.forceActiveFocus()
    }
  }

  function refresh() {
    suggestions = PathCompleter.complete(input.text, NavState.currentPath)
    highlight = suggestions.length > 0 ? 0 : -1
  }

  function fillWith(path) {
    input.text = path
    input.cursorPosition = path.length
  }

  // Tab: acepta la sugerencia resaltada y recompleta -> muestra el contenido de
  // la carpeta recién elegida, listo para bajar otro tramo.
  function acceptHighlighted() {
    if (highlight < 0 || highlight >= suggestions.length)
      return
    fillWith(suggestions[highlight])
    refresh()
  }

  function navigate(target) {
    root.navigateTo(PathCompleter.expandTilde(target))
    EditModeState.editingPath = false
  }

  TextField {
    id: input
    anchors.fill: parent
    verticalPadding: 2
    Accessible.role: Accessible.EditableText
    Accessible.name: "Path"
    // Solo al teclear el usuario (no cuando fillWith/onVisibleChanged asignan
    // text por código: onTextEdited no dispara con asignaciones programáticas).
    onTextEdited: field.refresh()
    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        field.navigate(field.dropdownVisible && field.highlight >= 0
          ? field.suggestions[field.highlight] : input.text)
        event.accepted = true
      } else if (event.key === Qt.Key_Escape) {
        EditModeState.editingPath = false
        event.accepted = true
      } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        field.acceptHighlighted()
        event.accepted = true
      } else if (event.key === Qt.Key_Down) {
        if (field.suggestions.length > 0) {
          field.highlight = Math.min(field.suggestions.length - 1, field.highlight + 1)
          suggestList.positionViewAtIndex(field.highlight, ListView.Contain)
        }
        event.accepted = true
      } else if (event.key === Qt.Key_Up) {
        if (field.suggestions.length > 0) {
          field.highlight = Math.max(0, field.highlight - 1)
          suggestList.positionViewAtIndex(field.highlight, ListView.Contain)
        }
        event.accepted = true
      }
    }
  }

  // Desplegable flotante bajo el campo. z alto: se dibuja SOBRE la lista de
  // ficheros; ningún ancestro del panel activo recorta (verificado).
  BorderSurface {
    id: dropdown
    visible: field.dropdownVisible
    z: 50
    anchors.top: input.bottom
    anchors.topMargin: 2
    anchors.left: input.left
    width: input.width
    height: Math.min(suggestList.contentHeight + 2 * Style.spacing.xs, 240)
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)

    ListView {
      id: suggestList
      anchors.fill: parent
      anchors.margins: Style.spacing.xs
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: field.suggestions

      delegate: CursorSurface {
        required property var modelData
        required property int index
        width: suggestList.width
        implicitHeight: Style.spacing.controlHeight
        foreground: Color.menu.text
        accent: Color.accent
        hasCursor: index === field.highlight

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.sm
          elide: Text.ElideMiddle
          text: parent.modelData
          font.pixelSize: Style.font.body
          font.family: Style.font.family
          color: parent.index === field.highlight ? Color.menu.selectedText : Color.menu.text
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: field.highlight = parent.index
          onClicked: field.navigate(parent.modelData)
        }
      }
    }
  }
}

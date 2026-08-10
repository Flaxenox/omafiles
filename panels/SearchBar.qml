import QtQuick
import qs.Commons
import qs.Ui
import "../state"

// Lupa de búsqueda expandible de la barra superior (Fase 19, josema). En
// reposo solo se ve la lupa, pegada al borde derecho de navRow; al activarla
// (clic o Ctrl+F) el campo se despliega HACIA LA IZQUIERDA con una animación
// suave, comiéndole ancho al breadcrumb (que MainLayout encoge, nunca a 0:
// la ruta sigue visible, truncada). No es un sistema de búsqueda nuevo:
// reutiliza SearchOps/SearchWorker (búsqueda recursiva incremental desde la
// carpeta actual, resultados en NavState.entries = el mismo panel activo).
//
// Vive en panels/ (no shared/) porque lee NavState y llama a searchOps: capa
// panels/ = puede leer state/ y accionar logic/ inyectado, igual que
// ActivePanelInputRows. Un único componente para los dos frontends (Quickshell
// y Qt6): no hay nada específico de host aquí.
Item {
  id: sb

  // Inyectadas por MainLayout (patrón ActiveFileList, no root.*).
  property Item list: null
  property var searchOps: null
  property var navController: null
  property var selectionOps: null

  // Ancho máximo que MainLayout deja para el campo expandido (lo que sobra
  // tras reservar un mínimo para el breadcrumb) -- así en ventanas estrechas
  // la lupa se expande menos y la ruta nunca desaparece.
  property real maxWidth: 300

  readonly property int collapsedW: Style.spacing.controlHeight
  readonly property int expandedW: Math.max(collapsedW, Math.min(300, maxWidth))

  height: Style.spacing.controlHeight
  width: NavState.searching ? expandedW : collapsedW
  // Expansión/colapso suave (200-250 ms) hacia la izquierda: la lupa queda
  // fija a la derecha porque MainLayout ancla este componente al final de
  // navRow y encoge el breadcrumb en su lugar.
  Behavior on width { enabled: !NavState.suppressSearchAnim; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

  function expand() {
    if (NavState.searching) { field.forceActiveFocus(); return }
    searchOps.startSearch() // searching=true, query="" -> el campo se hace visible y toma foco
  }
  function collapse() {
    searchOps.exitSearch() // searching=false, cancela, limpia, refresca, deselecciona
  }

  // Fondo del campo -- solo visible al expandir (en reposo: solo la lupa).
  // Mismo radio que el resto de controles de la app (TextField/Button usan
  // Style.cornerRadius = decoration:rounding de Hyprland), no una píldora
  // redonda: así sigue las esquinas originales del tema.
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: NavState.searching ? Color.menu.selectedBackground : "transparent"
    border.width: NavState.searching ? Style.spacing.hairline : 0
    border.color: Color.menu.border
    Behavior on color { ColorAnimation { duration: 200 } }
  }

  TextField {
    id: field
    // Lupa a la IZQUIERDA (mockup de josema): el campo va a su derecha,
    // hasta el borde. En reposo (width = collapsedW) el campo queda de ancho
    // ~0 e invisible, y solo se ve la lupa pegada al borde derecho de navRow.
    anchors.left: iconSlot.right
    anchors.leftMargin: Style.spacing.xs
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    verticalPadding: 2
    visible: NavState.searching
    opacity: NavState.searching ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }
    placeholderText: "Search files…"
    Accessible.role: Accessible.EditableText
    Accessible.name: "Search files"
    text: NavState.searchQuery
    onTextChanged: {
      if (text !== NavState.searchQuery) NavState.searchQuery = text
      debounce.restart()
    }
    onVisibleChanged: if (visible) forceActiveFocus(); else if (sb.list) sb.list.forceActiveFocus()
    // Clic fuera con el campo vacío -> colapsar (si hay texto, se mantiene
    // abierto mostrando los resultados aunque el foco se vaya a una fila).
    onActiveFocusChanged: {
      // La ListView reclama el foco activo cada vez que su modelo se resetea
      // (el filtro en vivo cambia con cada letra), lo que dejaba escribir solo
      // una letra. Mientras la lupa está abierta con texto, el teclado es del
      // campo (SearchBar gestiona Up/Down/Enter/Escape), así que se lo
      // devolvemos en el siguiente ciclo (callLater evita pelear en el mismo).
      if (!activeFocus && NavState.searching && NavState.searchQuery.length > 0) Qt.callLater(forceActiveFocus)
      else if (!activeFocus && NavState.searching && NavState.searchQuery.length === 0) sb.collapse()
    }
    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Escape) {
        if (NavState.searchQuery.length > 0) { field.text = ""; NavState.searchQuery = ""; sb.searchOps.restoreListing() }
        else sb.collapse()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (SelectionState.selectedIndex >= 0)
          sb.navController.enter(NavState.visibleEntries[SelectionState.selectedIndex])
        sb.searchOps.exitSearch()
        event.accepted = true
      } else if (event.key === Qt.Key_Down) {
        var d = Math.min(NavState.visibleEntries.length - 1, SelectionState.selectedIndex + 1)
        if (d >= 0) { sb.selectionOps.selectOnly(d); if (sb.list) sb.list.positionViewAtIndex(d, ListView.Contain) }
        event.accepted = true
      } else if (event.key === Qt.Key_Up) {
        var u = Math.max(0, SelectionState.selectedIndex - 1)
        if (NavState.visibleEntries.length > 0) { sb.selectionOps.selectOnly(u); if (sb.list) sb.list.positionViewAtIndex(u, ListView.Contain) }
        event.accepted = true
      }
    }
  }

  Item {
    id: iconSlot
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight

    OpticalGlyph {
      anchors.centerIn: parent
      visible: !NavState.searchBusy
      text: "\u{F0349}" // nf-md-magnify
      fontFamily: Style.font.family
      fontSize: Style.font.icon
      color: NavState.searching ? Color.menu.selectedText : Color.menu.text
      opacity: NavState.searching ? 1 : Style.emphasis.strong
    }

    // Spinner mínimo: un punto en órbita (sin depender de glyph ni de
    // gradientes cónicos). Solo mientras una búsqueda está en vuelo.
    Item {
      id: spinner
      anchors.centerIn: parent
      width: Style.font.icon
      height: Style.font.icon
      visible: NavState.searchBusy
      Rectangle {
        width: 4; height: 4; radius: 2
        color: Color.accent
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
      }
      RotationAnimator on rotation {
        running: spinner.visible
        loops: Animation.Infinite
        from: 0; to: 360; duration: 800
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: NavState.searching ? sb.collapse() : sb.expand()
    }
  }

  Timer {
    id: debounce
    interval: 150
    onTriggered: {
      // Incremental recursiva a partir de 2 caracteres; con 0-1 se restaura
      // el listado normal de la carpeta actual (ver SearchOps).
      if (NavState.searchQuery.length >= 2) sb.searchOps.runDeepSearch()
      else sb.searchOps.restoreListing()
    }
  }
}

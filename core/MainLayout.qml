import QtQuick
import qs.Commons
import qs.Ui
import "../panels"
import "../shared"
import "../state"

// MainLayout -- árbol visual principal de Omafiles (Fase 11.B, josema:
// descomponer el god object core/OmafilesContent.qml). La tarjeta
// (BorderSurface), la barra lateral, la fila de paneles (fondo + activo con
// su navegación/migas/entradas/lista) y el MouseArea del lazo de selección
// que arranca en el hueco barra-lateral↔contenido. Deps inyectadas
// explícitamente (patrón ActiveFileList, no root.*). Expone `list` como
// alias porque los controladores (NavigationController, SearchOps, TabOps,
// ArchiveActions) y DialogLayer lo referencian de vuelta.
Item {
  id: mainLayout

  property Item root
  property var bookmarkOps
  property var mountOps
  property var dragDropOps
  property var videoThumbs
  property var fileMeta
  property var tabOps
  property var sortOps
  property var searchOps
  property var selectionOps
  property var conflictActions
  property var previewLoader
  property var fileOps
  property var renameOps
  property var clipboardOps
  property var deleteOps
  property var gTimer
  property var deleteConfirm
  property var renameConflictConfirm
  property var extractConflictConfirm
  property var compressConflictConfirm
  property var bulkRenameConflictConfirm
  property var newFileConflictConfirm
  property var newFolderConflictConfirm

  property alias list: list
  BorderSurface {
    id: card
    anchors.fill: parent
    color: Color.menu.background
    // Sin borde propio: Hyprland ya dibuja el borde de ventana activa/
    // inactiva alrededor de toda la ventana (como en el resto de apps del
    // sistema) -- un BorderSurface aquí dibujaría un segundo borde, con
    // su propio color, pegado al de Hyprland. Eso sí hace falta en los
    // popups reales de Omarchy (audio, red...) porque son layer-shell y
    // Hyprland nunca los decora; Omafiles ya es una ventana normal.
    borderSpec: Border.none()
    radius: Style.cornerRadius
    padding: Style.spacing.panelPadding

    Row {
      id: cardRow
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      spacing: Style.spacing.panelGap

      // ---------- Barra lateral: accesos anclados ----------
      Sidebar {
        id: sidebar
        width: 160
        height: parent.height
        bookmarks: BookmarksState.bookmarks
        recentFiles: BookmarksState.recentFiles
        mounts: MountsState.mounts
        networkMounts: MountsState.networkMounts
        currentPath: NavState.currentPath
        dropHoverPath: DropHoverState.dropHoverPath
        positionRelativeTo: card
        iconForBookmark: bookmarkOps.iconForBookmark
        iconFor: root.iconFor
        iconForMount: bookmarkOps.iconForMount
        iconForNetworkMount: bookmarkOps.iconForNetworkMount
        openContextMenu: root.openContextMenu
        bookmarkActionsFor: root.bookmarkActions
        mountActionsFor: root.mountActions
        networkMountActionsFor: bookmarkOps.networkMountActions
        onBookmarkOpened: function (bookmark) { root.openBookmark(bookmark) }
        onRecentOpened: function (item) { root.openRecent(item) }
        onRecentLaunched: function (item) { root.launchRecent(item) }
        onRecentRemoveRequested: function (path) { bookmarkOps.removeRecent(path) }
        onRecentClearRequested: bookmarkOps.clearRecent()
        onMountActivated: function (mount) {
          if (!mount.mounted) mountOps.mountDevice(mount)
          else root.navigateTo(mount.path)
        }
        onNetworkMountOpened: function (mount) { root.navigateTo(mount.path) }
        onConnectRequested: mountOps.startConnectToServer()
        onFilesDropped: function (drop, destPath) { dragDropOps.handleFilesDropped(drop, destPath) }
        onDropHoverChanged: function (path) { DropHoverState.dropHoverPath = path }
      }

      Rectangle {
        width: Style.spacing.hairline
        height: parent.height
        color: Color.menu.border
        // Bajado de 0.3 a 0.15 -- misma alpha que usa PanelSeparator
        // (el separador horizontal real de Omarchy) para el mismo rol
        // conceptual de "línea divisoria discreta". No hay un
        // componente vertical real con el que comparar, pero no hay
        // motivo para que esta línea sea el doble de fuerte que las
        // horizontales del mismo fichero.
        opacity: 0.15
      }

      // ---------- Contenido principal ----------
      Column {
        id: mainColumn
        width: parent.width - sidebar.width - 1 - parent.spacing * 2
        height: parent.height
        spacing: Style.spacing.rowGap

        Item {
          id: panelsRow
          width: parent.width
          height: parent.height
          readonly property int panelCount: TabsState.tabs.length
          // El hueco entre dos paneles lleva panelGap A CADA LADO del
          // divisor (no panelGap repartido entre los dos) -- para que el
          // margen "interior" de un panel (hacia el divisor) sea tan ancho
          // como el "exterior" (hacia la barra lateral o el borde de la
          // ventana), en vez de la mitad.
          readonly property real interPanelGap: 2 * Style.spacing.panelGap + Style.spacing.hairline
          readonly property real slotWidth: (panelsRow.width - (panelCount - 1) * interPanelGap) / panelCount
          function slotX(i) { return i * (panelsRow.slotWidth + panelsRow.interPanelGap) }

          // ---------- Divisores entre paneles ----------
          // Una simple línea, no un recuadro con borde propio -- mismo
          // estilo que ya usa el divisor entre la barra lateral y el
          // contenido (Color.menu.border, opacity 0.15, Style.spacing.hairline).
          Repeater {
            model: Math.max(0, TabsState.tabs.length - 1)
            delegate: Rectangle {
              required property int index
              x: panelsRow.slotX(index) + panelsRow.slotWidth + Style.spacing.panelGap
              y: 0
              width: Style.spacing.hairline
              height: panelsRow.height
              color: Color.menu.border
              opacity: 0.15
            }
          }

          // ---------- Paneles simples (todas las pestañas salvo la activa) ----------
          // Generalización de lo que antes era un único panel de "vista
          // dividida" fijo -- ahora hay uno por cada pestaña que no sea la
          // activa, cada uno con su propio listado (su propio Process,
          // hijo del delegado). Deliberadamente simple: sin lazo de
          // selección ni menú contextual propio, solo navegar con doble
          // clic y arrastrar -- para eso sirve, el panel activo (más
          // abajo) ya tiene todo lo demás.
          Repeater {
            model: TabsState.tabs

            BackgroundPanel {
              hostRoot: root
              hostPanelsRow: panelsRow
              hostVideoThumbs: videoThumbs
              hostDragDropOps: dragDropOps
              hostFileMeta: fileMeta
              hostTabOps: tabOps
              hostSortOps: sortOps
            }
          }

          // ---------- Panel activo ----------
          // Todo lo que ya existía (barra de navegación, campos de
          // nueva carpeta/fichero/búsqueda, la lista completa con lazo de
          // selección/menú contextual/drag&drop/etc.) sin tocar su lógica
          // interna -- solo movido a su propio hueco dentro de la fila de
          // paneles, en la posición de la pestaña activa.
          Item {
            id: activePanel
            x: panelsRow.slotX(TabsState.activeTabIndex)
            y: 0
            width: panelsRow.slotWidth
            height: panelsRow.height

        // Sin tinte de fondo propio en el panel activo -- se probó un
        // Rectangle de Util.alpha(Color.accent, 0.08) de pared a pared,
        // pero josema lo vio feo al pasar el ratón (mancha de color
        // sobre todo el panel). El atenuado opacity:0.8 de bgPanel ya
        // basta por sí solo para distinguir cuál está activo, sin
        // añadir color encima.

        // navRow/listContainer/etc. van en su propia Column interior en
        // vez de directamente en activePanel -- así statusText, fuera de
        // ella, puede anclarse a parent.bottom (igual que bgStatusText)
        // y quedar en el mismo píxel exacto en los dos tipos de panel.
        // Antes, al ser el último hijo de la Column, su posición salía de
        // sumar navRow+listContainer+márgenes -- una cadena de números
        // reales que no siempre cuadraba pixel a pixel con el bottom:
        // parent.bottom de los paneles de fondo (una simple resta).
        Column {
          id: activeTop
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.rowGap

        Row {
          id: navRow
          width: parent.width
          height: Style.spacing.controlHeight
          spacing: Style.spacing.controlGap

          PanelNavButtons {
            anchors.verticalCenter: parent.verticalCenter
            canGoBack: TabsState.navHistoryIndex > 0
            canGoForward: TabsState.navHistoryIndex < TabsState.navHistory.length - 1
            canGoUp: NavState.currentPath !== "/"
            onBackRequested: root.navBack()
            onForwardRequested: root.navForward()
            onUpRequested: root.goUp()
          }

          Item {
            id: pathArea
            width: parent.width - 3 * (Style.spacing.controlHeight + Style.spacing.controlGap)
            height: parent.height

            MouseArea {
              // Detrás de las migas de pan: clic en hueco vacío -> editar ruta a mano.
              anchors.fill: parent
              visible: !EditModeState.editingPath
              cursorShape: Qt.IBeamCursor
              onClicked: searchOps.startEditPath()
            }

            BreadcrumbSegments {
              id: breadcrumbRow
              visible: !EditModeState.editingPath
              anchors.fill: parent
              segments: root.pathSegments()
              activePath: NavState.currentPath
            }

            TextField {
              id: pathField
              visible: EditModeState.editingPath
              anchors.fill: parent
              verticalPadding: 2
              Accessible.role: Accessible.EditableText
              Accessible.name: "Path"
              onVisibleChanged: if (visible) { text = NavState.currentPath; forceActiveFocus(); selectAll() } else list.forceActiveFocus()
              Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.navigateTo(text)
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  EditModeState.editingPath = false
                  event.accepted = true
                }
              }
            }
          }
        }

        ActivePanelInputRows {
          id: activeInputRows
          // RHS cualificado con mainLayout.* (Fase 11.B): estas deps son
          // properties de MainLayout, no ids -- sin cualificar, `root: root`
          // se autorreferencia a la property root del propio
          // ActivePanelInputRows (binding loop -> null). `list` sí es un id.
          root: mainLayout.root
          list: list
          conflictActions: mainLayout.conflictActions
          searchOps: mainLayout.searchOps
          selectionOps: mainLayout.selectionOps
        }

        Item {
          id: listContainer
          width: parent.width
          // Sin el "- Style.spacing.hairline" que llevaba antes: ese
          // único píxel de más hacía que list.height quedara 1px por
          // debajo de bgList.height (misma fórmula, pero bgList lo
          // deriva de anchors reales, sin ese fudge). En una lista con
          // filas no se notaba (solo cambia el margen bajo la última
          // fila), pero el estado vacío, centrado en el alto total,
          // amplificaba ese único píxel a un desajuste visible al
          // cambiar entre panel activo/de fondo.
          // Las tres filas de activeInputRows son mutuamente excluyentes
          // (ver comentario del propio componente) -- su altura ya ES
          // la de la única fila visible, o 0 si ninguna lo está, así
          // que basta un término en vez de sumar los tres por separado.
          height: activePanel.height - navRow.height
            - (EditModeState.creatingFolder || EditModeState.creatingFile || root.searching ? activeInputRows.height + mainColumn.spacing : 0)
            - statusText.height - mainColumn.spacing * (2 + (EditModeState.creatingFolder || EditModeState.creatingFile || root.searching ? 1 : 0))

          ActiveFileList {
            id: list
            anchors.fill: parent
            // RHS cualificado con mainLayout.* (Fase 11.B): son properties de
            // MainLayout, no ids -- sin cualificar cada `X: X` se
            // autorreferencia a la property homónima del propio ActiveFileList
            // (binding loop -> null). `card` y `list` sí son ids. Los siete
            // ConfirmDialog los recibe MainLayout de root (antes apuntaban a
            // `dialogLayer`, que no existe en este ámbito).
            root: mainLayout.root
            card: card
            gTimer: mainLayout.gTimer
            previewLoader: mainLayout.previewLoader
            conflictActions: mainLayout.conflictActions
            mountOps: mainLayout.mountOps
            fileOps: mainLayout.fileOps
            videoThumbs: mainLayout.videoThumbs
            renameOps: mainLayout.renameOps
            clipboardOps: mainLayout.clipboardOps
            dragDropOps: mainLayout.dragDropOps
            searchOps: mainLayout.searchOps
            fileMeta: mainLayout.fileMeta
            deleteOps: mainLayout.deleteOps
            tabOps: mainLayout.tabOps
            selectionOps: mainLayout.selectionOps
            sortOps: mainLayout.sortOps
            deleteConfirm: mainLayout.deleteConfirm
            renameConflictConfirm: mainLayout.renameConflictConfirm
            extractConflictConfirm: mainLayout.extractConflictConfirm
            compressConflictConfirm: mainLayout.compressConflictConfirm
            bulkRenameConflictConfirm: mainLayout.bulkRenameConflictConfirm
            newFileConflictConfirm: mainLayout.newFileConflictConfirm
            newFolderConflictConfirm: mainLayout.newFolderConflictConfirm
          }

        }
        } // fin activeTop (Column)
            // ---------- Barra de estado ----------
            // Dentro del panel activo, no como hermana global de
            // panelsRow -- antes quedaba siempre debajo de la columna
            // izquierda aunque la información fuera de la pestaña de la
            // derecha, algo que josema notó como desalineado. Fuera de
            // activeTop y anclada a activePanel.bottom (como
            // bgStatusText) para que quede en el mismo píxel exacto.
            Text {
              id: statusText
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              text: NavState.visibleEntries.length + (NavState.visibleEntries.length === 1 ? " item" : " items")
                + (NavState.searchQuery ? " of " + NavState.entries.length : "")
                + (root.searchTruncated ? " · showing first 200" : "")
                // Sin tope en la carpeta en sí (a diferencia de la
                // búsqueda) -- cortar un listado normal a los N primeros
                // rompería el manejo de ficheros de verdad para carpetas
                // grandes (node_modules, caches de paquetes...). Solo un
                // aviso informativo de que puede ir lento, no un límite.
                + (!NavState.searchQuery && NavState.entries.length > 5000 ? " · large folder, may be slow" : "")
                + (SelectionState.selectedIndices.length > 1 ? " · " + SelectionState.selectedIndices.length + " selected" : "")
                + (ClipboardState.clipboardPaths.length > 0 ? " · clipboard: " + ClipboardState.clipboardPaths.length + (ClipboardState.clipboardPaths.length === 1 ? " item" : " items") + (ClipboardState.clipboardMode === "cut" ? " (cut)" : " (copied)") : "")
                + " · sort: " + sortOps.sortLabel()
              font.pixelSize: Style.font.subtitle
              font.family: Style.font.family
              color: Color.menu.text
              opacity: 0.55
            }
          } // fin activePanel (Item)
        } // fin panelsRow (Item)
      }
    }

    // El lazo de selección también debe poder arrancar en el hueco entre
    // la barra lateral y el contenido -- `cardRow` es un Row con
    // `spacing: Style.spacing.panelGap` a cada lado del separador
    // vertical, y ese espaciado no pertenece a ningún hijo (ni sidebar ni
    // mainColumn lo cubren), así que ningún MouseArea dentro de
    // `listContainer` llega hasta ahí por mucho z-order que se ajuste.
    // `mapToItem` en vez de aritmética manual con list.y/contentY --
    // ya nos hemos equivocado antes a mano con esas cuentas.
    MouseArea {
      x: cardRow.x + sidebar.width
      y: cardRow.y
      width: 2 * Style.spacing.panelGap + 1
      height: cardRow.height
      acceptedButtons: Qt.LeftButton
      onPressed: function (mouse) {
        var p = mapToItem(list.contentItem, mouse.x, mouse.y)
        var vp = mapToItem(list, mouse.x, mouse.y)
        selectionOps.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
      }
      onPositionChanged: function (mouse) {
        var p = mapToItem(list.contentItem, mouse.x, mouse.y)
        var vp = mapToItem(list, mouse.x, mouse.y)
        selectionOps.moveMarquee(p.x, p.y, vp.y)
      }
      onReleased: selectionOps.endMarquee()
      onCanceled: selectionOps.endMarquee()
    }
  }
}

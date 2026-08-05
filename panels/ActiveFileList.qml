import QtQuick
import qs.Commons
import qs.Ui
import "../shared"
import "../logic"
import "../state"
import "../Utils.js" as Utils

// La ListView principal del panel activo (selección con lazo, arrastrar y
// soltar, atajos de teclado, renombrado inline, menú contextual por fila) +
// todo lo que la rodea dentro de listContainer (separador, rueda del ratón,
// gutters del lazo, estado vacío, rectángulo visual del lazo, vista
// previa) -- vigésimo primer componente extraído de Omafiles.qml, y el más
// grande hasta ahora. listContainer se queda en Omafiles.qml con su cálculo
// de altura (afinado a pixel, ver sus propios comentarios) intacto; este
// componente solo pinta su contenido con anchors.fill: parent.
//
// La ListView interna se renombró de "list" a "listView" (con id: list ya
// no habría manera de darle el MISMO id "list" a la instancia de este
// componente sin colisionar) -- pero decenas de sitios en Omafiles.qml
// (funciones de root, otros diálogos con onFocusReturnRequested, el
// MouseArea del hueco lateral entre sidebar y mainColumn) siguen
// escribiendo `list.contentY`/`list.forceActiveFocus()`/etc. por id
// directo, y cambiar todos esos call sites habría sido mucho más
// arriesgado que resolverlo aquí: la instancia de este componente se sigue
// llamando "list" en Omafiles.qml (mismo id de siempre), y estos alias +
// funciones-sombra reexponen justo el subconjunto de API de ListView que
// se usa desde fuera (contentY/originY/contentHeight/contentItem,
// forceActiveFocus()/positionViewAtBeginning()) -- nada más, no es un
// wrapper genérico de ListView.
Item {
  property Item root: null
  property Item card: null
  property Timer gTimer: null
  property Item previewLoader: null
  property Item conflictActions: null
  property Item mountOps: null
  property Item fileOps: null
  property Item videoThumbs: null
  property Item renameOps: null
  property Item clipboardOps: null
  property Item dragDropOps: null
  property Item searchOps: null
  property Item fileMeta: null
  property Item deleteOps: null
  property Item tabOps: null
  property Item sortOps: null
  property Item selectionOps: null
  property Item deleteConfirm: null
  property Item renameConflictConfirm: null
  property Item extractConflictConfirm: null
  property Item compressConflictConfirm: null
  property Item bulkRenameConflictConfirm: null
  property Item newFileConflictConfirm: null
  property Item newFolderConflictConfirm: null

  property alias contentY: listView.contentY
  property alias originY: listView.originY
  property alias contentHeight: listView.contentHeight
  property alias contentItem: listView.contentItem
  function forceActiveFocus() { listView.forceActiveFocus() }
  function positionViewAtBeginning() { listView.positionViewAtBeginning() }
  function positionViewAtIndex(index, mode) { listView.positionViewAtIndex(index, mode) }

  KeyboardShortcuts {
    id: keyboardShortcuts
    hostRoot: root
    hostListView: listView
    hostGTimer: gTimer
    hostPreviewLoader: previewLoader
    hostConflictActions: conflictActions
    hostMountOps: mountOps
    hostFileOps: fileOps
    hostRenameOps: renameOps
    hostClipboardOps: clipboardOps
    hostDragDropOps: dragDropOps
    hostSearchOps: searchOps
    hostDeleteOps: deleteOps
    hostTabOps: tabOps
    hostSortOps: sortOps
    hostSelectionOps: selectionOps
    hostDeleteConfirm: deleteConfirm
    hostRenameConflictConfirm: renameConflictConfirm
    hostExtractConflictConfirm: extractConflictConfirm
    hostCompressConflictConfirm: compressConflictConfirm
    hostBulkRenameConflictConfirm: bulkRenameConflictConfirm
    hostNewFileConflictConfirm: newFileConflictConfirm
    hostNewFolderConflictConfirm: newFolderConflictConfirm
  }

            // Misma línea que separa cabecera y lista en los paneles de
            // fondo (bgHeaderSep) -- va aquí dentro, no como hermana en la
            // Column, para que el hueco entre separador y lista sea el
            // mismo Style.spacing.sm de allí y no el mainColumn.spacing
            // (más ancho) que la Column mete entre CUALQUIER par de hijos.
            PanelSeparator {
              id: listSep
              anchors.top: parent.top
              foreground: Color.menu.text
              strength: 0.15
            }

            MouseArea {
              // Detrás de la lista: clic derecho en hueco vacío -> menú contextual general.
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              acceptedButtons: Qt.RightButton
              onClicked: function (mouse) {
                var pos = mapToItem(card, mouse.x, mouse.y)
                root.openContextMenu(pos.x, pos.y, root.emptyAreaActions())
              }
            }

            // Detrás de la lista: soltar aquí (desde otra app, o un arrastre
            // interno sobre hueco vacío en vez de encima de una fila) mete
            // los ficheros en la carpeta abierta ahora mismo. Al ir ANTES
            // que la ListView en el fichero, queda por debajo en el orden de
            // pintado -- el DropArea de cada fila de carpeta, por encima,
            // gana cuando el cursor está sobre ella.
            DropArea {
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              keys: ["text/uri-list"]
              onEntered: function (drag) { if (!drag.hasUrls) drag.accepted = false }
              onDropped: function (drop) {
                dragDropOps.handleFilesDropped(drop, root.currentPath)
              }
            }

            // Rueda del ratón: con `listView.interactive` a false (para que
            // arrastrar nunca haga scroll, solo dibuje el lazo), Flickable
            // deja de procesar también la rueda -- se reimplementa aquí a
            // mano. Sin onPressed/onClicked, así que un MouseArea sin
            // control de wheel (ninguno de filas/footer/marqueeArea lo
            // implementa) deja pasar el evento hasta este, detrás de todo;
            // por eso uno solo, cubriendo toda la zona, basta para filas y
            // huecos vacíos por igual.
            MouseArea {
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              property real wheelAccumulator: 0
              onWheel: function (wheel) {
                var step = Util.wheelSteps(wheelAccumulator, wheel.angleDelta.y)
                wheelAccumulator = step.remainder
                if (step.steps === 0) return
                // El suelo es listView.originY, NO 0 -- ListView puede desplazar
                // su origen con el reciclado de delegados (visto en vivo:
                // originY llegó a valer cientos de píxeles tras scrollear
                // mucho), y forzar contentY a 0 en ese caso deja justo el
                // hueco vacío arriba del todo que reportaba el usuario.
                var minY = listView.originY
                var maxY = minY + Math.max(0, listView.contentHeight - listView.height)
                listView.contentY = Math.max(minY, Math.min(maxY, listView.contentY - step.steps * 60))
              }
            }

            // Detrás de la ListView, solo el hueco de arriba (fuera de sus
            // bounds, por el topMargin de `listView` -- lo de abajo lo cubre el
            // footer, dentro de la propia ListView, ver más abajo). Pulsar y
            // arrastrar aquí dibuja un lazo de selección (como Nautilus/
            // cualquier gestor de iconos) -- Ctrl mantenido pulsado suma a
            // la selección previa en vez de reemplazarla.
            MarqueeCatcher {
              id: marqueeArea
              anchors.top: parent.top
              height: listView.y
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              catcherListView: listView
              catcherSelectionOps: selectionOps
            }

            ListView {
              id: listView
              anchors.top: listSep.bottom
              // Hueco reservado encima de la primera fila -- sin esto no hay
              // ningún píxel "vacío" por encima donde arrancar el lazo, la
              // fila 0 empezaría justo en el borde. Solo desplaza la
              // ListView, marqueeArea/DropArea de detrás siguen llegando
              // hasta el borde real, así que ese hueco cae en ellos. Subido
              // de sm a md (josema: poco aire entre la cabecera y la
              // lista) -- mismo valor en bgList para que las dos alturas
              // seguán coincidiendo exactas (ver el bug del -1px anterior).
              anchors.topMargin: Style.spacing.md
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: PreviewState.previewOpen ? parent.width * 0.55 : parent.width
              clip: true
              model: root.visibleEntries
              focus: root.opened
              // Sin esto, arrastrar con el click (botón izquierdo pulsado)
              // hace scroll de la lista -- el mismo gesto que queremos
              // libre por completo para el lazo de selección. Solo debe
              // poder hacer scroll la rueda, nunca el arrastre. Como
              // Flickable ata la rueda a esta misma propiedad, hay que
              // reimplementarla a mano (ver wheelArea más abajo).
              interactive: false
              // Sin esto (default DragAndOvershootBounds), cualquier cambio
              // en contentHeight mientras contentY está en el borde (el
              // footer se recalcula constantemente a partir de
              // measuredRowHeight) dispara una animación de rebote propia de
              // Flickable que puede pasar a negativo antes de asentarse. Si
              // el siguiente evento de rueda llega a mitad de esa animación,
              // el contentY que se lee ya no es el real y el rebote se
              // reinicia sobre un punto erróneo -- eso es lo que hacía crecer
              // el hueco de arriba en cada ciclo de scroll. Con esto, el
              // límite es duro e inmediato, sin animación que interrumpir.
              boundsBehavior: Flickable.StopAtBounds

              // Hueco de abajo para el lazo. Un MouseArea suelto detrás de
              // la ListView (como el de arriba) NO sirve aquí: al ser
              // Flickable, ListView se queda con cualquier press+arrastre en
              // TODO su rectángulo -- incluido el hueco bajo la última fila,
              // aunque ahí no haya ningún delegado -- antes de que le llegue
              // a nada por detrás (y si se desactiva `interactive` para
              // evitarlo, se pierde también el scroll con la rueda, que
              // depende de la misma propiedad). La solución real es un
              // footer: al ser contenido propio de la ListView (como las
              // filas), gana el press igual que ellas.
              footer: Item {
                id: listFooter
                width: listView.width
                // Altura FIJA a propósito -- nada que dependa de
                // measuredRowHeight/contentHeight/visibleEntries.length, ni
                // de ninguna otra propiedad que cambie durante el scroll. El
                // footer es contenido propio de la ListView (participa en su
                // recolocación/reciclado de delegados); atarlo a algo que se
                // recalcula mientras se hace scroll es lo que dejaba
                // `listView.originY` desincronizado de 0 -- confirmado con un
                // lector de depuración (originY llegó a valer 210 tras
                // scrollear arriba/abajo varias veces), y eso es exactamente
                // el hueco que aparecía arriba del todo. Con un número fijo
                // el footer nunca se recalcula, así que no hay nada que
                // pueda perturbar el origen.
                height: 400

                MarqueeCatcher {
                  anchors.fill: parent
                  catcherListView: listView
                  catcherSelectionOps: selectionOps
                }
              }

              // Auto-scroll del lazo: si el cursor se queda pegado a un
              // borde de la lista mientras se arrastra y hay más filas de
              // las que caben en el viewport, hace scroll solo para poder
              // seguir seleccionando más allá de lo visible -- como
              // Nautilus/cualquier gestor con lazo. marqueeViewportY llega
              // ya actualizado (vía mapToItem(listView, ...)) desde cualquier
              // catcher del lazo, así que esto no depende de dónde arrancó
              // el arrastre.
              Timer {
                interval: 16
                repeat: true
                running: SelectionState.marqueeActive && listView.contentHeight > listView.height
                  && (SelectionState.marqueeViewportY < 32 || SelectionState.marqueeViewportY > listView.height - 32)
                onTriggered: {
                  var minY = listView.originY
                  var maxY = minY + Math.max(0, listView.contentHeight - listView.height)
                  var step = 18
                  if (SelectionState.marqueeViewportY < 32) {
                    listView.contentY = Math.max(minY, listView.contentY - step)
                    SelectionState.marqueeCurrentY = listView.contentY
                  } else {
                    listView.contentY = Math.min(maxY, listView.contentY + step)
                    SelectionState.marqueeCurrentY = listView.contentY + listView.height
                  }
                  selectionOps.updateMarqueeSelection(SelectionState.marqueeAdditive, SelectionState.marqueeBaseSelection)
                }
              }

              Keys.onPressed: function (event) { keyboardShortcuts.handlePress(event) }

              delegate: FileListRow {
                hostRoot: root
                hostListView: listView
                hostCard: card
                hostDragDropOps: dragDropOps
                hostVideoThumbs: videoThumbs
                hostFileMeta: fileMeta
                hostConflictActions: conflictActions
                hostSelectionOps: selectionOps
              }
            }

            // Aviso cuando list-dir.sh no ha podido listar currentPath --
            // antes esto se veía igual que una carpeta vacía de verdad, sin
            // ningún indicio de que el problema era de permisos.
            Text {
              visible: root.currentPathError !== ""
              anchors.top: parent.top
              anchors.topMargin: Style.spacing.lg
              anchors.left: parent.left
              text: root.currentPathError
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              color: Color.urgent
            }

            EmptyState {
              visible: root.currentPathError === "" && root.visibleEntries.length === 0
              centerOn: listView
              message: root.searchQuery
                ? "No results for “" + root.searchQuery + "”"
                : (root.currentPath === root.trashDir ? "Trash is empty" : "Nothing here yet")
            }

            // Rectángulo visual del lazo -- después de la ListView en el
            // fichero para quedar por encima al pintar (visible incluso
            // cuando el lazo crece sobre filas ya dibujadas).
            Rectangle {
              visible: SelectionState.marqueeActive
              x: Math.min(SelectionState.marqueeStartX, SelectionState.marqueeCurrentX)
              y: Math.min(SelectionState.marqueeStartY, SelectionState.marqueeCurrentY) - listView.contentY + listView.y
              width: Math.abs(SelectionState.marqueeCurrentX - SelectionState.marqueeStartX)
              height: Math.abs(SelectionState.marqueeCurrentY - SelectionState.marqueeStartY)
              color: Util.alpha(Color.accent, 0.12)
              border.color: Color.accent
              border.width: 1
              z: 5
            }

            // ---------- Vista previa (Espacio) ----------
            PreviewPanel {
              anchors.fill: parent
              open: PreviewState.previewOpen
              entryName: PreviewContentState.previewEntry ? PreviewContentState.previewEntry.name : ""
              hasEntry: !!PreviewContentState.previewEntry
              isImageEntry: PreviewContentState.previewEntry ? root.isImage(PreviewContentState.previewEntry) : false
              isVideoEntry: PreviewContentState.previewEntry ? root.isVideo(PreviewContentState.previewEntry) : false
              isTextEntry: !!PreviewContentState.previewEntry && !root.isImage(PreviewContentState.previewEntry) && PreviewContentState.previewIsText
              isPdfEntry: PreviewContentState.previewEntry ? root.isPdf(PreviewContentState.previewEntry) : false
              isAudioEntry: PreviewContentState.previewEntry ? root.isAudio(PreviewContentState.previewEntry) : false
              imageSource: (PreviewContentState.previewEntry && root.isImage(PreviewContentState.previewEntry))
                ? Util.fileUrl(root.joinPath(root.currentPath, PreviewContentState.previewEntry.name)) : ""
              videoThumbSource: {
                if (!PreviewContentState.previewEntry || !root.isVideo(PreviewContentState.previewEntry)) return ""
                var p = VideoThumbState.videoThumbReady[Utils.thumbKeyFor(PreviewContentState.previewEntry, root.currentPath)] || ""
                return p ? Util.fileUrl(p) : ""
              }
              highlightedText: PreviewContentState.previewHighlighted
              plainText: PreviewContentState.previewText
              pdfImageSource: PreviewContentState.previewPdfImage ? Util.fileUrl(PreviewContentState.previewPdfImage) : ""
              audioInfo: PreviewContentState.previewAudioInfo
              fallbackSizeText: PreviewContentState.previewEntry ? Utils.formatSize(PreviewContentState.previewEntry.size) : ""
            }
}

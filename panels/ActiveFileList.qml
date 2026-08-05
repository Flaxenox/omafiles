import QtQuick
import qs.Commons
import qs.Ui
import "../shared"
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
  property Item deleteConfirm: null
  property Item renameConflictConfirm: null
  property Item extractConflictConfirm: null
  property Item compressConflictConfirm: null
  property Item bulkRenameConflictConfirm: null

  property alias contentY: listView.contentY
  property alias originY: listView.originY
  property alias contentHeight: listView.contentHeight
  property alias contentItem: listView.contentItem
  function forceActiveFocus() { listView.forceActiveFocus() }
  function positionViewAtBeginning() { listView.positionViewAtBeginning() }

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
              width: root.previewOpen ? parent.width * 0.55 : parent.width
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
              width: root.previewOpen ? parent.width * 0.55 : parent.width
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
              width: root.previewOpen ? parent.width * 0.55 : parent.width
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
            MouseArea {
              id: marqueeArea
              anchors.top: parent.top
              height: listView.y
              anchors.left: parent.left
              width: root.previewOpen ? parent.width * 0.55 : parent.width
              acceptedButtons: Qt.LeftButton
              onPressed: function (mouse) {
                var p = mapToItem(listView.contentItem, mouse.x, mouse.y)
                var vp = mapToItem(listView, mouse.x, mouse.y)
                root.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
              }
              onPositionChanged: function (mouse) {
                var p = mapToItem(listView.contentItem, mouse.x, mouse.y)
                var vp = mapToItem(listView, mouse.x, mouse.y)
                root.moveMarquee(p.x, p.y, vp.y)
              }
              onReleased: root.endMarquee()
              onCanceled: root.endMarquee()
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
              width: root.previewOpen ? parent.width * 0.55 : parent.width
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

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  onPressed: function (mouse) {
                    var p = mapToItem(listView.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(listView, mouse.x, mouse.y)
                    root.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
                  }
                  onPositionChanged: function (mouse) {
                    var p = mapToItem(listView.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(listView, mouse.x, mouse.y)
                    root.moveMarquee(p.x, p.y, vp.y)
                  }
                  onReleased: root.endMarquee()
                  onCanceled: root.endMarquee()
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
                running: root.marqueeActive && listView.contentHeight > listView.height
                  && (root.marqueeViewportY < 32 || root.marqueeViewportY > listView.height - 32)
                onTriggered: {
                  var minY = listView.originY
                  var maxY = minY + Math.max(0, listView.contentHeight - listView.height)
                  var step = 18
                  if (root.marqueeViewportY < 32) {
                    listView.contentY = Math.max(minY, listView.contentY - step)
                    root.marqueeCurrentY = listView.contentY
                  } else {
                    listView.contentY = Math.min(maxY, listView.contentY + step)
                    root.marqueeCurrentY = listView.contentY + listView.height
                  }
                  root.updateMarqueeSelection(root.marqueeAdditive, root.marqueeBaseSelection)
                }
              }

              Keys.onPressed: function (event) {
                if (root.paletteOpen) return
                if (root.openWithOpen) {
                  if (event.key === Qt.Key_Escape) { root.openWithOpen = false; event.accepted = true }
                  return
                }
                if (root.chmodOpen) {
                  if (event.key === Qt.Key_Escape) { root.chmodOpen = false; event.accepted = true }
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { fileOps.commitChmod(root.chmodMode); event.accepted = true }
                  return
                }
                if (root.contextMenuOpen) {
                  if (event.key === Qt.Key_Escape) { root.contextMenuOpen = false; event.accepted = true }
                  return
                }
                if (root.pendingDeleteNames.length > 0) {
                  if (deleteConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.renameConflictOpen) {
                  if (renameConflictConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.extractConflictOpen) {
                  if (extractConflictConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.compressConflictOpen) {
                  if (compressConflictConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.bulkRenameConflictOpen) {
                  if (bulkRenameConflictConfirm.handleKey(event)) event.accepted = true
                  return
                }
                if (root.pasteConflictOpen) {
                  if (event.key === Qt.Key_Escape) { clipboardOps.cancelPasteConflict(); event.accepted = true }
                  return
                }
                if (root.dropConflictOpen) {
                  if (event.key === Qt.Key_Escape) { dragDropOps.cancelDropConflict(); event.accepted = true }
                  return
                }
                if (root.propertiesOpen) {
                  if (event.key === Qt.Key_Escape) { root.propertiesOpen = false; event.accepted = true }
                  return
                }
                if (root.shortcutsHelpOpen) {
                  if (event.key === Qt.Key_Escape || event.key === Qt.Key_Question) { root.shortcutsHelpOpen = false; event.accepted = true }
                  return
                }
                // Red de seguridad -- bulkRenameField normalmente tiene el
                // foco y gestiona Escape/Enter él solo, pero si alguna vez
                // no lo tiene, esto evita que j/k/Supr caigan en la lista de
                // detrás con el diálogo todavía abierto encima.
                if (root.bulkRenameOpen) {
                  if (event.key === Qt.Key_Escape) { root.bulkRenameOpen = false; event.accepted = true }
                  return
                }
                // Misma red de seguridad que bulkRenameOpen -- connectServerField
                // gestiona Escape/Enter él solo mientras tiene el foco.
                if (root.connectServerOpen) {
                  if (event.key === Qt.Key_Escape) {
                    if (root.networkConnecting) mountOps.cancelNetworkConnect()
                    else mountOps.cancelConnectToServer()
                    event.accepted = true
                  }
                  return
                }
                if (root.creatingFolder || root.creatingFile || root.renamingIndex >= 0 || root.editingPath || root.searching) return

                var extend = (event.modifiers & Qt.ShiftModifier) !== 0

                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) {
                  root.openTerminalHere()
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  // Con 2+ pestañas, Escape cierra el panel activo (el que
                  // tiene el cursor encima, gracias al HoverHandler de cada
                  // panel) en vez de la ventana entera -- sustituye a la ×
                  // que había antes en cada cabecera. closeTab() ya cae en
                  // requestClose() si solo queda 1, así que el comportamiento
                  // de siempre (Escape cierra la ventana) no cambia con una
                  // sola pestaña abierta.
                  if (root.previewOpen) root.previewOpen = false
                  else tabOps.closeTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_Backspace || (event.key === Qt.Key_H && event.modifiers === Qt.NoModifier)) {
                  root.goUp()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (event.key === Qt.Key_L && event.modifiers === Qt.NoModifier)) {
                  if (root.selectedIndex >= 0) root.enter(root.visibleEntries[root.selectedIndex])
                  event.accepted = true
                } else if (event.key === Qt.Key_Space) {
                  previewLoader.togglePreview()
                  event.accepted = true
                } else if (event.key === Qt.Key_Slash) {
                  searchOps.startSearch()
                  event.accepted = true
                } else if (event.key === Qt.Key_Colon || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
                  root.openPalette()
                  event.accepted = true
                } else if (event.key === Qt.Key_Question) {
                  root.shortcutsHelpOpen = true
                  event.accepted = true
                } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                  searchOps.goBottom()
                  event.accepted = true
                } else if (event.key === Qt.Key_G && event.modifiers === Qt.NoModifier) {
                  if (root.gPending) { searchOps.goTop(); root.gPending = false }
                  else { root.gPending = true; gTimer.restart() }
                  event.accepted = true
                } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers === Qt.NoModifier)) {
                  var down = Math.min(root.visibleEntries.length - 1, root.selectedIndex + 1)
                  if (extend) root.selectRange(down); else root.selectOnly(down)
                  event.accepted = true
                } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers === Qt.NoModifier)) {
                  var up = Math.max(0, root.selectedIndex - 1)
                  if (extend) root.selectRange(up); else root.selectOnly(up)
                  event.accepted = true
                } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
                  root.selectNone()
                  event.accepted = true
                } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                  root.selectedIndices = Array.from({ length: root.visibleEntries.length }, function (_, i) { return i })
                  event.accepted = true
                } else if (event.key === Qt.Key_I && (event.modifiers & Qt.ControlModifier)) {
                  root.invertSelection()
                  event.accepted = true
                } else if (event.key === Qt.Key_F2) {
                  renameOps.startRename(root.selectedIndex)
                  event.accepted = true
                } else if (event.key === Qt.Key_Delete) {
                  deleteOps.requestDelete()
                  event.accepted = true
                } else if (event.key === Qt.Key_F5) {
                  root.refresh()
                  event.accepted = true
                } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ShiftModifier)) {
                  root.reverseSort()
                  event.accepted = true
                } else if (event.key === Qt.Key_S && event.modifiers === Qt.NoModifier) {
                  root.cycleSort()
                  event.accepted = true
                } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                  searchOps.startEditPath()
                  event.accepted = true
                } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
                  renameOps.startNewFolder()
                  event.accepted = true
                } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
                  // "New file" no tenía atajo propio, a diferencia de
                  // "New folder" (Ctrl+Shift+N, arriba) -- solo estaba en
                  // paleta/menú contextual.
                  renameOps.startNewFile()
                  event.accepted = true
                } else if (event.key === Qt.Key_Backslash && (event.modifiers & Qt.ControlModifier)) {
                  // Antes alternaba la vista dividida; ahora cada pestaña ES
                  // ya un panel visible, así que este atajo simplemente abre
                  // uno nuevo (igual que Ctrl+T).
                  tabOps.newTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) {
                  root.navBack()
                  event.accepted = true
                } else if (event.key === Qt.Key_Right && (event.modifiers & Qt.AltModifier)) {
                  root.navForward()
                  event.accepted = true
                } else if (event.key === Qt.Key_T && (event.modifiers & Qt.ControlModifier)) {
                  tabOps.newTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
                  tabOps.closeTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
                  tabOps.nextTab()
                  event.accepted = true
                } else if (event.key === Qt.Key_H && (event.modifiers & Qt.ControlModifier)) {
                  searchOps.toggleHidden()
                  event.accepted = true
                } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                  clipboardOps.copySelected()
                  event.accepted = true
                } else if (event.key === Qt.Key_X && (event.modifiers & Qt.ControlModifier)) {
                  clipboardOps.cutSelected()
                  event.accepted = true
                } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                  conflictActions.paste()
                  event.accepted = true
                } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
                  root.redoLast()
                  event.accepted = true
                } else if (event.key === Qt.Key_Y && (event.modifiers & Qt.ControlModifier)) {
                  root.redoLast()
                  event.accepted = true
                } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
                  root.undoLast()
                  event.accepted = true
                }
              }

              delegate: CursorSurface {
                id: rowSurface
                required property var modelData
                required property int index
                width: listView.width
                implicitHeight: rowContent.implicitHeight + Style.spacing.md * 2
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name + (modelData.type === "dir" ? ", folder" : ", file")
                Accessible.selected: root.isSelected(index)
                // Al reciclar delegados (recrea filas al hacer scroll),
                // implicitHeight puede pasar por 0 durante un frame antes de
                // que el layout del texto se asiente -- si se acepta ese
                // valor de paso, measuredRowHeight (compartido por todas las
                // filas) queda mal un instante, el footer recalcula su
                // altura, contentHeight cambia en pleno scroll y eso es justo
                // lo que hacía crecer el hueco de arriba en cada ciclo. Todas
                // las filas miden lo mismo, así que quedarse con el máximo
                // visto es seguro y nunca acepta un valor transitorio menor.
                onHeightChanged: {
                  if (height > root.measuredRowHeight) root.measuredRowHeight = height
                }
                foreground: Color.menu.text
                accent: Color.accent
                hasCursor: mouseArea.containsMouse
                current: root.isSelected(index) || root.dropHoverIndex === index

                DropArea {
                  // Solo las carpetas son destino válido de un drop --
                  // soltar sobre un fichero suelto no tiene sentido.
                  anchors.fill: parent
                  enabled: modelData.type === "dir"
                  keys: ["text/uri-list"]
                  onEntered: function (drag) {
                    if (!drag.hasUrls) { drag.accepted = false; return }
                    root.dropHoverIndex = index
                  }
                  onExited: if (root.dropHoverIndex === index) root.dropHoverIndex = -1
                  onDropped: function (drop) {
                    root.dropHoverIndex = -1
                    dragDropOps.handleFilesDropped(drop, root.joinPath(root.currentPath, modelData.name))
                  }
                }

                Item {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: 0
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  implicitHeight: activeFileRow.implicitHeight

                  readonly property bool isVid: root.isVideo(modelData)
                  readonly property string vidKey: isVid ? Utils.thumbKeyFor(modelData, root.currentPath) : ""
                  readonly property string vidThumb: vidKey ? (root.videoThumbReady[vidKey] || "") : ""

                  Component.onCompleted: if (isVid) videoThumbs.requestVideoThumb(modelData)

                  FileRowVisual {
                    id: activeFileRow
                    anchors.fill: parent
                    name: modelData.name
                    isDir: modelData.type === "dir"
                    isBroken: modelData.link === "broken"
                    highlighted: rowSurface.current
                    dimmed: root.clipboardMode === "cut" && root.clipboardPaths.indexOf(root.joinPath(root.currentPath, modelData.name)) >= 0
                    fileIconGlyph: root.iconFor(modelData)
                    thumbSource: root.isImage(modelData) ? Util.fileUrl(root.joinPath(root.currentPath, modelData.name))
                      : (parent.vidThumb ? Util.fileUrl(parent.vidThumb) : "")
                    metaText: fileMeta.metaFor(modelData)
                    showNameText: root.renamingIndex !== index
                  }

                  TextField {
                    id: renameField
                    visible: root.renamingIndex === index
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Rename"
                    // Misma X que nameCol dentro de FileRowVisual
                    // (thumbSlot.right + rowGap) -- ese id ya no es
                    // visible desde aquí, así que se repite con la
                    // misma constante conocida (Style.spacing.controlHeight,
                    // el ancho fijo del icono) en vez de perseguir el id.
                    anchors.left: parent.left
                    anchors.leftMargin: Style.spacing.controlHeight + Style.spacing.rowGap
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    verticalPadding: 2
                    onVisibleChanged: if (visible) { text = modelData.name; forceActiveFocus(); selectAll() } else listView.forceActiveFocus()
                    Keys.onPressed: function (event) {
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        conflictActions.commitRename(text)
                        event.accepted = true
                      } else if (event.key === Qt.Key_Escape) {
                        root.renamingIndex = -1
                        event.accepted = true
                      }
                    }
                  }
                }

                MouseArea {
                  id: mouseArea
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.left: parent.left
                  // Huecos sin cubrir a los dos lados (el contenido visual --
                  // icono, texto -- no se mueve, solo se reduce el área
                  // interactiva) para que los MouseArea de gutter de abajo
                  // puedan quedarse con el press ahí en vez de competir por
                  // hover con este. Izquierda subida de 14 a 24 -- josema
                  // probándolo en vivo dijo que sobraba distancia sin usar
                  // entre el icono y la barra separadora. Derecha iguala
                  // rowContent.anchors.rightMargin (rowPaddingX), que ya
                  // deja ese hueco sin contenido visual.
                  anchors.leftMargin: 24
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  hoverEnabled: true
                  visible: root.renamingIndex !== index
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  drag.target: dragProxy
                  drag.axis: Drag.XAndYAxis
                  onPressed: function (mouse) {
                    // Empezar a arrastrar un fichero que no formaba parte de
                    // la selección debe arrastrar solo ese fichero (como
                    // Nautilus) -- pero solo en clic simple: Ctrl/Shift+clic
                    // siguen decidiendo la selección en onClicked, sin tocar
                    // aquí el ancla de rango (selectRange).
                    if (mouse.button === Qt.LeftButton && mouse.modifiers === Qt.NoModifier && !root.isSelected(index)) {
                      root.selectOnly(index)
                    }
                    // Miniatura del arrastre: capturada aquí (no en
                    // Drag.onActiveChanged) para que le dé tiempo a
                    // completarse -- grabToImage es async (un frame) y para
                    // cuando el movimiento supera el umbral de drag ya casi
                    // siempre está lista.
                    if (mouse.button === Qt.LeftButton) {
                      rowContent.grabToImage(function (result) { dragProxy.Drag.imageSource = result.url })
                    }
                  }
                  onClicked: function (mouse) {
                    if (mouse.button === Qt.RightButton) {
                      if (!root.isSelected(index)) root.selectOnly(index)
                      var pos = mapToItem(card, mouse.x, mouse.y)
                      root.openContextMenu(pos.x, pos.y, root.itemActions())
                      return
                    }
                    if (mouse.modifiers & Qt.ControlModifier) root.toggleSelect(index)
                    else if (mouse.modifiers & Qt.ShiftModifier) root.selectRange(index)
                    else root.selectOnly(index)
                  }
                  // hasPendingEdit: no entrar (y sobre todo no entrar en
                  // un archivo comprimido) mientras hay un renombrado/
                  // nueva-carpeta/nuevo-fichero sin confirmar en esta
                  // misma fila u otra -- ver commitRename() para el bug
                  // real que esto evita.
                  onDoubleClicked: if (!root.hasPendingEdit) root.enter(modelData)
                }

                // Proxy invisible que MouseArea.drag mueve -- lo único que
                // importa de verdad es su Drag.active, que arranca el drag
                // real (interno o hacia otra app) en cuanto se supera el
                // umbral de movimiento.
                Item {
                  id: dragProxy
                  width: 1
                  height: 1
                  Drag.active: mouseArea.drag.active
                  Drag.dragType: Drag.Automatic
                  Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                  Drag.proposedAction: Qt.MoveAction
                  Drag.mimeData: dragDropOps.dragMimeDataFor(index)
                }

                // Gutters del lazo a los dos lados de la fila -- implementan
                // el arranque/arrastre directamente (no confían en que el
                // press "caiga" a algo detrás: en la franja izquierda, antes
                // de este cambio, no había nada detrás salvo el MouseArea de
                // la rueda, que se queda con cualquier click de todos modos
                // aunque solo tenga onWheel). anchors.leftMargin de
                // `mouseArea` (24) y anchors.rightMargin de `rowContent`
                // (Style.spacing.rowPaddingX) dejan estos huecos libres de
                // contenido visual, así que no roban nada al icono/texto.
                MouseArea {
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.left: parent.left
                  width: 24
                  acceptedButtons: Qt.LeftButton
                  onPressed: function (mouse) {
                    var p = mapToItem(listView.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(listView, mouse.x, mouse.y)
                    root.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
                  }
                  onPositionChanged: function (mouse) {
                    var p = mapToItem(listView.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(listView, mouse.x, mouse.y)
                    root.moveMarquee(p.x, p.y, vp.y)
                  }
                  onReleased: root.endMarquee()
                  onCanceled: root.endMarquee()
                }

                MouseArea {
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  width: Style.spacing.rowPaddingX
                  acceptedButtons: Qt.LeftButton
                  onPressed: function (mouse) {
                    var p = mapToItem(listView.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(listView, mouse.x, mouse.y)
                    root.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
                  }
                  onPositionChanged: function (mouse) {
                    var p = mapToItem(listView.contentItem, mouse.x, mouse.y)
                    var vp = mapToItem(listView, mouse.x, mouse.y)
                    root.moveMarquee(p.x, p.y, vp.y)
                  }
                  onReleased: root.endMarquee()
                  onCanceled: root.endMarquee()
                }
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
              visible: root.marqueeActive
              x: Math.min(root.marqueeStartX, root.marqueeCurrentX)
              y: Math.min(root.marqueeStartY, root.marqueeCurrentY) - listView.contentY + listView.y
              width: Math.abs(root.marqueeCurrentX - root.marqueeStartX)
              height: Math.abs(root.marqueeCurrentY - root.marqueeStartY)
              color: Util.alpha(Color.accent, 0.12)
              border.color: Color.accent
              border.width: 1
              z: 5
            }

            // ---------- Vista previa (Espacio) ----------
            PreviewPanel {
              anchors.fill: parent
              open: root.previewOpen
              entryName: root.previewEntry ? root.previewEntry.name : ""
              hasEntry: !!root.previewEntry
              isImageEntry: root.previewEntry ? root.isImage(root.previewEntry) : false
              isVideoEntry: root.previewEntry ? root.isVideo(root.previewEntry) : false
              isTextEntry: !!root.previewEntry && !root.isImage(root.previewEntry) && root.previewIsText
              isPdfEntry: root.previewEntry ? root.isPdf(root.previewEntry) : false
              isAudioEntry: root.previewEntry ? root.isAudio(root.previewEntry) : false
              imageSource: (root.previewEntry && root.isImage(root.previewEntry))
                ? Util.fileUrl(root.joinPath(root.currentPath, root.previewEntry.name)) : ""
              videoThumbSource: {
                if (!root.previewEntry || !root.isVideo(root.previewEntry)) return ""
                var p = root.videoThumbReady[Utils.thumbKeyFor(root.previewEntry, root.currentPath)] || ""
                return p ? Util.fileUrl(p) : ""
              }
              highlightedText: root.previewHighlighted
              plainText: root.previewText
              pdfImageSource: root.previewPdfImage ? Util.fileUrl(root.previewPdfImage) : ""
              audioInfo: root.previewAudioInfo
              fallbackSizeText: root.previewEntry ? Utils.formatSize(root.previewEntry.size) : ""
            }
}

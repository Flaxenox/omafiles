import QtQuick
import qs.Commons
import qs.Ui
import "../shared"
import "../state"
import "../services"
import "../Utils.js" as Utils

// Delegate de fila de la ListView principal (visual + arrastrar/soltar +
// renombrado inline + gutters del lazo) -- segundo corte de
// panels/ActiveFileList.qml (761 líneas, por encima del límite 300-500),
// después del primero (Keys.onPressed -> logic/KeyboardShortcuts.qml).
// Es un delegate (equivalente a un Repeater), así que las properties que
// vienen de fuera llevan prefijo `host*` -- si se llamaran igual que un id
// del fichero que instancia esto (root/listView/card/...), QML las
// autoenlaza a sí mismas en vez de al valor pasado (ver
// [[project_omafiles_architecture_rules]], mismo bug que BackgroundPanel.qml
// y, más tarde, el propio KeyboardShortcuts.qml pese a NO ser un delegate).
CursorSurface {
  id: rowSurface
  required property var modelData
  required property int index

  property Item hostRoot: null
  property Item hostListView: null
  property Item hostCard: null
  property Item hostDragDropOps: null
  property Item hostVideoThumbs: null
  property Item hostFileMeta: null
  property Item hostConflictActions: null
  property Item hostSelectionOps: null

  width: hostListView.width
  implicitHeight: rowContent.implicitHeight + Style.spacing.md * 2
  Accessible.role: Accessible.ListItem
  Accessible.name: modelData.name + (modelData.type === "dir" ? ", folder" : ", file")
  Accessible.selected: hostSelectionOps.isSelected(index)
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
    if (height > hostRoot.measuredRowHeight) hostRoot.measuredRowHeight = height
  }
  foreground: Color.menu.text
  accent: Color.accent
  hasCursor: mouseArea.containsMouse
  current: hostSelectionOps.isSelected(index) || DropHoverState.dropHoverIndex === index

  DropArea {
    // Solo las carpetas son destino válido de un drop --
    // soltar sobre un fichero suelto no tiene sentido.
    anchors.fill: parent
    enabled: modelData.type === "dir"
    keys: ["text/uri-list"]
    onEntered: function (drag) {
      if (!drag.hasUrls) { drag.accepted = false; return }
      DropHoverState.dropHoverIndex = index
    }
    onExited: if (DropHoverState.dropHoverIndex === index) DropHoverState.dropHoverIndex = -1
    onDropped: function (drop) {
      DropHoverState.dropHoverIndex = -1
      hostDragDropOps.handleFilesDropped(drop, Utils.joinPath(NavState.currentPath, modelData.name))
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

    readonly property bool isVid: hostRoot.isVideo(modelData)
    readonly property string vidKey: isVid ? Utils.thumbKeyFor(modelData, NavState.currentPath) : ""
    readonly property string vidThumb: vidKey ? (VideoThumbState.videoThumbReady[vidKey] || "") : ""

    // Miniatura nativa (imágenes/SVG/PDF) vía ThumbnailProvider: caché en
    // disco, no re-decodifica el fichero entero en cada scroll/revisita
    // como hacía cargar la imagen completa a 32px. imgThumb es la ruta del
    // thumbnail en caché ("" hasta que está listo -> se ve el glyph).
    readonly property string myPath: Utils.joinPath(NavState.currentPath, modelData.name)
    readonly property bool wantsThumb: hostRoot.isImage(modelData) || hostRoot.isPdf(modelData)
      || modelData.name.toLowerCase().slice(-4) === ".svg"
    property string imgThumb: ""
    // onMyPathChanged (no Component.onCompleted) porque la ListView recicla
    // los delegados: al reusar una fila para otra entrada hay que volver a
    // pedir la miniatura de la nueva ruta.
    onMyPathChanged: {
      imgThumb = wantsThumb ? ThumbnailProvider.request(myPath, 256) : ""
      _requestCount(false)
    }

    Component.onCompleted: {
      if (isVid) hostVideoThumbs.requestVideoThumb(modelData)
      if (wantsThumb) imgThumb = ThumbnailProvider.request(myPath, 256)
      _requestCount(false)
    }

    // Contador de items (Fase 23): solo carpetas, perezoso (esta fila está
    // visible) y con caché. force=true en la invalidación (refreshTick) para
    // recontar aunque ya estuviera en caché.
    readonly property bool _isDir: modelData.type === "dir"
    function _requestCount(force) {
      if (!_isDir) return
      if (!force && !FolderCountState.needsRequest(myPath)) return
      FolderCountState.markPending(myPath)
      FolderCounter.request(myPath, NavState.showHidden)
    }

    Connections {
      target: ThumbnailProvider
      function onReady(path, thumbPath) {
        if (path === rowContent.myPath) rowContent.imgThumb = thumbPath
      }
    }

    // Invalidación: cualquier operación en la app (o el watcher de la carpeta)
    // sube refreshTick -> se recuenta la carpeta de esta fila. Cubre también
    // el toggle de ocultos (toggleHidden hace refresh + refreshTick).
    Connections {
      target: NavState
      function onRefreshTickChanged() { rowContent._requestCount(true) }
    }

    FileRowVisual {
      id: activeFileRow
      anchors.fill: parent
      name: modelData.name
      isDir: modelData.type === "dir"
      isBroken: modelData.link === "broken"
      highlighted: rowSurface.current
      dimmed: ClipboardState.clipboardMode === "cut" && ClipboardState.clipboardPaths.indexOf(Utils.joinPath(NavState.currentPath, modelData.name)) >= 0
      fileIconGlyph: hostRoot.iconFor(modelData)
      thumbSource: rowContent.imgThumb ? Util.fileUrl(rowContent.imgThumb)
        : (rowContent.vidThumb ? Util.fileUrl(rowContent.vidThumb) : "")
      metaText: hostFileMeta.metaFor(modelData)
      metaTooltip: hostFileMeta.metaTooltipFor(modelData)
      showNameText: EditModeState.renamingIndex !== index
    }

    TextField {
      id: renameField
      visible: EditModeState.renamingIndex === index
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
      onVisibleChanged: if (visible) { text = modelData.name; forceActiveFocus(); selectAll() } else hostListView.forceActiveFocus()
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          hostConflictActions.commitRename(text)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          EditModeState.renamingIndex = -1
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
    visible: EditModeState.renamingIndex !== index
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
      if (mouse.button === Qt.LeftButton && mouse.modifiers === Qt.NoModifier && !hostSelectionOps.isSelected(index)) {
        hostSelectionOps.selectOnly(index)
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
        if (!hostSelectionOps.isSelected(index)) hostSelectionOps.selectOnly(index)
        var pos = mapToItem(hostCard, mouse.x, mouse.y)
        hostRoot.openContextMenu(pos.x, pos.y, hostRoot.itemActions())
        return
      }
      if (mouse.modifiers & Qt.ControlModifier) hostSelectionOps.toggleSelect(index)
      else if (mouse.modifiers & Qt.ShiftModifier) hostSelectionOps.selectRange(index)
      else hostSelectionOps.selectOnly(index)
    }
    // hasPendingEdit: no entrar (y sobre todo no entrar en
    // un archivo comprimido) mientras hay un renombrado/
    // nueva-carpeta/nuevo-fichero sin confirmar en esta
    // misma fila u otra -- ver commitRename() para el bug
    // real que esto evita.
    onDoubleClicked: if (!hostRoot.hasPendingEdit) hostRoot.enter(modelData)
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
    Drag.mimeData: hostDragDropOps.dragMimeDataFor(index)
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
  MarqueeCatcher {
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    width: 24
    catcherListView: hostListView
    catcherSelectionOps: hostSelectionOps
  }

  MarqueeCatcher {
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    width: Style.spacing.rowPaddingX
    catcherListView: hostListView
    catcherSelectionOps: hostSelectionOps
  }
}

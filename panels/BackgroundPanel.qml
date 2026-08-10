import QtQuick
import qs.Commons
import qs.Ui
import "../shared"
import "../state"
import "../services"
import "../logic"
import "../Utils.js" as Utils

// Delegado de los paneles "de fondo" (todas las pestañas salvo la activa),
// decimonoveno componente extraído de Omafiles.qml. Cada uno tiene su
// propio listado (su propio Process), sin lazo de selección ni menú
// contextual propio -- solo navegar con doble clic y arrastrar, el panel
// activo (que se queda en Omafiles.qml) ya tiene todo lo demás.
// hostPanelsRow se pasa como propiedad aparte de hostRoot -- es quien calcula
// x/width/height de este panel (slotX/slotWidth), y sin pasarlo explícito
// no es visible desde este fichero.
Item {
  id: bgPanel
  property Item hostRoot: null
  property Item hostPanelsRow: null
  property Item hostVideoThumbs: null
  property Item hostDragDropOps: null
  property Item hostFileMeta: null
  property Item hostTabOps: null
  property Item hostSortOps: null
  required property var modelData
  required property int index
  visible: index !== TabsState.activeTabIndex
  x: hostPanelsRow.slotX(index)
  y: 0
  width: hostPanelsRow.slotWidth
  height: hostPanelsRow.height
  // Atenuado respecto al panel activo -- con "el panel activo es el que
  // tiene el ratón encima" (ver HoverHandler más abajo), sin ninguna señal
  // visual era fácil no darse cuenta de a qué panel le estaban llegando
  // los atajos de teclado y actuar sobre el equivocado sin querer. Solo
  // opacidad, sin tocar colores del tema.
  opacity: 0.72

  // El listado en sí vive en DirLister (Fase 1.6, josema) -- mismo
  // mecanismo que usa el panel activo (NavigationController), pero con
  // su propia instancia: varias pestañas de fondo pueden estar listando
  // rutas distintas a la vez, así que no pueden compartir un único
  // Process. entries/pathError/loaded ya no son propiedades propias de
  // bgPanel -- se leen directo de dirLister en todo el fichero.
  DirLister {
    id: dirLister
    trashDir: Paths.trashDir
    showHidden: NavState.showHidden
    sortOps: hostSortOps
    // hostRoot.tabEntriesCache es lo que _goToPath() consulta al entrar
    // en una ruta que un panel de fondo ya tenía lista -- solo lo
    // rellenan los paneles de fondo (ver NavigationController, que NO
    // escribe aquí).
    onListed: bgPanel._cachePut(bgPanel.modelData.path, dirLister.entries)
  }

  // LRU de la caché de entradas por ruta (Fase 10.A): antes crecía sin
  // límite (una entrada por cada carpeta visitada en CUALQUIER pestaña de
  // fondo, reteniendo miles de objetos en sesiones largas con keepLoaded).
  // Se acota a las 8 rutas más recientes usando el orden de inserción de las
  // claves del objeto (borrar+reinsertar mueve al final = más reciente;
  // se evict las del principio = más antiguas).
  readonly property int _cacheMax: 8
  function _cachePut(path, entries) {
    var c = hostRoot.tabEntriesCache
    if (c[path] !== undefined) delete c[path]
    c[path] = entries
    var keys = Object.keys(c)
    while (keys.length > _cacheMax) { delete c[keys[0]]; keys.shift() }
  }

  // Pasar el ratón por encima hace que este panel se vuelva el activo (el
  // que tiene lazo de selección, menú contextual, y responde a los atajos
  // de teclado j/k/F2/Supr/etc.) -- sin esto solo se podía "activar" un
  // panel haciendo clic dentro, y josema quería que baste con colocar el
  // cursor encima. HoverHandler en vez de MouseArea: no roba el evento a
  // los MouseArea de las filas/botones de debajo, solo observa.
  HoverHandler {
    // No cambiar de panel activo mientras el usuario tiene un nombre a
    // medio escribir (rename/nueva carpeta/nuevo fichero/ruta editable) --
    // switchToTab -> _goToPath resetea esos campos, y con hover-to-activate
    // bastaba con cruzar el ratón por el divisor para perder el texto sin
    // ningún clic de por medio. Tampoco con el menú contextual abierto --
    // bug real: el menú se abre sobre el panel activo de ESE momento, pero
    // si el cursor pasaba por otro panel de fondo de camino a una entrada
    // del menú (nada bloqueaba el hover solo por haber un menú encima), la
    // pestaña activa cambiaba a mitad de acción y "Open in new tab"/Copy/
    // etc. acababan actuando sobre la carpeta equivocada.
    // El guard real vive ahora en switchToTab() (hasBlockingOverlay), así
    // cubre TODOS los diálogos, no solo estos dos.
    onHoveredChanged: if (hovered) hostTabOps.switchToTab(bgPanel.index)
  }

  // Última ruta para la que este panel concreto ha lanzado una recarga --
  // ver onModelDataChanged más abajo.
  property string _lastRefreshedPath: ""

  function refreshMe() {
    if (!bgPanel.visible) return
    bgPanel._lastRefreshedPath = bgPanel.modelData.path
    dirLister.list(bgPanel.modelData.path)
  }

  onVisibleChanged: if (visible) bgPanel.refreshMe()
  // TabOps.saveActiveTab() reasigna TabsState.tabs entero (para guardar el
  // estado de la pestaña que se abandona) cada vez que se cambia de
  // pestaña -- eso dispara onModelDataChanged en TODOS los paneles de
  // fondo del Repeater, aunque la ruta de ESTE panel concreto no haya
  // cambiado en absoluto. Sin este guard, cada cambio de pestaña recargaba
  // el listado de fondo DOS veces (una por el reset del array, otra real
  // por el cambio de visibilidad) -- trabajo doble e innecesario que
  // contribuía al asentamiento visible al cambiar de panel con la
  // papelera abierta (reportado por josema).
  onModelDataChanged: if (bgPanel.modelData.path !== bgPanel._lastRefreshedPath) bgPanel.refreshMe()
  // refreshTick es la señal para que los paneles NO activos se refresquen
  // tras una acción (borrar/mover/pegar/renombrar), que puede afectar a
  // cualquier panel y no solo al activo. Vive en NavState desde la Fase 14.C
  // -- antes estaba en OmafilesContent (hostRoot) y este Connections quedó
  // escuchando un target sin esa señal (regresión silenciosa detectada en la
  // auditoría 14.E: qmllint no la ve porque hostRoot es Item sin tipar).
  Connections {
    target: NavState
    function onRefreshTickChanged() { bgPanel.refreshMe() }
  }
  Component.onCompleted: bgPanel.refreshMe()

  DropArea {
    anchors.fill: parent
    keys: ["text/uri-list"]
    onEntered: function (drag) { if (!drag.hasUrls) drag.accepted = false }
    onDropped: function (drop) { hostDragDropOps.handleFilesDropped(drop, bgPanel.modelData.path) }
  }

  Row {
    id: bgHeaderRow
    anchors.top: parent.top
    width: parent.width
    height: Style.spacing.controlHeight
    spacing: Style.spacing.controlGap

    // Misma cabecera que el panel activo (atrás/adelante/casa/subir) --
    // josema pidió que las dos se vean iguales, no solo el panel activo
    // con navegación completa.
    PanelNavButtons {
      canGoBack: (bgPanel.modelData.historyIndex || 0) > 0
      canGoForward: (bgPanel.modelData.historyIndex || 0) < (bgPanel.modelData.history || [bgPanel.modelData.path]).length - 1
      canGoUp: bgPanel.modelData.path !== "/"
      onBackRequested: hostTabOps.navTabBack(bgPanel.index)
      onForwardRequested: hostTabOps.navTabForward(bgPanel.index)
      onUpRequested: {
        var p = bgPanel.modelData.path
        var idx = p.lastIndexOf("/")
        hostTabOps.navigateTabTo(bgPanel.index, idx > 0 ? p.substring(0, idx) : "/")
      }
    }

    // Migas de pan completas, igual que en el panel activo -- antes solo
    // se veía el nombre de la carpeta actual, sin el resto de la ruta.
    BreadcrumbSegments {
      id: bgBreadcrumbRow
      width: parent.width - 3 * Style.spacing.controlHeight - 3 * Style.spacing.controlGap
      height: parent.height
      segments: hostRoot.pathSegmentsFor(bgPanel.modelData.path)
      activePath: bgPanel.modelData.path
    }
  }

  PanelSeparator {
    id: bgHeaderSep
    anchors.top: bgHeaderRow.bottom
    // Mismo hueco que separa navRow de listContainer en el panel activo
    // (Style.spacing.rowGap, el mismo spacing de mainColumn -- no
    // Style.spacing.sm) -- con sm quedaba visiblemente más alto que la
    // línea del panel activo.
    anchors.topMargin: Style.spacing.rowGap
    width: parent.width
    foreground: Color.menu.text
    strength: 0.15
  }

  Text {
    id: bgErrorText
    visible: dirLister.pathError !== ""
    anchors.top: bgHeaderSep.bottom
    anchors.topMargin: Style.spacing.sm
    width: parent.width
    text: dirLister.pathError
    font.pixelSize: Style.font.subtitle
    font.family: Style.font.family
    color: Color.urgent
  }

  ListView {
    id: bgList
    anchors.top: bgErrorText.visible ? bgErrorText.bottom : bgHeaderSep.bottom
    anchors.topMargin: Style.spacing.md
    anchors.bottom: bgStatusText.top
    anchors.bottomMargin: Style.spacing.rowGap
    anchors.left: parent.left
    anchors.right: parent.right
    clip: true
    model: dirLister.entries
    boundsBehavior: Flickable.StopAtBounds

    delegate: CursorSurface {
      id: bgRowSurface
      required property var modelData
      required property int index
      width: bgList.width
      implicitHeight: bgRowContent.implicitHeight + Style.spacing.md * 2
      foreground: Color.menu.text
      accent: Color.accent
      hasCursor: bgRowMouse.containsMouse
      // El fill/borde de hover ya es semitransparente de por sí
      // (Style.hoverFillFor) -- bgPanel entero va a opacity:0.72 para
      // marcarse como "no es el panel activo", y sin esto esa opacidad se
      // multiplica TAMBIÉN sobre el hover, quedando doblemente débil/
      // desvaído en vez del mismo aspecto que tiene en el panel activo.
      // 1/0.72 cancela justo la opacidad del padre solo mientras esta
      // fila concreta tiene el cursor encima.
      opacity: hasCursor ? 1 / 0.72 : 1

      DropArea {
        visible: modelData.type === "dir"
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: function (drag) { if (!drag.hasUrls) drag.accepted = false }
        onDropped: function (drop) {
          hostDragDropOps.handleFilesDropped(drop, Utils.joinPath(bgPanel.modelData.path, modelData.name))
        }
      }

      Item {
        id: bgRowContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 0
        anchors.rightMargin: Style.spacing.rowPaddingX
        implicitHeight: bgFileRow.implicitHeight

        readonly property bool isVid: hostRoot.isVideo(modelData)
        readonly property string vidKey: isVid ? Utils.thumbKeyFor(modelData, bgPanel.modelData.path) : ""
        readonly property string vidThumb: vidKey ? (VideoThumbState.videoThumbReady[vidKey] || "") : ""

        // Miniatura nativa (imágenes/SVG/PDF) vía ThumbnailProvider -- Fase
        // 10.A: antes se cargaba el fichero de imagen COMPLETO para pintarlo
        // a 32 px. Mismo patrón que FileListRow, con la ruta de ESTE panel.
        readonly property string myPath: Utils.joinPath(bgPanel.modelData.path, modelData.name)
        readonly property bool wantsThumb: hostRoot.isImage(modelData) || hostRoot.isPdf(modelData)
          || modelData.name.toLowerCase().slice(-4) === ".svg"
        property string imgThumb: ""
        onMyPathChanged: {
          imgThumb = wantsThumb ? ThumbnailProvider.request(myPath, 256) : ""
          _requestCount(false)
        }

        Component.onCompleted: {
          if (isVid) hostVideoThumbs.requestVideoThumb(modelData, bgPanel.modelData.path)
          if (wantsThumb) imgThumb = ThumbnailProvider.request(myPath, 256)
          _requestCount(false)
        }

        // Contador de items (Fase 23): igual que FileListRow, con la ruta de
        // ESTE panel de fondo. La caché FolderCountState es global (por ruta).
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
            if (path === bgRowContent.myPath) bgRowContent.imgThumb = thumbPath
          }
        }

        Connections {
          target: NavState
          function onRefreshTickChanged() { bgRowContent._requestCount(true) }
        }

        FileRowVisual {
          id: bgFileRow
          anchors.fill: parent
          name: modelData.name
          isDir: modelData.type === "dir"
          isBroken: modelData.link === "broken"
          fileIconGlyph: hostRoot.iconFor(modelData)
          // La ruta es la de ESTE panel (bgPanel.modelData.path), no
          // hostRoot.currentPath -- ese es del panel activo, y era justo lo
          // que hacía fallar la miniatura aquí cuando este panel no era
          // el activo.
          thumbSource: bgRowContent.imgThumb ? Util.fileUrl(bgRowContent.imgThumb)
            : (bgRowContent.vidThumb ? Util.fileUrl(bgRowContent.vidThumb) : "")
          metaText: hostFileMeta.metaFor(modelData, bgPanel.modelData.path)
          metaTooltip: hostFileMeta.metaTooltipFor(modelData, bgPanel.modelData.path)
        }
      }

      MouseArea {
        id: bgRowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        drag.target: bgDragProxy
        drag.axis: Drag.XAndYAxis
        onDoubleClicked: {
          if (modelData.type === "dir") {
            hostTabOps.navigateTabTo(bgPanel.index, Utils.joinPath(bgPanel.modelData.path, modelData.name))
          } else {
            hostRoot.openWithDefault(Utils.joinPath(bgPanel.modelData.path, modelData.name))
          }
        }
      }

      Item {
        id: bgDragProxy
        width: 1
        height: 1
        Drag.active: bgRowMouse.drag.active
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
        Drag.proposedAction: Qt.MoveAction
        Drag.mimeData: {
          var data = {}
          data["text/uri-list"] = Util.fileUrl(Utils.joinPath(bgPanel.modelData.path, modelData.name))
          return data
        }
      }
    }
  }

  EmptyState {
    visible: dirLister.pathError === "" && dirLister.entries.length === 0
    centerOn: bgList
    message: bgPanel.modelData.path === Paths.trashDir ? "Trash is empty" : "Nothing here yet"
  }

  Text {
    id: bgStatusText
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text: dirLister.entries.length + (dirLister.entries.length === 1 ? " item" : " items")
    font.pixelSize: Style.font.subtitle
    font.family: Style.font.family
    color: Color.menu.text
    opacity: 0.55
  }
}

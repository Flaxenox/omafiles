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
  // SIEMPRE renderizado (no `visible:false`): una ListView invisible no hace su
  // layout (contentHeight=0), así que al pasar a fondo positionViewAtIndex no
  // acertaba hasta un par de frames después -> el salto de scroll. Con opacity:0
  // (en el slot activo) la ListView SIGUE con layout real (ch>0), tapada por el
  // activePanel que va encima en el mismo slot; al pasar a fondo se posiciona al
  // instante, congelada. Los slots de fondo van al 0.72 de atenuado de siempre.
  visible: true
  opacity: index === TabsState.activeTabIndex ? 0 : 0.72
  x: hostPanelsRow.slotX(index)
  y: 0
  width: hostPanelsRow.slotWidth
  height: hostPanelsRow.height

  // Búsqueda POR PANEL (Fase 26, josema): si esta pestaña quedó en modo
  // búsqueda GLOBAL (2+ chars) al pasar a segundo plano, el panel de fondo la
  // mantiene abierta -- barra + resultados -- hasta que se cierre con la X. El
  // estado (searching/searchQuery/searchEntries/searchTruncated) lo guarda
  // TabOps.saveActiveTab en el propio objeto de pestaña (modelData), así cada
  // panel tiene su búsqueda independiente en vez de una global compartida.
  readonly property bool bgSearching: modelData.searching === true
    && (modelData.searchQuery || "").length >= 2
  // Resultados EN CRUDO guardados por TabOps (para el "of N" del footer).
  readonly property var bgSearchEntries: modelData.searchEntries || []
  // Mismo filtro por NOMBRE que aplica el panel activo (NavState.visibleEntries):
  // la búsqueda global trae también coincidencias por RUTA (p.ej. carpetas
  // DENTRO de Steam/ como bin/ o logs/, cuyo nombre no contiene el término). El
  // panel activo las oculta; sin esto, el panel de fondo mostraba MÁS resultados
  // que el activo para la misma búsqueda. Ahora los dos enseñan lo mismo.
  readonly property var bgVisibleSearchEntries: {
    var q = (modelData.searchQuery || "").toLowerCase()
    return bgSearchEntries.filter(function (e) { return e.name.toLowerCase().indexOf(q) >= 0 })
  }

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
    onListed: {
      bgPanel._cachePut(bgPanel.effectivePath, dirLister.entries)
      // Refresca el contenido pintado SOLO si de verdad cambió (Utils
      // .entriesEqual): así, al pasar a fondo con la carpeta sin cambios, NO se
      // reasigna el modelo -> la ListView no resetea el scroll -> sin salto. Si
      // cambió (ficheros nuevos), se reasigna y se re-posiciona.
      if (!Utils.entriesEqual(dirLister.entries, bgPanel._content)) {
        bgPanel._content = dirLister.entries
        bgPanel._restoreScroll()
      }
    }
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

  // Ruta que este panel debe listar. Para la pestaña ACTIVA es NavState
  // .currentPath (el objeto de pestaña NO se actualiza hasta el cambio, así que
  // usar modelData.path dejaba el panel del slot activo con la carpeta ANTERIOR
  // y su lista VACÍA/desfasada -> al pasar a fondo se poblaba async y saltaba).
  // Para las pestañas de fondo es su propia ruta guardada. Así el panel del slot
  // activo (opacity:0, tapado por el panel activo) va PRECARGANDO la carpeta
  // actual, y al pasar a fondo ya tiene el contenido y el layout -> el
  // reposicionamiento es instantáneo, congelado, sin salto.
  readonly property string effectivePath: index === TabsState.activeTabIndex
    ? NavState.currentPath : (modelData.path || "")
  onEffectivePathChanged: bgPanel.refreshMe()

  // Contenido que pinta la ListView de fondo. Se adopta SÍNCRONO desde el objeto
  // de pestaña (modelData.entries, que TabOps guardó = lo que veía el panel
  // activo) al pasar a segundo plano, para que la lista NO esté vacía en ese
  // instante (si se poblara async, el scroll saltaría de 0 a su sitio). El
  // dirLister lo refresca por detrás sin resetear si el contenido no cambió.
  property var _content: []

  function refreshMe() {
    if (bgPanel.effectivePath === "") return
    bgPanel._lastRefreshedPath = bgPanel.effectivePath
    dirLister.list(bgPanel.effectivePath)
  }

  // Al pasar a segundo plano (ya no es la pestaña activa): restaurar el scroll.
  // El contenido ya está precargado (el slot activo listaba effectivePath en
  // vivo) y con layout (opacity:0 mantiene la ListView en el scene graph), así
  // que positionViewAtIndex acierta al instante. NO se re-lista aquí: la ruta no
  // ha cambiado, y re-listar reseteaba la lista -> el salto.
  readonly property bool isBackground: index !== TabsState.activeTabIndex
  onIsBackgroundChanged: if (isBackground) {
    // Adopta el contenido guardado en la pestaña (síncrono, no vacío) ANTES de
    // posicionar, y refresca por detrás.
    bgPanel._content = bgPanel.modelData.entries || []
    bgPanel._restoreScroll()
    bgPanel.refreshMe()
  }
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

  // Scroll compartido con el panel activo (tab.scrollY = list.contentY). Al
  // pasar ESTE panel a segundo plano hay que reflejar en su bgList el scroll que
  // tenía como panel activo; si no, saltaba al principio. Se llama desde
  // dirLister.onListed (cuando el relistado async ya está puesto, si no ese
  // relistado resetearía el contentY justo después).
  function _restoreScroll() {
    // Por ÍNDICE (positionViewAtIndex), no por píxel: inmune a que el
    // contentHeight se estime perezosamente. Fallback a contentY si no hay
    // índice guardado (pestañas antiguas / raíz sin scroll).
    var idx = modelData.scrollIndex
    if (idx !== undefined && idx >= 0) {
      // Una ListView recién hecha visible aún no ha hecho su layout (contentHeight
      // = 0), así que positionViewAtIndex daría 0 y el scroll saltaría al medirse
      // async. forceLayout() completa el layout SÍNCRONO -> geometría real ->
      // positionViewAtIndex acierta a la primera, sin salto.
      // Anclado en la y REAL de la fila (misma geometría que firstVisibleOffset
      // al guardar), no en el contentY que deja positionViewAtIndex -> sin drift.
      bgList.forceLayout()
      bgList.positionViewAtIndex(idx, ListView.Beginning)
      var it = bgList.itemAtIndex(idx)
      if (it) bgList.contentY = it.y + (modelData.scrollOffset || 0)
    } else {
      bgList.contentY = modelData.scrollY || bgList.originY
    }
  }
  // Y al revés: si desplazas este panel de fondo, se guarda en su objeto de
  // pestaña para que al activarlo (list.contentY = tab.scrollY) quede igual.
  // Solo al soltar (onMovementEnded), no por píxel, para no reasignar
  // TabsState.tabs constantemente.
  function _saveScroll() {
    if (index < 0 || index >= TabsState.tabs.length) return
    var t = TabsState.tabs[index]
    if (!t || t.scrollY === bgList.contentY) return
    var idx = bgList.indexAt(bgList.width / 2, bgList.contentY + 4)
    var it = idx >= 0 ? bgList.itemAtIndex(idx) : null
    var off = it ? (bgList.contentY - it.y) : 0
    var next = TabsState.tabs.slice()
    next[index] = Object.assign({}, t, { "scrollY": bgList.contentY, "scrollIndex": idx, "scrollOffset": off })
    TabsState.tabs = next
  }

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
      id: bgNavButtons
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
      // Misma anchura que el breadcrumb del panel activo (pathArea en
      // MainLayout): reserva el hueco de la lupa colapsada (collapsedW =
      // controlHeight) + su separación, aunque aquí NO haya lupa (la búsqueda
      // es solo del panel activo). Así el breadcrumb no cambia de anchura al
      // pasar el panel a activo -- sin desplazamiento horizontal al alternar
      // de panel (Sprint Visual 3, B-06).
      width: parent.width - bgNavButtons.width - bgSearchPlaceholder.width - 2 * Style.spacing.controlGap
      height: parent.height
      segments: hostRoot.pathSegmentsFor(bgPanel.modelData.path)
      activePath: bgPanel.modelData.path
    }

    // Hueco de la lupa. En reposo va vacío (solo reserva el ancho de la lupa
    // colapsada del panel activo, para que la cabecera tenga la misma geometría
    // en ambos estados). Si ESTE panel de fondo tiene una búsqueda abierta,
    // crece a una barra de solo lectura: consulta + X para cerrarla. Es de solo
    // lectura porque para EDITAR se activa el panel (pasando el ratón), que ya
    // trae la lupa interactiva completa.
    Item {
      id: bgSearchPlaceholder
      // Mismo ancho expandido que la SearchBar activa (core/MainLayout): 300 px
      // literales (NO Style.space, que lo escalaría y lo hacía más ancho que la
      // original), recortado por lo que quede tras reservar 120 px de breadcrumb
      // (pathArea.minPathW). En reposo, solo el ancho de la lupa colapsada.
      width: bgPanel.bgSearching
        ? Math.max(Style.spacing.controlHeight, Math.min(300, bgHeaderRow.width - bgNavButtons.width - 120 - 2 * Style.spacing.controlGap))
        : Style.spacing.controlHeight
      height: parent.height

      // Indicador de SOLO LECTURA de la búsqueda abierta en este panel de
      // fondo (lupa + consulta). No lleva controles propios: con "activar al
      // pasar el ratón", cualquier botón aquí se volvería inalcanzable (el
      // hover activaría el panel y sustituiría esta barra por la lupa
      // interactiva antes de poder pulsarlo). Para editar o CERRAR la búsqueda
      // se activa el panel (pasando el ratón) y se usa la lupa interactiva de
      // siempre (Escape, o clic en la propia lupa).
      // Misma geometría y tokens que la SearchBar activa expandida (fondo
      // selectedBackground + borde menu.border, lupa CENTRADA en un slot de
      // controlHeight, texto arrancando en iconSlot.right + xs) para que las dos
      // barras se vean idénticas -- antes la lupa quedaba pegada al texto y
      // desalineada respecto al original.
      Rectangle {
        anchors.fill: parent
        visible: bgPanel.bgSearching
        radius: Style.cornerRadius
        color: Color.menu.selectedBackground
        border.width: Style.spacing.hairline
        border.color: Color.menu.border

        Item {
          id: bgSearchIconSlot
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.spacing.controlHeight
          height: Style.spacing.controlHeight

          OpticalGlyph {
            anchors.centerIn: parent
            text: "\u{F0349}" // nf-md-magnify
            fontFamily: Style.font.family
            fontSize: Style.font.icon
            color: Color.menu.selectedText
          }
        }

        Text {
          anchors.left: bgSearchIconSlot.right
          // El TextField activo empieza el texto en xs + su leftPadding interno
          // (Style.spacing.controlPaddingX). Un Text plano no tiene ese padding,
          // así que se replica aquí para que "steam" arranque a la MISMA x que en
          // la barra activa (si no, queda más a la izquierda).
          anchors.leftMargin: Style.spacing.xs + Style.spacing.controlPaddingX
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          text: bgPanel.modelData.searchQuery || ""
          elide: Text.ElideRight
          color: Color.menu.selectedText
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }
      }
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
    // Mismo ancla y margen que el aviso de error del panel activo
    // (ActiveFileList): justo bajo el separador de la cabecera, a
    // Style.spacing.md -- así el mismo error sale en la MISMA posición en los
    // dos paneles (Sprint Visual 3, C-05). Antes era sm y no coincidía con el
    // del panel activo.
    visible: dirLister.pathError !== "" && !bgPanel.bgSearching
    anchors.top: bgHeaderSep.bottom
    anchors.topMargin: Style.spacing.md
    // Mismo alineado que el aviso del panel activo (ActiveFileList): columna
    // del icono (sin leftMargin) y centrado en el alto de una fila, para
    // quedar a la altura del glyph con el mismo espaciado superior que el resto.
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    height: Style.spacing.controlHeight
    verticalAlignment: Text.AlignVCenter
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
    // Resultados de la búsqueda de ESTE panel si la tiene abierta; si no, su
    // listado normal de carpeta.
    model: bgPanel.bgSearching ? bgPanel.bgVisibleSearchEntries : bgPanel._content
    boundsBehavior: Flickable.StopAtBounds
    onMovementEnded: bgPanel._saveScroll()

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
          hostDragDropOps.handleFilesDropped(drop, Utils.entryPath(bgPanel.modelData.path, modelData))
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
        readonly property string myPath: Utils.entryPath(bgPanel.modelData.path, modelData)
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
          if (bgPanel.bgSearching) {
            // Resultado de búsqueda global: REVELAR en este panel -- carpeta ->
            // entrar en ella; fichero -> ir a su carpeta. navigateTabTo ya deja
            // el objeto de pestaña sin campos de búsqueda, así que la búsqueda
            // se cierra sola al navegar.
            hostTabOps.navigateTabTo(bgPanel.index, modelData.type === "dir" ? modelData.path : modelData.parent)
          } else if (modelData.type === "dir") {
            hostTabOps.navigateTabTo(bgPanel.index, Utils.joinPath(bgPanel.modelData.path, modelData.name))
          } else {
            hostRoot.openWithDefault(Utils.entryPath(bgPanel.modelData.path, modelData))
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
    // `dirLister.loaded` (no solo entries.length === 0): el logo de carpeta
    // vacía SOLO cuando el listado está confirmado. Un panel de fondo que
    // acaba de hacerse visible (al cambiar de pestaña o al pasar el cursor)
    // arranca con entries=[] y loaded=false hasta que refreshMe() termina de
    // listar de forma asíncrona -- sin este guard, EmptyState cumplía
    // entries.length===0 && pathError==="" y parpadeaba un frame aunque la
    // carpeta no estuviera vacía. loaded se pone a true en el primer _apply
    // (incluido el de una carpeta realmente vacía) y no vuelve a false, y
    // list() nunca vacía entries en un refresh, así que esto no oculta nunca
    // un vacío real ni parpadea al refrescar.
    visible: dirLister.loaded && dirLister.pathError === "" && dirLister.entries.length === 0
    centerOn: bgList
    message: bgPanel.modelData.path === Paths.trashDir ? "Trash is empty" : "Nothing here yet"
  }

  Text {
    id: bgStatusText
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    // Mismo formato que el footer del panel activo (statusText en
    // MainLayout): "N items · sort: <criterio>". El criterio de orden es
    // global (SortState, vía hostSortOps.sortLabel()), así que el panel de
    // fondo lista con el MISMO orden -- omitirlo hacía que las dos vistas se
    // vieran distintas al mover el cursor. Los extras del panel activo
    // (selección/portapapeles/búsqueda) son estados que solo existen ahí, no
    // en un panel de fondo, así que no se replican.
    // Con búsqueda abierta, el footer refleja los RESULTADOS de este panel
    // (recuento + aviso de lista recortada), igual que el footer del panel
    // activo al buscar; si no, el listado normal de la carpeta.
    text: bgPanel.bgSearching
      ? (bgPanel.bgVisibleSearchEntries.length + (bgPanel.bgVisibleSearchEntries.length === 1 ? " item" : " items")
         + " of " + bgPanel.bgSearchEntries.length
         + (bgPanel.modelData.searchTruncated ? " · showing first 200" : ""))
      : (dirLister.entries.length + (dirLister.entries.length === 1 ? " item" : " items")
         + " · sort: " + hostSortOps.sortLabel())
    font.pixelSize: Style.font.subtitle
    font.family: Style.font.family
    color: Color.menu.text
    opacity: Style.emphasis.secondary
  }
}

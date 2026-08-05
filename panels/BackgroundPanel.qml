import QtQuick
import qs.Commons
import qs.Ui
import "../shared"
import "../state"
import "../services"
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

  property var entries: []
  property string pathError: ""
  property bool loaded: false

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
    bgPanel.pathError = ""
    // Papelera: igual que hostRoot.refresh() con el panel activo -- no es una
    // carpeta real, agrega la de casa más la de cualquier otro disco
    // montado (list-trash.sh), así que list-dir.sh a secas contra
    // trashDir solo ve la de casa y con eso vacía se veía como "papelera
    // vacía" hasta que este panel pasaba a ser el activo.
    if (bgPanel.modelData.path === hostRoot.trashDir) {
      bgListProc.start([hostRoot.pluginDir + "/list-trash.sh", hostRoot.showHidden ? "1" : "0"])
    } else {
      bgListProc.start([hostRoot.pluginDir + "/list-dir.sh", bgPanel.modelData.path, hostRoot.showHidden ? "1" : "0"])
    }
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
  Connections {
    target: hostRoot
    function onRefreshTickChanged() { bgPanel.refreshMe() }
  }
  Component.onCompleted: bgPanel.refreshMe()

  // Reasigna bgPanel.entries SOLO si el contenido de verdad cambió --
  // igual que root._applyEntries() en Omafiles.qml (mismo bug real): la
  // ListView no compara el contenido de un array modelo, solo la
  // referencia, así que reasignar aunque los datos sean idénticos
  // dispara un relayout completo. Al pasar de panel activo a panel de
  // fondo (Escape, hover a otro panel...), este mismo bgListProc se
  // relanza vía refreshMe() (ver onVisibleChanged más abajo) aunque el
  // contenido casi siempre sea el mismo que ya tenía -- ESE relayout
  // innecesario era el salto real reportado por josema en la dirección
  // "principal a secundaria".
  function _applyEntries(parsed) {
    if (JSON.stringify(parsed) !== JSON.stringify(bgPanel.entries)) bgPanel.entries = parsed
    bgPanel.loaded = true
  }

  ProcessRunner {
    id: bgListProc
    onFinished: function (result) {
      if (result.exitCode === 2) bgPanel.pathError = "Permission denied"
      else if (result.exitCode === 3) bgPanel.pathError = "This folder no longer exists"
      else if (result.exitCode === 4) bgPanel.pathError = "Not a folder"
      else if (result.exitCode !== 0) bgPanel.pathError = "Couldn't open this folder"
      var parsed = hostSortOps.sortEntries(Utils.parseEntries(result.stdout))
      hostRoot.tabEntriesCache[bgPanel.modelData.path] = parsed
      if (bgPanel.modelData.path === hostRoot.trashDir) {
        if (Object.keys(TrashState.trashInfo).length > 0) {
          // Ya hay trashInfo cargada -- de este mismo panel en una
          // visita anterior, del panel activo, o de OTRO panel de
          // fondo (TrashState.trashInfo es compartida entre todos, ver
          // bgTrashInfoProc más abajo: trash-info.sh siempre devuelve
          // TODA la papelera, no depende de qué panel pregunte).
          // Pintar ya con eso; el trashInfoProc que sigue solo la
          // refresca por detrás sin bloquear el primer pintado.
          bgPanel._applyEntries(parsed)
        } else {
          // Primera vez que se ve la papelera en toda la sesión -- sin
          // nada previo que enseñar, esperar a que trash-info.sh
          // termine para pintar ya con el texto final ("Deleted X ago
          // · from ...") de una sola vez. Si se pintara ya con solo el
          // tamaño y esa parte llegara un instante después, el texto
          // más largo haría crecer bgFileRow y todas las filas de
          // debajo saltarían de sitio (parpadeo real, reportado por
          // josema).
          bgPanel._waitingForTrashInfo = true
          bgPanel._pendingEntries = parsed
        }
        bgTrashInfoProc.start([hostRoot.pluginDir + "/trash-info.sh"])
      } else {
        bgPanel._applyEntries(parsed)
      }
    }
  }

  // Ver el comentario en bgListProc.onStreamFinished -- guardan las
  // entries leídas mientras se espera al primer trash-info.sh de la
  // sesión, para pintar las dos cosas juntas en una sola pasada.
  property bool _waitingForTrashInfo: false
  property var _pendingEntries: []

  // TrashState.trashInfo es COMPARTIDA entre el panel activo y todos los
  // paneles de fondo -- antes cada panel tenía su propia copia, y al
  // pasar de fondo a activo (con solo pasar el ratón por encima, ver
  // HoverHandler más abajo) la copia del panel activo empezaba vacía
  // otra vez y tardaba un instante en recargar, aunque el panel de fondo
  // ya la tuviera lista justo al lado -- ESE era el parpadeo real en la
  // transición (reportado por josema), no el primer pintado en sí. Con
  // una sola copia compartida, quien llegue primero (activo o cualquier
  // panel de fondo) la deja lista para todos los demás.
  ProcessRunner {
    id: bgTrashInfoProc
    onFinished: function (result) {
      var fields = String(result.stdout || "").split("\u0000")
      if (fields.length > 0 && fields[fields.length - 1] === "") fields.pop()
      var info = {}
      for (var i = 0; i + 3 < fields.length; i += 4) {
        info[fields[i]] = { origPath: fields[i + 1], epoch: Number(fields[i + 2] || 0), trashRoot: fields[i + 3] }
      }
      TrashState.trashInfo = info
      if (bgPanel._waitingForTrashInfo) {
        bgPanel._waitingForTrashInfo = false
        bgPanel._applyEntries(bgPanel._pendingEntries)
      }
    }
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
    visible: bgPanel.pathError !== ""
    anchors.top: bgHeaderSep.bottom
    anchors.topMargin: Style.spacing.sm
    width: parent.width
    text: bgPanel.pathError
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
    model: bgPanel.entries
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
          hostDragDropOps.handleFilesDropped(drop, hostRoot.joinPath(bgPanel.modelData.path, modelData.name))
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

        Component.onCompleted: if (isVid) hostVideoThumbs.requestVideoThumb(modelData, bgPanel.modelData.path)

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
          thumbSource: hostRoot.isImage(modelData) ? Util.fileUrl(hostRoot.joinPath(bgPanel.modelData.path, modelData.name))
            : (parent.vidThumb ? Util.fileUrl(parent.vidThumb) : "")
          metaText: hostFileMeta.metaFor(modelData, bgPanel.modelData.path)
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
            hostTabOps.navigateTabTo(bgPanel.index, hostRoot.joinPath(bgPanel.modelData.path, modelData.name))
          } else {
            hostRoot.openWithDefault(hostRoot.joinPath(bgPanel.modelData.path, modelData.name))
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
          data["text/uri-list"] = Util.fileUrl(hostRoot.joinPath(bgPanel.modelData.path, modelData.name))
          return data
        }
      }
    }
  }

  EmptyState {
    visible: bgPanel.pathError === "" && bgPanel.entries.length === 0
    centerOn: bgList
    message: bgPanel.modelData.path === hostRoot.trashDir ? "Trash is empty" : "Nothing here yet"
  }

  Text {
    id: bgStatusText
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text: bgPanel.entries.length + (bgPanel.entries.length === 1 ? " item" : " items")
    font.pixelSize: Style.font.subtitle
    font.family: Style.font.family
    color: Color.menu.text
    opacity: 0.55
  }
}

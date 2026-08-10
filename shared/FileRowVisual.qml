import QtQuick
import qs.Commons
import qs.Ui

// Contenido visual de una fila de fichero/carpeta (icono/miniatura +
// nombre + subtítulo) -- duodécimo componente extraído de Omafiles.qml,
// y el primero compartido de verdad entre el panel activo y los de
// fondo. Antes eran dos bloques casi idénticos (rowContent/thumbSlot/
// nameCol y bgRowContent/bgThumbSlot/bgNameCol) que se habían ido
// desincronizando varias veces esta sesión (el bug del icono sin
// alinear con el nombre, el de la altura de fila con 1px de más...) --
// un solo componente para los dos elimina esa clase de bug de raíz en
// vez de solo relocalizarla.
//
// Deliberadamente NO incluye el campo de renombrar en línea (solo lo
// tiene el panel activo) ni el MouseArea (cada panel lo necesita
// distinto: el activo con selección/menú contextual/atajos, el de
// fondo solo doble-clic + arrastrar) -- ambos siguen viviendo en el
// delegado de cada panel, anclados con el mismo ancho de icono conocido
// (Style.spacing.controlHeight) en vez de necesitar ver el "thumbSlot"
// interno de aquí.
Item {
  id: root

  property string name: ""
  property bool isDir: false
  property bool isBroken: false
  // Equivalente a "rowSurface.current" en el panel activo -- el panel
  // de fondo nunca lo pone a true (ahí no existe selección de fila).
  property bool highlighted: false
  // Nombre en gris (recorte pendiente) -- solo aplica en el panel activo.
  property bool dimmed: false
  // Solo se usa cuando !isDir && !isBroken (root.iconFor(modelData) ya
  // resuelto por quien llama).
  property string fileIconGlyph: ""
  // Miniatura ya resuelta (imagen real o miniatura de vídeo en caché) --
  // "" si no aplica, mismo ternario que antes pero calculado por quien
  // llama (conoce basePath/root.currentPath, este componente no).
  property url thumbSource: ""
  property string metaText: ""
  // Valor exacto para el tooltip del subtítulo cuando el contador está
  // abreviado (12.3k -> "12,347 items"); "" = sin tooltip (Fase 23).
  property string metaTooltip: ""
  // El campo de renombrar del panel activo ocupa este mismo hueco --
  // oculta el nombre/subtítulo pero deja el icono visible, igual que
  // hacía "nameCol.visible: root.renamingIndex !== index" antes.
  property bool showNameText: true

  implicitHeight: Math.max(thumbSlot.height, nameCol.implicitHeight)

  Item {
    id: thumbSlot
    anchors.left: parent.left
    // Alineado con el nombre (nameText), no con el bloque de dos
    // líneas completo -- ver la nota larga que ya existía junto a esta
    // misma fórmula antes de extraerla aquí: "anchors.verticalCenter:
    // nameText.verticalCenter" no daba el resultado esperado en este
    // fichero por algún motivo nunca identificado del todo; "y"
    // explícito a partir de nameCol.y sí, y está verificado con overlay
    // de depuración.
    y: nameCol.y + (nameText.height - height) / 2
    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight

    Image {
      id: thumbImage
      anchors.fill: parent
      visible: status === Image.Ready
      source: root.thumbSource
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: 32
      sourceSize.height: 32
    }

    OpticalGlyph {
      anchors.fill: parent
      visible: root.isDir && !root.isBroken
      text: "󰉋"
      fontFamily: Style.font.family
      fontSize: Style.font.iconLarge
      color: root.highlighted ? Color.menu.selectedText : Color.menu.text
    }

    // Antes se ocultaba con "!hasThumb", que decide por EXTENSIÓN -- una
    // imagen real pero lenta de cargar (o con contenido corrupto,
    // status nunca llega a Ready) tenía hasThumb=true sin que la Image
    // de arriba se hiciera visible nunca, así que la fila se quedaba
    // sin icono ninguno. Se basa en el estado real de carga de la
    // propia Image.
    OpticalGlyph {
      anchors.fill: parent
      visible: !root.isDir && !thumbImage.visible && !root.isBroken
      text: root.fileIconGlyph
      fontFamily: Style.font.family
      fontSize: Style.font.iconLarge
      color: root.highlighted ? Color.menu.selectedText : Color.menu.text
    }

    // Enlace simbólico roto (md-link_variant_off, verificado contra el
    // cmap real de la fuente) -- antes se veía como un fichero normal
    // de 0 bytes fechado en 1970, sin ningún indicio de que el destino
    // ya no existe.
    OpticalGlyph {
      anchors.fill: parent
      visible: root.isBroken
      text: "\u{F033A}"
      fontFamily: Style.font.family
      fontSize: Style.font.iconLarge
      color: Color.urgent
    }
  }

  // Fila de dos líneas (nombre + tamaño/fecha relativa) -- mismo patrón
  // que el ejemplo real de fila compuesta de Omarchy (icono + Column de
  // título/subtítulo).
  Column {
    id: nameCol
    visible: root.showNameText
    anchors.left: thumbSlot.right
    anchors.leftMargin: Style.spacing.rowGap
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    Text {
      id: nameText
      width: parent.width
      text: root.name + (root.isDir ? "/" : "")
      font.pixelSize: Style.font.title
      font.family: Style.font.family
      font.weight: Font.Medium
      color: root.isBroken ? Color.urgent
        : root.dimmed ? Qt.darker(Color.menu.text, 1.6)
        : (root.highlighted ? Color.menu.selectedText : Color.menu.text)
      elide: Text.ElideRight
    }

    Text {
      id: metaTextItem
      visible: root.metaText.length > 0
      width: parent.width
      text: root.metaText
      font.pixelSize: Style.font.bodySmall
      font.family: Style.font.family
      color: root.highlighted ? Color.menu.selectedText : Color.menu.text
      opacity: 0.6
      elide: Text.ElideRight

      // Tooltip con el valor exacto cuando el contador se muestra abreviado
      // (12.3k items -> 12,347 items). Solo si metaTooltip viene informado.
      HoverHandler { id: metaHover; enabled: root.metaTooltip.length > 0 }
      PanelToolTip {
        visible: metaHover.hovered && root.metaTooltip.length > 0
        text: root.metaTooltip
      }
    }
  }
}

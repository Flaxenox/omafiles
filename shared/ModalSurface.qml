import QtQuick
import qs.Commons
import qs.Ui

// Superficie modal compartida de Omafiles: scrim oscurecido + tarjeta
// centrada animada. Unifica el fondo, la animación de apertura/cierre, el
// radio, el borde, el color y el padding de TODOS los diálogos centrados de
// la app, para que se perciban como una única familia (Sprint Visual 2 --
// hallazgos A-01/A-03/B-02 de VISUAL_AUDIT_V1). Antes cada diálogo repetía
// casi idéntico este envoltorio (backdrop MouseArea + card BorderSurface +
// Behaviors + Column con insets), con pequeñas divergencias (spacing xs/sm,
// altura fija con hueco muerto, y NINGÚN scrim visible salvo en ConfirmDialog).
//
// Cada diálogo conserva su propia API (open + señales + contenido) y solo
// delega aquí el aspecto visual: instancia ModalSurface, fija su maxWidth y
// mete su contenido dentro; el scrim, la animación y el padding ya no se
// repiten en cada fichero.
//
// El scrim usa EXACTAMENTE el mismo valor que qs.Ui/ConfirmDialog
// (Util.alpha(Color.background, 0.7)) -- que no se puede tocar (qs.Ui
// compartido) -- para que el fondo oscurecido sea idéntico venga el diálogo
// de donde venga.
Item {
  id: root
  anchors.fill: parent

  property bool open: false
  // Ancho máximo de la tarjeta (cada diálogo elige el suyo según su
  // contenido). El ALTO sale siempre del contenido, acotado a la ventana.
  property real maxWidth: Style.space(360)
  // Algunos diálogos bloquean el cierre por clic-fuera en ciertos estados
  // (p.ej. ConnectServer mientras conecta). false lo desactiva.
  property bool dismissable: true
  // Contenido de la tarjeta: se coloca como hijos de la Column interna, con
  // el mismo espaciado para todos.
  default property alias content: contentColumn.data

  // Clic sobre el scrim (fuera de la tarjeta).
  signal dismissed()

  // Única duración/curva de la familia modal (Fase 22): 120 ms OutCubic,
  // sin overshoot, entrada y salida iguales, scrim y tarjeta sincronizados.
  readonly property int transitionDuration: 120

  Rectangle {
    id: scrim
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.7)
    opacity: root.open ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic } }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      enabled: root.open
      onClicked: if (root.dismissable) root.dismissed()
    }
  }

  BorderSurface {
    id: card
    visible: root.open || opacity > 0
    width: Math.min(parent.width - Style.space(32), root.maxWidth)
    // Tamaño por contenido (implicitHeight, intrínseco -> no crea ciclo con
    // el height real de la Column), acotado a la ventana. Así ningún diálogo
    // reserva hueco muerto de más (antes ShortcutsHelp fijaba 460).
    height: Math.min(parent.height - Style.space(32),
                     contentColumn.implicitHeight + contentTopInset + contentBottomInset)
    anchors.centerIn: parent
    opacity: root.open ? 1 : 0
    scale: root.open ? 1 : 0.98
    Behavior on opacity { NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic } }
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.panelPadding

    // Come clics dentro de la tarjeta para que no cierren el diálogo.
    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: contentColumn
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      spacing: Style.spacing.sm
    }
  }
}

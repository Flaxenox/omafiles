import QtQuick
import qs.Commons
import qs.Ui

// Diálogo de permisos (chmod). Quinto componente extraído de
// Omafiles.qml. root.chmodBitSet()/toggleChmodBit() leían y escribían
// root.chmodMode directamente -- como un componente aparte no ve ese
// "root" (es el suyo propio), el cálculo de qué casilla está marcada se
// reproduce aquí en local a partir de la propiedad `mode` recibida
// (misma lógica exacta que chmodDigit()/chmodBitSet(), solo
// parametrizada), y cambiar una casilla se pide hacia fuera con una
// señal en vez de escribir el modo directamente -- Omafiles.qml sigue
// siendo el único dueño real de root.chmodMode.
Item {
  id: root

  property bool open: false
  property var names: []
  property bool mixed: false
  property string mode: ""
  property bool hasDir: false
  property bool recursive: false

  signal closeRequested()
  signal bitToggled(int ownerIdx, int bit)
  signal recursiveToggled()
  signal applyRequested(string mode)

  function digitAt(ownerIdx) {
    var m = String(root.mode || "0")
    while (m.length < 3) m = "0" + m
    return parseInt(m.substring(m.length - 3).charAt(ownerIdx) || "0", 10)
  }

  function bitSet(ownerIdx, bit) {
    return (root.digitAt(ownerIdx) & bit) !== 0
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    visible: root.open
    z: 15
    onClicked: root.closeRequested()
  }

  BorderSurface {
    id: chmodCard
    visible: root.open || opacity > 0
    width: Math.min(parent.width - 80, 320)
    height: chmodColumn.implicitHeight + contentTopInset + contentBottomInset
    anchors.centerIn: parent
    // Fase 22: entrada discreta del diálogo (opacity 0->1, scale
    // 0.98->1.0, 120 ms, sin overshoot). No bloquea el clic.
    opacity: root.open ? 1 : 0
    scale: root.open ? 1 : 0.98
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.sm
    z: 20

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: chmodColumn
      anchors.fill: parent
      anchors.topMargin: chmodCard.contentTopInset
      anchors.rightMargin: chmodCard.contentRightInset
      anchors.bottomMargin: chmodCard.contentBottomInset
      anchors.leftMargin: chmodCard.contentLeftInset
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        text: root.names.length === 1
          ? "Permissions for \"" + root.names[0] + "\""
          : "Permissions for " + root.names.length + " items"
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: true
        color: Color.menu.text
        elide: Text.ElideMiddle
      }

      Text {
        width: parent.width
        visible: root.mixed
        text: "Mixed permissions — choose a mode to apply to all"
        font.pixelSize: Style.font.bodySmall
        font.family: Style.font.family
        // Qt.darker se usa en este fichero para texto DESHABILITADO
        // (botones/filas sin acción posible) -- este texto no está
        // deshabilitado, es solo un aviso secundario, así que le
        // toca la misma convención de opacity:0.6 que el resto del
        // texto secundario del fichero.
        color: Color.menu.text
        opacity: 0.6
        wrapMode: Text.WordWrap
      }

      PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

      // Cabecera de columnas -- hueco a la izquierda del ancho de la
      // etiqueta de fila (Owner/Group/Other), luego Read/Write/Exec.
      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Item { width: 60; height: 1 }

        Repeater {
          model: ["Read", "Write", "Exec"]

          Text {
            required property string modelData
            width: Style.spacing.controlHeight
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            font.pixelSize: Style.font.caption
            font.family: Style.font.family
            color: Color.menu.text
            opacity: 0.6
          }
        }
      }

      // Owner (tú) / Group / Other -- cada fila con sus 3 casillas rwx,
      // en vez de escribir el octal a mano. root.mode sigue siendo la
      // fuente de verdad (un string de 3 dígitos, dueño real en
      // Omafiles.qml); cada casilla consulta un bit suyo directamente y
      // pide cambiarlo con bitToggled().
      Repeater {
        model: [
          { label: "Owner", idx: 0 },
          { label: "Group", idx: 1 },
          { label: "Other", idx: 2 }
        ]

        Row {
          id: chmodRow
          required property var modelData
          width: chmodColumn.width
          spacing: Style.spacing.sm

          Text {
            width: 60
            anchors.verticalCenter: parent.verticalCenter
            text: chmodRow.modelData.label
            font.pixelSize: Style.font.subtitle
            font.family: Style.font.family
            color: Color.menu.text
          }

          Repeater {
            model: [4, 2, 1]

            // CursorSurface en vez de un Rectangle+MouseArea a mano --
            // mismo componente que usa cualquier otra fila/pestaña
            // clicable de la app, así que la casilla tiene el mismo
            // hover y el mismo tratamiento de "seleccionado" (current)
            // que el resto, en vez de un estilo inventado aparte.
            CursorSurface {
              id: chmodCell
              required property int modelData
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              anchors.verticalCenter: parent.verticalCenter
              foreground: Color.menu.text
              accent: Color.accent
              bordered: true
              hasCursor: chmodCellMouse.containsMouse
              current: root.bitSet(chmodRow.modelData.idx, modelData)

              MouseArea {
                id: chmodCellMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.bitToggled(chmodRow.modelData.idx, chmodCell.modelData)
              }
            }
          }
        }
      }

      PanelSeparator { foreground: Color.menu.text; strength: 0.15 }

      Text {
        width: parent.width
        text: "Octal: " + root.mode
        font.pixelSize: Style.font.subtitle
        font.family: Style.font.family
        color: Color.menu.text
        opacity: 0.6
      }

      Toggle {
        width: parent.width
        visible: root.hasDir
        label: "Apply to subfolders"
        description: "chmod -R -- also changes everything inside"
        checked: root.recursive
        foreground: Color.menu.text
        accent: Color.accent
        onClicked: root.recursiveToggled()
      }

      Button {
        text: "Apply"
        bordered: true
        Accessible.role: Accessible.Button
        Accessible.name: text
        onClicked: root.applyRequested(root.mode)
      }
    }
  }
}

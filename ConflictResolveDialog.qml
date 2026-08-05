import QtQuick
import qs.Commons
import qs.Ui

// Diálogo "ya existe, ¿sobrescribir/omitir/cancelar?". Séptimo
// componente extraído de Omafiles.qml -- a diferencia de los
// anteriores, este no es solo una reubicación: "Conflicto al pegar" y
// "Conflicto al soltar" eran dos bloques de ~55 líneas IDÉNTICOS salvo
// qué función llamaban, así que se unifican en un solo componente
// reutilizable con señales genéricas (overwriteRequested/skipRequested/
// cancelRequested) en vez de mantener la duplicación en dos ficheros.
Item {
  id: root

  property bool open: false
  property var names: []

  signal overwriteRequested()
  signal skipRequested()
  signal cancelRequested()

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    visible: root.open
    z: 15
    onClicked: root.cancelRequested()
  }

  BorderSurface {
    id: conflictCard
    visible: root.open
    width: Math.min(parent.width - 80, 360)
    height: conflictColumn.implicitHeight + contentTopInset + contentBottomInset
    anchors.centerIn: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.sm
    z: 20

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: conflictColumn
      anchors.fill: parent
      anchors.topMargin: conflictCard.contentTopInset
      anchors.rightMargin: conflictCard.contentRightInset
      anchors.bottomMargin: conflictCard.contentBottomInset
      anchors.leftMargin: conflictCard.contentLeftInset
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        text: root.names.length === 1
          ? "\"" + root.names[0] + "\" already exists here."
          : root.names.length + " items already exist here."
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: true
        color: Color.menu.text
        wrapMode: Text.Wrap
      }

      Column {
        width: parent.width
        spacing: Style.spacing.xs

        Button { width: parent.width; leftAlign: true; bordered: true; text: "Overwrite all"; Accessible.role: Accessible.Button; Accessible.name: text; onClicked: root.overwriteRequested() }
        Button { width: parent.width; leftAlign: true; bordered: true; text: "Skip existing"; Accessible.role: Accessible.Button; Accessible.name: text; onClicked: root.skipRequested() }
        Button { width: parent.width; leftAlign: true; bordered: true; text: "Cancel"; Accessible.role: Accessible.Button; Accessible.name: text; onClicked: root.cancelRequested() }
      }
    }
  }
}

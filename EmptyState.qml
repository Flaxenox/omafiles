import QtQuick
import qs.Commons

// Estado vacío ("Nothing here yet" / "Trash is empty" / "No results
// for...") -- trece componente extraído de Omafiles.qml, y el segundo
// (después de FileRowVisual.qml) que unifica panel activo y de fondo
// en vez de solo relocalizar código.
//
// OJO al tocar esto: `centerOn` es el motivo real de un bug ya cazado
// una vez esta misma sesión -- el icono/texto "saltaba" de sitio al
// pasar el ratón entre paneles porque el panel activo se centraba
// sobre un contenedor que incluía la cabecera (navRow/breadcrumb) y el
// de fondo sobre uno que no. Aquí solo hay un componente, así que ya
// no puede volver a desincronizarse -- pero quien lo use SIEMPRE debe
// pasar la ListView real del panel (list/bgList), nunca un contenedor
// más amplio, o el bug vuelve.
Column {
  id: root

  property Item centerOn: null
  property string message: ""

  anchors.centerIn: root.centerOn
  width: root.centerOn ? root.centerOn.width : 0
  spacing: Style.spacing.sm

  Text {
    text: "\u{F0209}"
    color: Color.menu.selectedText
    opacity: 0.8
    font.family: Style.font.family
    font.pixelSize: Style.font.displayLarge
    horizontalAlignment: Text.AlignHCenter
    width: parent.width
  }

  Text {
    text: root.message
    color: Color.menu.text
    opacity: 0.7
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    horizontalAlignment: Text.AlignHCenter
    width: parent.width
  }
}

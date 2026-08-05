pragma Singleton
import QtQuick

// Estado de selección de filas (individual + lazo de arrastre) --
// primer singleton de la capa state/, piloto para validar el patrón
// pragma Singleton dentro del propio plugin (mismo mecanismo que ya usan
// Util/Color/Style de qs.Commons) antes de mover más estado aquí. La
// lógica que lo manipula sigue en logic/SelectionOps.qml -- esto es SOLO
// el estado, sin funciones.
QtObject {
  property int selectedIndex: -1
  property var selectedIndices: []
  property int anchorIndex: -1

  // ---------- Lazo de selección (arrastrar sobre hueco vacío) ----------
  // Coordenadas en el espacio de contenido de la ListView (independientes
  // del scroll), no del viewport -- así el rectángulo sigue correcto si
  // el usuario arrastra hacia dentro de la zona con scroll.
  property bool marqueeActive: false
  property real marqueeStartX: 0
  property real marqueeStartY: 0
  property real marqueeCurrentX: 0
  property real marqueeCurrentY: 0
  property bool marqueeAdditive: false
  property var marqueeBaseSelection: []
  // Posición del cursor relativa al viewport de `list` (0 = arriba del
  // todo, list.height = abajo del todo) -- para el auto-scroll cuando el
  // lazo llega a un borde con más filas de las que caben en pantalla.
  property real marqueeViewportY: 0
}

import QtQuick
import QtQuick.Controls
import "../../core"

// Frontend Qt6 standalone -- primer arranque (Fase 4, josema: prueba de
// independencia del núcleo, no una app completa). Instancia el MISMO
// core/OmafilesContent.qml que usa el frontend Quickshell
// (integrations/quickshell/HostBridge.qml lo hace bajo un
// FloatingWindow; aquí va bajo un ApplicationWindow normal de Qt6) --
// ninguna diferencia de comportamiento pretendida más allá del tipo de
// ventana anfitriona.
ApplicationWindow {
  id: window
  visible: true
  width: 1400
  height: 900
  title: "Omafiles"

  OmafilesContent {
    id: content
    anchors.fill: parent
  }
}

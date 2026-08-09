import QtQuick
import QtQuick.Controls
import Omafiles.Backend as Backend
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

  // El core solo navega cuando el host llama a open() (en Quickshell lo
  // hace HostBridge al mostrar la ventana). Fase 4 no lo llamaba, por eso
  // el standalone salia sin listar nada. HOME sale del Env real (Fase 5,
  // backend/Env.cpp), no ya de un context property. Con ProcessRunner
  // respaldado por QProcess real, esto lista la carpeta de verdad.
  Component.onCompleted: {
    content.open(Backend.Env.get("HOME"))
  }
}

import QtQuick
import QtQuick.Controls
import qs.Commons
import Omafiles.Backend as Backend
import "../../core"
import ".."

// Adaptador de host Qt6 standalone (Fase 4 → Fase 18, josema). Es el
// equivalente de integrations/quickshell/HostBridge.qml para el frontend
// Qt6: instancia el MISMO core/OmafilesContent.qml pero sobre un
// ApplicationWindow en vez de un FloatingWindow. Cumple el mismo contrato de
// host (ver integrations/HostAdapter.qml):
//   · show()/hide()/close()  -- built-in de Window/ApplicationWindow.
//   · cierre externo         -- onClosing (botón de cerrar del WM / Alt+F4).
//   · geometría (tamaño)     -- vía HostAdapter, misma persistencia que
//                               Quickshell (~/.local/state/omafiles/window.json).
// El bootstrap (crear el engine, cargar este fichero) lo hace main.cpp; por
// eso, a diferencia del lado Quickshell, aquí la ventana ES la raíz (main.cpp
// espera un QQuickWindow) y no hay un Omafiles.qml intermedio ni objeto
// `shell` del host.
ApplicationWindow {
  id: window
  visible: true
  // Tamaño por defecto de la primera apertura; HostAdapter lo sobrescribe si
  // hay un window.json guardado (ver onSizeRestored).
  width: 1400
  height: 900
  minimumWidth: 560
  minimumHeight: 380
  title: "Omafiles"
  color: Color.menu.background

  HostAdapter {
    id: adapter
    window: window
  }

  Connections {
    target: adapter
    function onSizeRestored(w, h) {
      window.width = w
      window.height = h
    }
  }

  // Cierre externo (botón de cerrar del gestor de ventanas): equivale al
  // closedExternally() del lado Quickshell. En un standalone de una sola
  // ventana, cerrar = terminar la app (quitOnLastWindowClosed), así que no
  // hay que hacer nada más que dejar constancia de que ya no está abierto.
  onClosing: content.opened = false

  OmafilesContent {
    id: content
    anchors.fill: parent
    // Esc / cerrar la última pestaña: sin objeto `shell` que avisar (no hay
    // host que oculte el plugin), así que se cierra la ventana directamente.
    onCloseRequested: window.close()
  }

  // Instancia única (Fase 25): una segunda invocación `omafiles [ruta]` no abre
  // otra ventana -- main.cpp entrega el payload por el socket local y aquí se
  // navega/selecciona (content.open) y se trae la ventana al frente. Mismo
  // content.open() que usa la apertura inicial y que usaba el summon del plugin.
  Connections {
    target: SingleInstance
    function onReceived(payload) {
      content.open(payload)
      window.show()
      window.raise()
      window.requestActivate()
    }
  }

  Component.onCompleted: {
    adapter.restore()
    // Payload inicial de la línea de comandos (main.cpp). Vacío = restaura la
    // sesión anterior (carpeta/pestañas), igual que el arranque del plugin.
    content.open(typeof omafilesInitialPayload !== "undefined" ? omafilesInitialPayload : "")
  }
}

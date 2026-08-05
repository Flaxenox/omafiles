import QtQuick
import qs.Commons
import "core"
import "integrations/quickshell"

// Omafiles -- explorador de archivos para Omarchy.
// Bootstrap del frontend Quickshell (Fase 3, josema: separar el
// composition root del frontend). Todo el árbol visual y el wiring
// principal vive en core/OmafilesContent.qml, instanciado aquí dentro de
// un HostBridge (integrations/quickshell/) -- este fichero se limita a:
// crear la ventana, crear el contenido, y traducir entre el contrato del
// host Quickshell (shell/open/close/opened, ver más abajo) y la API de
// OmafilesContent (open/close/opened/closeRequested), sin lógica de
// negocio propia. El siguiente paso natural para un frontend Qt6
// standalone sería un integrations/standalone/Main.qml que instancie el
// mismo OmafilesContent dentro de un ApplicationWindow, sin tocar
// core/logic/state/panels/dialogs/shared/services.
Item {
  id: root

  // Inyectado por el host (shell.qml) via duck-typing al cargar el
  // plugin -- ver integrations/quickshell/HostBridge.qml para el detalle
  // del protocolo (summon/hide/toggle).
  property var shell: null

  // Leído por el host (isPluginOpen(): "loader.item.opened !== undefined")
  // -- alias al `opened` real, que vive en OmafilesContent (content.open()/
  // close() lo mantienen).
  property alias opened: content.opened

  // Puesto mientras close() está en marcha, para que HostBridge no
  // interprete el cierre que NOSOTROS mismos iniciamos como un cierre
  // EXTERNO (botón de cerrar del gestor de ventanas) -- ver
  // HostBridge.suppressExternalClose.
  property bool closingFromHost: false

  // Host-initiated open/close (`shell toggle`/`shell summon`/`shell
  // hide`), llamados por nombre directo sobre esta instancia (contrato
  // del plugin, ver shell.qml). show()/close() del lado de la ventana
  // aquí; el resto de la lógica (parsear payload, cargar sesión/
  // bookmarks, refrescar mounts...) vive en content.open()/content.close().
  function open(payload) {
    hostBridge.show()
    content.open(payload)
  }

  function close() {
    root.closingFromHost = true
    content.close()
    hostBridge.close()
    root.closingFromHost = false
  }

  HostBridge {
    id: hostBridge
    shell: root.shell
    suppressExternalClose: root.closingFromHost
    onClosedExternally: {
      content.opened = false
      hostBridge.hide()
    }

    // Los Window de QtQuick nacen visible:true por defecto -- sin esto se
    // abriría solo con keepLoaded, antes de que open() lo pida.
    visible: false
    title: "Omafiles"
    color: Color.menu.background
    implicitWidth: 900
    implicitHeight: 620
    minimumSize: Qt.size(560, 380)

    OmafilesContent {
      id: content
      anchors.fill: parent
      // content.requestClose() (Esc, cerrar la última pestaña...) emite
      // esto en vez de hablar con el host directamente -- aquí se decide
      // si eso significa avisar al host (que llamará de vuelta a
      // root.close(), ver HostBridge.hide()) o cerrar directo si no hay
      // host (shell no asignado, ej. en pruebas fuera de Quickshell).
      onCloseRequested: {
        if (root.shell && typeof root.shell.hide === "function") hostBridge.hide()
        else content.close()
      }
    }
  }
}

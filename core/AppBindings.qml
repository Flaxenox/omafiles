import QtQuick
import "../services"

// AppBindings -- wiring de ciclo de vida y temporizadores de Omafiles (Fase
// 11.C, josema: completar el desacoplamiento del frontend). Reúne las
// reacciones/temporizadores que no son ni UI (MainLayout/DialogLayer) ni
// fachada operativa (CommandFacade): el autoregistro como gestor de archivos
// al cargar, el sondeo periódico de discos/red y el debounce de la tecla `g`
// (gg -> ir arriba). Recibe solo lo que usa: `root` (pluginDir/opened/
// gPending) y `mountOps`. Expone `gTimer` como alias porque KeyboardShortcuts
// (vía ActiveFileList) lo reinicia.
Item {
  id: appBindings

  property Item root
  property var mountOps

  property alias gTimer: gTimer

  // Autoregistro como gestor de archivos del sistema (MimeType inode/
  // directory + org.freedesktop.FileManager1) -- se lanza una vez al cargar
  // el plugin. El script es idempotente (scripts/install-integrations.sh),
  // así que llamarlo en cada arranque del shell es barato y seguro.
  Component.onCompleted: {
    Detached.run([root.pluginDir + "/scripts/install-integrations.sh"])
  }

  // Discos/red no tienen un evento fácil de vigilar aquí (habría que
  // suscribirse a señales D-Bus de UDisks2/GVfs) -- un polling modesto es la
  // opción honesta dado el alcance. "running: root.opened" para que no siga
  // en marcha de fondo con la ventana cerrada.
  Timer {
    interval: 7000
    repeat: true
    running: root.opened
    onTriggered: { mountOps.refreshMounts(); mountOps.refreshNetworkMounts() }
  }

  // Debounce de la tecla `g` (pulsar `g` dos veces seguidas = ir arriba del
  // todo, estilo vim). onTriggered limpia el estado si no llegó la segunda.
  Timer {
    id: gTimer
    interval: 600
    onTriggered: root.gPending = false
  }
}

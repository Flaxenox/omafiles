import "../state"
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
    // Bajo el arnés de validación (omafiles --selfcheck, Fase 12) NO se
    // autoregistra como gestor de archivos: el selfcheck instancia el core
    // muchas veces y no debe tener efectos secundarios en el sistema. En un
    // arranque normal OMAFILES_SELFCHECK no existe y el comportamiento es el
    // de siempre.
    if (Env.get("OMAFILES_SELFCHECK") === "1") return
    Detached.run([Paths.resourceDir + "/scripts/install-integrations.sh"])
  }

  // Dispositivos de bloque (USB/ISO/discos): reactivos vía UDisks2 (Fase 20).
  // El watcher nativo (backend/UDisksWatcher, suscripción D-Bus) emite
  // devicesChanged() coalescido ante cualquier conexión/expulsión/montaje/
  // cambio de label, y aquí se responde volviendo a listar -- sin polling. La
  // carga inicial la hace OmafilesContent.open(); `enabled: root.opened` evita
  // relistar con la ventana cerrada (al reabrir, open() pone al día).
  //
  // Montajes de RED (GVfs) NO los cubre UDisks2: se refrescan solo por eventos
  // internos (conectar/desconectar servidor en Omafiles, navegar a red) y al
  // abrir la ventana -- sin polling periódico. LIMITACIÓN CONOCIDA: un montaje
  // de red creado desde OTRA app (nautilus...) no aparece hasta el siguiente
  // evento interno o reapertura. Mejora futura: un watcher específico de GVfs
  // (señales D-Bus de org.gtk.vfs), nunca polling.
  Connections {
    target: UDisksWatcher
    enabled: root.opened
    function onDevicesChanged() { mountOps.refreshMounts() }
  }

  // Debounce de la tecla `g` (pulsar `g` dos veces seguidas = ir arriba del
  // todo, estilo vim). onTriggered limpia el estado si no llegó la segunda.
  Timer {
    id: gTimer
    interval: 600
    onTriggered: root.gPending = false
  }
}

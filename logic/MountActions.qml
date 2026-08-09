import QtQuick
import "../state"
import "../services"
import "../Utils.js" as Utils

// Montar/expulsar unidades (udisksctl) + conectar/desconectar unidades de
// red (gio mount) -- duodécimo componente extraído de Omafiles.qml, y el
// primero en mover Process + las funciones que los orquestan juntos desde
// fuera de la zona de "Panel activo" (mismo criterio que ConflictActions:
// código relacionado que vivía disperso, aquí ya estaba físicamente
// contiguo en el fichero salvo por las funciones, ahora se queda junto de
// verdad). Todas las llamadas externas usaban `root.xxx(...)`, así que se
// actualizaron a `mountActions.xxx(...)` en sus sitios de llamada -- no
// quedan wrappers sueltos en root.
Item {
  property Item root: null
  property Item tabOps: null

  function refreshMounts() {
    mountsProc.start([root.pluginDir + "/list-mounts.sh"])
  }

  function refreshNetworkMounts() {
    networkMountsProc.start([root.pluginDir + "/list-network-mounts.sh"])
  }

  function disconnectNetworkMount(mount) {
    if (networkUnmountProc.busy) {
      Notifier.notify("Still disconnecting a network location — try again in a moment")
      return
    }
    networkUnmountProc.wasInside = NavState.currentPath === mount.path || NavState.currentPath.indexOf(mount.path + "/") === 0
    networkUnmountProc.tabIndex = TabsState.activeTabIndex
    networkUnmountProc.start(["gio", "mount", "-u", mount.path])
  }

  function startConnectToServer() {
    DialogsState.connectServerUri = ""
    DialogsState.connectServerError = ""
    DialogsState.connectServerOpen = true
  }

  function cancelConnectToServer() {
    DialogsState.connectServerOpen = false
  }

  // "setsid" + matar el grupo entero al cancelar, mismo motivo que
  // runAction()/cancelAction(): gio mount puede quedarse esperando
  // credenciales que nunca van a llegar (esta app no tiene un diálogo de
  // usuario/contraseña -- ver comentario largo en connectServerOpen más
  // abajo en el fichero, junto al diálogo), y sin esto Cancelar no
  // conseguiría matar el proceso de verdad.
  function commitConnectToServer() {
    var uri = DialogsState.connectServerUri.trim()
    if (!uri) return
    DialogsState.connectServerError = ""
    DialogsState.networkConnecting = true
    networkMountProc.start(["gio", "mount", "--", uri], true)
  }

  function cancelNetworkConnect() {
    networkMountProc.cancel()
    DialogsState.networkConnecting = false
  }

  function ejectMount(mount) {
    // Sin esta guardia, hacer doble clic en "Expulsar" reasignaba
    // ejectProc.command a mitad de la primera llamada, reiniciándola --
    // mismo problema que runAction() ya evitaba para las acciones de
    // fichero, pero este proceso no lo tenía.
    // Aviso explícito en vez de un return mudo -- sin esto, el segundo
    // clic no hacía nada visible y parecía que la app había ignorado la
    // pulsación, igual que le pasaba antes a runAction() (ver ahí).
    if (ejectProc.busy) {
      Notifier.notify("Still ejecting a drive — try again in a moment")
      return
    }
    var wasInside = NavState.currentPath === mount.path || NavState.currentPath.indexOf(mount.path + "/") === 0
    ejectProc.mountPath = mount.path
    ejectProc.wasInside = wasInside
    ejectProc.tabIndex = TabsState.activeTabIndex
    ejectProc.device = mount.device
    ejectProc.start(["udisksctl", "unmount", "-b", mount.device])
  }

  // udisksctl imprime "Mounted /dev/sdX at /run/media/user/Label." -- se
  // extrae la ruta de ahí en vez de relanzar list-mounts.sh y adivinar cuál
  // es la unidad recién montada.
  function mountDevice(mount) {
    if (mountProc.busy) {
      Notifier.notify("Still mounting a drive — try again in a moment")
      return
    }
    // Capturado aquí (no releído en onFinished) -- si el ratón pasa a otro
    // panel mientras el montaje tarda, el resultado debe navegar el
    // panel que lo pidió, no el que resulte estar activo cuando termine.
    mountProc.tabIndex = TabsState.activeTabIndex
    mountProc.start(["udisksctl", "mount", "-b", mount.device])
  }

  // A diferencia de isArchive() (enterArchive(), navegación de solo
  // lectura sin montar nada de verdad), un .iso se monta como un
  // dispositivo loop real -- así lo que haya dentro (un instalador, por
  // ejemplo) se puede ejecutar/copiar igual que en cualquier carpeta
  // normal, no solo mirarlo. Aparece en la barra lateral como cualquier
  // otra unidad extraíble en cuanto se monta (list-mounts.sh ya distingue
  // el icono por fstype=iso9660) y se expulsa igual que una.
  function mountIso(entry) {
    if (mountIsoProc.busy) {
      Notifier.notify("Still mounting an ISO — try again in a moment")
      return
    }
    mountIsoProc.tabIndex = TabsState.activeTabIndex
    mountIsoProc.start(["bash", root.pluginDir + "/mount-iso.sh", root.joinPath(NavState.currentPath, entry.name)])
  }

  ProcessRunner {
    id: mountsProc
    onFinished: function (result) { MountsState.mounts = Utils.parseMounts(result.stdout) }
  }

  ProcessRunner {
    id: ejectProc
    property string mountPath: ""
    property bool wasInside: false
    property int tabIndex: -1
    property string device: ""
    onFinished: function (result) {
      if (result.exitCode === 0) {
        if (ejectProc.wasInside) tabOps.navigateTabTo(ejectProc.tabIndex, root.homeDir)
        // Un .iso montado con mountIso() deja el /dev/loopN asociado al
        // fichero aunque ya esté desmontado -- sin esto, el .iso se queda
        // "en uso" (no se puede mover/borrar) y cada uno gastaría un loop
        // device para siempre hasta reiniciar.
        if (ejectProc.device.indexOf("/dev/loop") === 0) {
          Detached.run(["udisksctl", "loop-delete", "-b", ejectProc.device])
        }
        refreshMounts()
      } else {
        Notifier.notify("Could not eject: " + (result.stderr || "device busy"))
      }
    }
  }

  ProcessRunner {
    id: mountProc
    property int tabIndex: -1
    onFinished: function (result) {
      refreshMounts()
      if (result.exitCode === 0) {
        var match = result.stdout.match(/ at (\/[^\s.]+)/)
        if (match) tabOps.navigateTabTo(mountProc.tabIndex, match[1])
      } else {
        Notifier.notify("Could not mount: " + (result.stderr || "unknown error"))
      }
    }
  }

  ProcessRunner {
    id: mountIsoProc
    property int tabIndex: -1
    onFinished: function (result) {
      refreshMounts()
      if (result.exitCode === 0) {
        var match = result.stdout.match(/ at (\/[^\s.]+)/)
        if (match) tabOps.navigateTabTo(mountIsoProc.tabIndex, match[1])
      } else {
        Notifier.notify("Could not mount ISO: " + (result.stderr || "unknown error"))
      }
    }
  }

  ProcessRunner {
    id: networkMountsProc
    onFinished: function (result) { MountsState.networkMounts = Utils.parseNetworkMounts(result.stdout) }
  }

  ProcessRunner {
    id: networkUnmountProc
    property bool wasInside: false
    property int tabIndex: -1
    onFinished: function (result) {
      if (result.exitCode === 0) {
        if (networkUnmountProc.wasInside) tabOps.navigateTabTo(networkUnmountProc.tabIndex, root.homeDir)
        refreshNetworkMounts()
      } else {
        Notifier.notify("Could not disconnect: " + (result.stderr || "unknown error"))
      }
    }
  }

  // Sin -a/--anonymous ni forma de pasar contraseña: si el servidor pide
  // credenciales, gio necesita un GMountOperation interactivo que esta
  // app no implementa (sería un sub-proyecto en sí mismo, tipo el diálogo
  // "Conectar a servidor" + llavero de Nautilus). Funciona bien para SFTP
  // con clave SSH ya configurada, o cualquier servidor con credenciales
  // ya guardadas en el llavero de una conexión anterior (con Nautilus,
  // por ejemplo) -- si se queda colgado esperando una contraseña que
  // nunca llega, el usuario tiene el botón Cancelar del diálogo
  // (cancelNetworkConnect/setsid, mismo mecanismo que cancelAction()).
  ProcessRunner {
    id: networkMountProc
    onFinished: function (result) {
      DialogsState.networkConnecting = false
      if (result.exitCode === 0) {
        DialogsState.connectServerOpen = false
        // gio no imprime la ruta local igual que udisksctl -- se relista
        // y se entra al mount que no estaba antes (el que acaba de
        // aparecer) en vez de parsear la salida de "gio mount".
        networkMountsAfterConnectProc.beforePaths = MountsState.networkMounts.map(function (m) { return m.path })
        networkMountsAfterConnectProc.start([root.pluginDir + "/list-network-mounts.sh"])
      } else {
        DialogsState.connectServerError = result.stderr.trim() || "Could not connect"
      }
    }
  }

  // Segunda pasada de list-network-mounts.sh tras un connect con éxito,
  // solo para encontrar CUÁL de los mounts es el nuevo (comparando contra
  // los que ya había antes) y navegar directamente a él -- refreshNetworkMounts()
  // normal no distingue cuál acaba de aparecer.
  ProcessRunner {
    id: networkMountsAfterConnectProc
    property var beforePaths: []
    onFinished: function (result) {
      var parsed = Utils.parseNetworkMounts(result.stdout)
      MountsState.networkMounts = parsed
      var before = networkMountsAfterConnectProc.beforePaths
      var fresh = parsed.filter(function (m) { return before.indexOf(m.path) < 0 })
      if (fresh.length > 0) root.navigateTo(fresh[0].path)
    }
  }
}

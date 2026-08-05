import QtQuick
import Quickshell
import Quickshell.Io
import "../state"
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
    mountsProc.running = true
  }

  function refreshNetworkMounts() {
    networkMountsProc.running = true
  }

  function disconnectNetworkMount(mount) {
    if (networkUnmountProc.running) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Still disconnecting a network location — try again in a moment"])
      return
    }
    networkUnmountProc.wasInside = root.currentPath === mount.path || root.currentPath.indexOf(mount.path + "/") === 0
    networkUnmountProc.tabIndex = root.activeTabIndex
    networkUnmountProc.command = ["gio", "mount", "-u", mount.path]
    networkUnmountProc.running = true
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
    networkMountProc.errorText = ""
    networkMountProc.command = ["setsid", "gio", "mount", "--", uri]
    networkMountProc.running = true
  }

  function cancelNetworkConnect() {
    var pid = networkMountProc.processId
    if (pid) Quickshell.execDetached(["kill", "-TERM", "--", "-" + pid])
    networkMountProc.running = false
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
    if (ejectProc.running) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Still ejecting a drive — try again in a moment"])
      return
    }
    var wasInside = root.currentPath === mount.path || root.currentPath.indexOf(mount.path + "/") === 0
    ejectProc.command = ["udisksctl", "unmount", "-b", mount.device]
    ejectProc.mountPath = mount.path
    ejectProc.wasInside = wasInside
    ejectProc.tabIndex = root.activeTabIndex
    ejectProc.device = mount.device
    ejectProc.running = true
  }

  // udisksctl imprime "Mounted /dev/sdX at /run/media/user/Label." -- se
  // extrae la ruta de ahí en vez de relanzar list-mounts.sh y adivinar cuál
  // es la unidad recién montada.
  function mountDevice(mount) {
    if (mountProc.running) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Still mounting a drive — try again in a moment"])
      return
    }
    // Capturado aquí (no releído en onExited) -- si el ratón pasa a otro
    // panel mientras el montaje tarda, el resultado debe navegar el
    // panel que lo pidió, no el que resulte estar activo cuando termine.
    mountProc.tabIndex = root.activeTabIndex
    mountProc.command = ["udisksctl", "mount", "-b", mount.device]
    mountProc.running = true
  }

  // A diferencia de isArchive() (enterArchive(), navegación de solo
  // lectura sin montar nada de verdad), un .iso se monta como un
  // dispositivo loop real -- así lo que haya dentro (un instalador, por
  // ejemplo) se puede ejecutar/copiar igual que en cualquier carpeta
  // normal, no solo mirarlo. Aparece en la barra lateral como cualquier
  // otra unidad extraíble en cuanto se monta (list-mounts.sh ya distingue
  // el icono por fstype=iso9660) y se expulsa igual que una.
  function mountIso(entry) {
    if (mountIsoProc.running) {
      Quickshell.execDetached(["notify-send", "Omafiles", "Still mounting an ISO — try again in a moment"])
      return
    }
    mountIsoProc.tabIndex = root.activeTabIndex
    mountIsoProc.command = ["bash", root.pluginDir + "/mount-iso.sh", root.joinPath(root.currentPath, entry.name)]
    mountIsoProc.running = true
  }

  Process {
    id: mountsProc
    command: [root.pluginDir + "/list-mounts.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: MountsState.mounts = Utils.parseMounts(text)
    }
  }

  Process {
    id: ejectProc
    property string mountPath: ""
    property bool wasInside: false
    property int tabIndex: -1
    property string errorText: ""
    property string device: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: ejectProc.errorText = text
    }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        if (ejectProc.wasInside) tabOps.navigateTabTo(ejectProc.tabIndex, root.homeDir)
        // Un .iso montado con mountIso() deja el /dev/loopN asociado al
        // fichero aunque ya esté desmontado -- sin esto, el .iso se queda
        // "en uso" (no se puede mover/borrar) y cada uno gastaría un loop
        // device para siempre hasta reiniciar.
        if (ejectProc.device.indexOf("/dev/loop") === 0) {
          Quickshell.execDetached(["udisksctl", "loop-delete", "-b", ejectProc.device])
        }
        refreshMounts()
      } else {
        Quickshell.execDetached(["notify-send", "Omafiles", "Could not eject: " + (ejectProc.errorText || "device busy")])
      }
    }
  }

  Process {
    id: mountProc
    property string outputText: ""
    property string errorText: ""
    property int tabIndex: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: mountProc.outputText = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: mountProc.errorText = text
    }
    onExited: function (exitCode) {
      refreshMounts()
      if (exitCode === 0) {
        var match = mountProc.outputText.match(/ at (\/[^\s.]+)/)
        if (match) tabOps.navigateTabTo(mountProc.tabIndex, match[1])
      } else {
        Quickshell.execDetached(["notify-send", "Omafiles", "Could not mount: " + (mountProc.errorText || "unknown error")])
      }
    }
  }

  Process {
    id: mountIsoProc
    property string outputText: ""
    property string errorText: ""
    property int tabIndex: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: mountIsoProc.outputText = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: mountIsoProc.errorText = text
    }
    onExited: function (exitCode) {
      refreshMounts()
      if (exitCode === 0) {
        var match = mountIsoProc.outputText.match(/ at (\/[^\s.]+)/)
        if (match) tabOps.navigateTabTo(mountIsoProc.tabIndex, match[1])
      } else {
        Quickshell.execDetached(["notify-send", "Omafiles", "Could not mount ISO: " + (mountIsoProc.errorText || "unknown error")])
      }
    }
  }

  Process {
    id: networkMountsProc
    command: [root.pluginDir + "/list-network-mounts.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: MountsState.networkMounts = Utils.parseNetworkMounts(text)
    }
  }

  Process {
    id: networkUnmountProc
    property bool wasInside: false
    property int tabIndex: -1
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: networkUnmountProc.errorText = text
    }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        if (networkUnmountProc.wasInside) tabOps.navigateTabTo(networkUnmountProc.tabIndex, root.homeDir)
        refreshNetworkMounts()
      } else {
        Quickshell.execDetached(["notify-send", "Omafiles", "Could not disconnect: " + (networkUnmountProc.errorText || "unknown error")])
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
  Process {
    id: networkMountProc
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: networkMountProc.errorText = text
    }
    onExited: function (exitCode) {
      DialogsState.networkConnecting = false
      if (exitCode === 0) {
        DialogsState.connectServerOpen = false
        // gio no imprime la ruta local igual que udisksctl -- se relista
        // y se entra al mount que no estaba antes (el que acaba de
        // aparecer) en vez de parsear la salida de "gio mount".
        networkMountsAfterConnectProc.beforePaths = MountsState.networkMounts.map(function (m) { return m.path })
        networkMountsAfterConnectProc.running = true
      } else {
        DialogsState.connectServerError = networkMountProc.errorText.trim() || "Could not connect"
      }
    }
  }

  // Segunda pasada de list-network-mounts.sh tras un connect con éxito,
  // solo para encontrar CUÁL de los mounts es el nuevo (comparando contra
  // los que ya había antes) y navegar directamente a él -- refreshNetworkMounts()
  // normal no distingue cuál acaba de aparecer.
  Process {
    id: networkMountsAfterConnectProc
    property var beforePaths: []
    command: [root.pluginDir + "/list-network-mounts.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Utils.parseNetworkMounts(text)
        MountsState.networkMounts = parsed
        var before = networkMountsAfterConnectProc.beforePaths
        var fresh = parsed.filter(function (m) { return before.indexOf(m.path) < 0 })
        if (fresh.length > 0) root.navigateTo(fresh[0].path)
      }
    }
  }
}

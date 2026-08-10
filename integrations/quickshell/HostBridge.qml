import QtQuick
import Quickshell
import ".."

// Adaptador de host Quickshell -- toda la integración específica de
// Quickshell para la ventana de Omafiles vive aquí (Fase 2, josema:
// separar el núcleo del proyecto de la integración con el host).
// FloatingWindow es el único tipo de Quickshell que expone esta capa:
// show()/hide()/close() + la señal closedExternally() son la API que el
// núcleo (Omafiles.qml) usa para no tocar Quickshell.FloatingWindow ni el
// objeto `shell` del host directamente. Los hijos declarados al
// instanciar HostBridge { ... } se cuelgan directo de FloatingWindow (su
// "default property" heredada, sin necesidad de un Item intermedio) --
// mismo árbol visual de siempre, sin tocarlo.
FloatingWindow {
  id: hostWindow

  // Asignado por el host: shell.qml hace "if ('shell' in item) item.shell
  // = shell" sobre CUALQUIER instancia de plugin con esta property --
  // eso ocurre en el `root` de Omafiles.qml (obligatorio, es el contrato
  // del host con el plugin), que reenvía aquí con `shell: root.shell`.
  // pluginId es el mismo id fijo que usa el resto del protocolo
  // (scripts/open-path.sh, scripts/dbus-filemanager1.py).
  property var shell: null
  readonly property string pluginId: "io.github.percius04.omafiles"

  // Puesto por Omafiles.qml mientras close() está en marcha (equivale al
  // antiguo root.closingFromHost) -- evita que un cierre INICIADO por
  // nosotros mismos (hide() -> shell.hide() -> el host llama de vuelta a
  // close() sobre el plugin) se interprete TAMBIÉN como un cierre
  // EXTERNO (botón de cerrar del gestor de ventanas) y dispare
  // closedExternally() por duplicado.
  property bool suppressExternalClose: false

  // Disparada cuando la ventana se oculta por un mecanismo que esta capa
  // no inició ella misma (botón de cerrar del gestor de ventanas) --
  // Omafiles.qml decide qué hacer con eso (mismo cuerpo que antes tenía
  // el onVisibleChanged de FloatingWindow, ahora cruzando la frontera vía
  // esta señal en vez de tocar root.opened/root.shell aquí dentro).
  signal closedExternally()

  function show() {
    hostWindow.visible = true
  }

  // Solo avisa al host -- shell.hide(pluginId) internamente llama de
  // vuelta a close() sobre esta misma instancia del plugin
  // (invokeIfLoaded, ver shell.qml), que es quien de verdad pone la
  // ventana a visible:false (vía close()). hide() en sí NO toca
  // hostWindow.visible directamente, mismo comportamiento que el
  // requestClose() original.
  function hide() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function close() {
    hostWindow.visible = false
  }

  onVisibleChanged: {
    if (!hostWindow.visible && !suppressExternalClose) closedExternally()
  }

  // Parte host-agnóstica del contrato (Fase 18): persistencia de tamaño.
  // FloatingWindow se dimensiona por implicitWidth/implicitHeight, así que el
  // tamaño restaurado se aplica ahí; el valor por defecto de abajo solo rige
  // la primera vez, antes de que exista window.json.
  HostAdapter {
    id: adapter
    window: hostWindow
  }

  Connections {
    target: adapter
    function onSizeRestored(w, h) {
      hostWindow.implicitWidth = w
      hostWindow.implicitHeight = h
    }
  }

  Component.onCompleted: adapter.restore()
}

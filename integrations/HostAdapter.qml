pragma ComponentBehavior: Bound
import QtQuick
import "../services"

// Contrato de host de Omafiles (Fase 18, josema) -- el ÚNICO artefacto que
// formaliza lo que un frontend anfitrión debe aportar al núcleo. Hay dos
// implementaciones que lo cumplen: integrations/quickshell/HostBridge.qml
// (sobre FloatingWindow) e integrations/standalone/Main.qml (sobre
// ApplicationWindow). El núcleo (core/OmafilesContent.qml) NO conoce ninguna
// de las dos: expone open()/close()/opened + la señal closeRequested() y nada
// más.
//
// El contrato se divide en:
//
//   1. Ventana/ciclo de vida  -- ESPECÍFICO del host, lo implementa cada
//      ventana anfitriona sobre su propio tipo (FloatingWindow /
//      ApplicationWindow). Cada host DEBE exponer:
//        · show()               mostrar la ventana
//        · hide()               ocultarla (sin destruir estado)
//        · close()              cerrarla
//        · signal closedExternally()  la ventana se fue por un mecanismo que
//                               el host no inició (botón de cerrar del WM)
//
//   2. Geometría              -- HOST-AGNÓSTICO, vive aquí y lo comparten los
//      dos hosts. Se limita al TAMAÑO: en Wayland el cliente no controla su
//      posición (la fija el compositor), así que "recordar posición" y
//      "centrar" no son capacidades del cliente -- center() es un no-op
//      documentado y solo persiste width/height.
//
// Las demás capacidades que a veces se piensan como "de host" (tema,
// notificaciones, abrir-externo, entorno, I/O de procesos) NO pasan por aquí:
// ya están abstraídas capa a capa en qs.Commons (tema) y services/ (Notifier,
// Detached, Env, ProcessRunner...), con la misma API en ambos frontends. Ver
// ARCHITECTURE.md ("Host contract") y el informe de la Fase 18.
QtObject {
  id: adapter

  // La ventana anfitriona (FloatingWindow o ApplicationWindow). Ambas
  // exponen width/height; cada host aplica el tamaño restaurado a su propia
  // propiedad de tamaño (implicitWidth/Height en Quickshell, width/height en
  // Qt6) desde el manejador de sizeRestored.
  property var window: null

  // Fichero de estado de ventana, compartido por los dos frontends (el tamaño
  // es preferencia "de la ventana de Omafiles", no del host). Mismo directorio
  // ~/.local/state/omafiles/ que el resto de la persistencia.
  readonly property string _file: Env.get("HOME") + "/.local/state/omafiles/window.json"

  // Emitida por restore() cuando hay un tamaño guardado válido -- el host lo
  // aplica a su propiedad de tamaño concreta.
  signal sizeRestored(int w, int h)

  // Lee el tamaño guardado (async: llega por onLoaded). El host llama a esto
  // en Component.onCompleted.
  function restore() {
    JsonStore.read(adapter._file)
  }

  // Persiste el tamaño actual (con rebote, para no escribir en cada píxel de
  // un arrastre de redimensionado).
  function remember() {
    _debounce.restart()
  }

  // No-op documentado: en Wayland el compositor coloca las ventanas; el
  // cliente no puede centrarse a sí mismo. Existe para completar el contrato
  // y para que un futuro host X11/otro pueda darle cuerpo sin tocar llamadas.
  function center() {}

  function _write() {
    if (!adapter.window) return
    JsonStore.write(adapter._file, {
      width: Math.round(adapter.window.width),
      height: Math.round(adapter.window.height)
    })
  }

  property Timer _debounce: Timer {
    interval: 400
    onTriggered: adapter._write()
  }

  property Connections _js: Connections {
    target: JsonStore
    function onLoaded(path, data, ok) {
      if (path !== adapter._file) return
      if (ok && data && data.width > 0 && data.height > 0)
        adapter.sizeRestored(data.width, data.height)
    }
  }

  property Connections _win: Connections {
    target: adapter.window
    ignoreUnknownSignals: true
    function onWidthChanged() { adapter.remember() }
    function onHeightChanged() { adapter.remember() }
  }
}

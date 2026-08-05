import QtQuick
import Quickshell
import Quickshell.Io

// API propia de Omafiles para ejecutar un proceso externo y enterarse
// de su resultado completo de una vez -- diseñada para cómo se usa de
// verdad en todo el proyecto (lanzar, comprobar si sigue ocupado,
// poder cancelar un grupo entero de procesos), no como un espejo de
// las properties/señales de Quickshell.Io.Process. Fase 1.5 (ver
// [[project_omafiles_standalone_prep]]): esta es la implementación de
// HOY sobre Quickshell -- cuando llegue standalone, solo el interior
// de este fichero se reescribe (sobre QProcess), ningún llamador
// cambia una línea.
//
// Para procesos que NO terminan solos (inotifywait -m y similares),
// ver services/ProcessWatcher.qml -- lifecycle distinto a propósito
// (línea a línea, sin "resultado final"), forzarlo en este mismo tipo
// habría complicado los dos casos por igual.
Item {
  id: root

  // true mientras hay una ejecución en marcha -- para el patrón
  // repetido en todo el proyecto "si ya está ocupado, avisar y salir"
  // antes de lanzar una nueva.
  readonly property bool busy: _proc.running

  // Se dispara siempre al terminar (con éxito, con fallo, o
  // cancelada), con el resultado completo ya listo -- sustituye a
  // leer onExited + stdout.onStreamFinished + stderr.onStreamFinished
  // por separado en cada sitio de llamada.
  signal finished(var result) // { exitCode, stdout, stderr, cancelled }

  // Lanza `args` (programa + argumentos). group:true envuelve el
  // comando en su propio grupo de procesos para que cancel() pueda
  // matar también a los hijos reales que haya lanzado (cp/mv/zip bajo
  // un "bash -c"), no solo al proceso inmediato -- mismo motivo que
  // llevaba a anteponer "setsid" a mano en cada sitio que lo
  // necesitaba. Devuelve false sin hacer nada si ya hay algo en
  // marcha (llamador decide si eso merece avisar al usuario).
  function start(args, group) {
    if (_proc.running) return false
    root._cancelled = false
    root._stdout = ""
    root._stderr = ""
    _proc.command = group ? ["setsid"].concat(args) : args
    _proc.running = true
    return true
  }

  // Mata la ejecución en marcha (todo su grupo si se lanzó con
  // group:true). No-op si no hay nada corriendo. `finished` se sigue
  // disparando (con cancelled:true) cuando el proceso realmente
  // termine tras la señal.
  function cancel() {
    if (!_proc.running) return
    root._cancelled = true
    var pid = _proc.processId
    if (pid) Quickshell.execDetached(["kill", "-TERM", "--", "-" + pid])
    _proc.running = false
  }

  property bool _cancelled: false
  property string _stdout: ""
  property string _stderr: ""

  Process {
    id: _proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._stdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }
    onExited: function (exitCode) {
      var wasCancelled = root._cancelled
      root._cancelled = false
      root.finished({
        exitCode: exitCode,
        stdout: root._stdout,
        stderr: root._stderr,
        cancelled: wasCancelled
      })
    }
  }
}

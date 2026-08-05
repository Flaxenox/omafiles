import QtQuick
import Quickshell.Io

// API propia de Omafiles para vigilar un proceso que NO termina solo
// (inotifywait -m y similares, modo monitor) -- emite `lineRead` por
// cada línea que llega en vez de esperar a un "resultado final" como
// services/ProcessRunner.qml. Único uso actual: vigilancia de cambios
// en la carpeta activa (ver logic/NavigationController.qml). Fase 1.5
// (ver [[project_omafiles_standalone_prep]]).
Item {
  id: root

  readonly property bool active: _proc.running

  // Una línea de salida del proceso vigilado -- el contenido en sí
  // normalmente da igual (dirWatchProc solo necesita SABER que algo
  // cambió, no QUÉ), pero se pasa por si algún caso futuro lo
  // necesita.
  signal lineRead(string line)

  function start(args) {
    _proc.running = false
    _proc.command = args
    _proc.running = true
  }

  function stop() {
    _proc.running = false
  }

  Process {
    id: _proc
    stdout: SplitParser {
      onRead: function (line) { root.lineRead(line) }
    }
  }
}

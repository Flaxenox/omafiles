import QtQuick

// Variante standalone de services/ProcessRunner.qml (Fase 4, josema),
// seleccionada automáticamente por QQmlFileSelector (ver main.cpp,
// selector "standalone") -- ningún import en logic/ cambia, solo la
// implementación que resuelve "../services". No ejecuta ningún proceso
// real todavía (eso requiere un tipo QML respaldado por C++/QProcess,
// fuera del alcance de "primer arranque") -- devuelve un resultado
// vacío async, lo justo para que busy/finished no se queden colgados y
// la UI no crashee, aunque la lista de ficheros salga vacía.
Item {
  id: root
  readonly property bool busy: _timer.running
  signal finished(var result)

  function start(args, group) {
    if (_timer.running) return false
    console.warn("[standalone] ProcessRunner.start ignorado (sin QProcess todavía):", JSON.stringify(args))
    _timer.start()
    return true
  }

  function cancel() {
    _timer.stop()
  }

  Timer {
    id: _timer
    interval: 0
    onTriggered: root.finished({ exitCode: 1, stdout: "", stderr: "not available in standalone build", cancelled: false })
  }
}

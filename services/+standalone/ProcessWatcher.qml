import QtQuick

// Variante standalone de services/ProcessWatcher.qml (Fase 4, josema) --
// ver ProcessRunner.qml en esta misma carpeta para el porqué. La
// vigilancia de directorio (inotify) simplemente no hace nada todavía.
Item {
  readonly property bool active: false
  signal lineRead(string line)

  function start(args) {}
  function stop() {}
}

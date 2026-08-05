pragma Singleton
import QtQuick
import Quickshell

// Ejecución "dispara y olvida" de un proceso externo -- sin
// seguimiento de resultado, sin busy/cancel (para eso,
// services/ProcessRunner.qml). Fase 1.5 (ver
// [[project_omafiles_standalone_prep]]): hoy delega en
// Quickshell.execDetached(), pero es el único sitio que debería
// necesitar saberlo.
QtObject {
  function run(args) {
    Quickshell.execDetached(args)
  }
}

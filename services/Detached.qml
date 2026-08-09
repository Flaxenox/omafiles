pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Ejecucion "dispara y olvida" de un proceso externo -- sin seguimiento
// de resultado, sin busy/cancel (para eso, services/ProcessRunner.qml).
// Adaptador fino sobre el singleton C++ Omafiles.Backend.Detached
// (QProcess::startDetached, ver backend/Detached.cpp).
//
// Fase 5.C (josema): implementacion UNICA para los dos frontends. Antes
// esto delegaba en Quickshell.execDetached() y el standalone tenia un stub
// que solo avisaba por consola; ahora ambos usan el mismo backend C++ y el
// stub desaparece. logic/ sigue llamando Detached.run(args) igual.
QtObject {
  function run(args) { Backend.Detached.run(args) }
}

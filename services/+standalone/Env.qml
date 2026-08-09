pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Adaptador standalone de services/Env.qml (Fase 5, josema). Delega en el
// singleton C++ Omafiles.Backend.Env (qEnvironmentVariable real, ver
// backend/Env.cpp). Sustituye al truco de la Fase 4, que solo sabia
// devolver HOME desde un context property inyectado por main.cpp; ahora
// se lee cualquier variable directamente del entorno. QQmlFileSelector lo
// selecciona para el host standalone; logic/ sigue llamando Env.get(name)
// igual que en Quickshell.
QtObject {
  function get(name) { return Backend.Env.get(name) }
}

pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Persistencia JSON -- adaptador fino sobre el singleton C++
// Omafiles.Backend.JsonStore (QFile/QSaveFile/QJsonDocument, ver
// backend/JsonStore.cpp). Fase 6.A (josema): implementacion UNICA para los
// dos frontends, igual que el resto de services/.
//
// Su razon de existir es la regla 8 de BACKEND_DESIGN.md: logic/ no importa
// Omafiles.Backend, pasa por aqui. Como los consumidores necesitan las
// senales (read es async), este adaptador las re-emite: reenvia read/write
// al backend y propaga loaded/saved para que logic/ se conecte a
// Omafiles.Services.JsonStore sin conocer el nombre del modulo backend.
QtObject {
  signal loaded(string path, var data, bool ok)
  signal saved(string path, bool ok)

  function read(path) { Backend.JsonStore.read(path) }
  function write(path, data) { return Backend.JsonStore.write(path, data) }

  property Connections _backend: Connections {
    target: Backend.JsonStore
    function onLoaded(path, data, ok) { loaded(path, data, ok) }
    function onSaved(path, ok) { saved(path, ok) }
  }
}

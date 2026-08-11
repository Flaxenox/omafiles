pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// JSON persistence -- thin adapter over the C++ singleton
// Omafiles.Backend.JsonStore (QFile/QSaveFile/QJsonDocument, see
// backend/JsonStore.cpp). Phase 6.A (josema): a SINGLE implementation for both
// frontends, like the rest of services/.
//
// Its reason to exist is rule 8 of BACKEND_DESIGN.md: logic/ does not import
// Omafiles.Backend, it goes through here. Since the consumers need the
// signals (read is async), this adapter re-emits them: it forwards read/write
// to the backend and propagates loaded/saved so logic/ connects to
// Omafiles.Services.JsonStore without knowing the backend module's name.
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

pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Autocompletado de rutas -- adaptador fino sobre el singleton C++
// Omafiles.Backend.PathCompleter (QDir en C++, sin procesos externos, ver
// backend/PathCompleter.cpp). Lo usa la barra de dirección (Ctrl+L).
//
// Existe solo para dar el nombre Omafiles.Services.PathCompleter y aislar a
// la capa visual del nombre del módulo backend (regla 8 de BACKEND_DESIGN.md).
QtObject {
  function complete(input, base) { return Backend.PathCompleter.complete(input, base, 50) }
  function expandTilde(input) { return Backend.PathCompleter.expandTilde(input) }
}

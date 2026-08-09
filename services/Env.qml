pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Lectura de variables de entorno -- adaptador fino sobre el singleton
// C++ Omafiles.Backend.Env (qEnvironmentVariable real, ver
// backend/Env.cpp). Fase 5.C (josema): implementacion UNICA y compartida
// por los dos frontends (Quickshell y Qt6 standalone), ambos cargando el
// mismo .so por import path -- ya no hay variante +standalone.
//
// La razon de existir de este fichero es solo dar el nombre
// Omafiles.Services.Env y aislar a logic/ del nombre del modulo backend
// (regla 8 de BACKEND_DESIGN.md). logic/ sigue llamando Env.get(name)
// igual que cuando esto delegaba en Quickshell.env().
QtObject {
  function get(name) { return Backend.Env.get(name) }
}

import Omafiles.Backend as Backend

// Vigila un proceso que NO termina solo (inotifywait -m y similares, modo
// monitor): emite lineRead por cada linea en vez de un resultado final
// (start / stop / active / lineRead). Adaptador fino que re-exporta el
// tipo C++ Omafiles.Backend.ProcessWatcher (QProcess en modo monitor, ver
// backend/ProcessWatcher.cpp) bajo el nombre Omafiles.Services.ProcessWatcher.
//
// Fase 5.C (josema): implementacion UNICA para los dos frontends, igual
// que ProcessRunner -- se retira la version Quickshell (Quickshell.Io) y
// queda solo esta costura QML<->C++. Unico uso actual: vigilancia de
// cambios en la carpeta activa (ver logic/NavigationController.qml).
Backend.ProcessWatcher {}

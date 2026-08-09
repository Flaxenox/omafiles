import Omafiles.Backend as Backend

// Adaptador standalone de services/ProcessWatcher.qml (Fase 5, josema).
// Re-exporta el tipo C++ Omafiles.Backend.ProcessWatcher (QProcess en
// modo monitor, ver backend/ProcessWatcher.cpp) bajo el nombre
// Omafiles.Services.ProcessWatcher que espera logic/. QQmlFileSelector lo
// selecciona para el host standalone sin que ningun import de logic/
// cambie.
//
// Sustituye al stub de la Fase 4 que no vigilaba nada (la carpeta activa
// no se auto-refrescaba al cambiar en disco). API (start/stop/active/
// lineRead) identica a la version Quickshell.
Backend.ProcessWatcher {}

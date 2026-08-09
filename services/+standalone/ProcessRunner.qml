import Omafiles.Backend as Backend

// Adaptador standalone de services/ProcessRunner.qml (Fase 5, josema).
// Re-exporta el tipo C++ Omafiles.Backend.ProcessRunner (respaldado por
// QProcess real, ver backend/ProcessRunner.cpp) bajo el nombre
// Omafiles.Services.ProcessRunner que espera logic/. QQmlFileSelector lo
// selecciona para el host standalone en vez de la implementacion
// Quickshell, sin que ningun import de logic/ cambie.
//
// Sustituye al stub de la Fase 4 que no ejecutaba ningun proceso (la
// lista de ficheros salia vacia). La API (start/busy/cancel/finished) es
// identica a la version Quickshell; toda la logica vive ya en C++, asi
// que este adaptador es solo la costura QML<->C++ que pide la Fase 5.
Backend.ProcessRunner {}

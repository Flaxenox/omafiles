import Omafiles.Backend as Backend

// Ejecuta un proceso externo y entrega su resultado completo de una vez
// (start / busy / cancel / finished{exitCode,stdout,stderr,cancelled}).
// Adaptador fino que re-exporta el tipo C++ Omafiles.Backend.ProcessRunner
// (respaldado por QProcess real, ver backend/ProcessRunner.cpp) bajo el
// nombre Omafiles.Services.ProcessRunner que espera logic/.
//
// Fase 5.C (josema): implementacion UNICA para los dos frontends. Antes
// habia dos -- esta (Quickshell.Io.Process) y services/+standalone/ sobre
// el backend C++; ahora Quickshell tambien carga el .so por import path,
// asi que la version Quickshell se retira y queda solo esta costura
// QML<->C++. La API (start/busy/cancel/finished) es identica; logic/ sigue
// escribiendo `ProcessRunner { onFinished: ... }` sin enterarse.
//
// Para procesos que NO terminan solos (inotifywait -m y similares), ver
// services/ProcessWatcher.qml.
Backend.ProcessRunner {}

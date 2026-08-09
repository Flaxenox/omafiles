import Omafiles.Backend as Backend

// Búsqueda recursiva -- adaptador fino que re-exporta el tipo C++
// Omafiles.Backend.SearchWorker (QDirIterator + QThreadPool, ver
// backend/SearchWorker.cpp) bajo Omafiles.Services.SearchWorker. Fase 16
// (josema): sustituto nativo de search-recursive.sh.
//
// No es singleton (como DirectoryModel/ProcessRunner): SearchOps tiene su
// propia instancia. La API (search/cancel/results) no cambia; logic/ no
// importa Omafiles.Backend directamente (regla 8).
Backend.SearchWorker {}

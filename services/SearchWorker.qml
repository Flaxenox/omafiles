import Omafiles.Backend as Backend

// Recursive search -- thin adapter that re-exports the C++ type
// Omafiles.Backend.SearchWorker (QDirIterator + QThreadPool, see
// backend/SearchWorker.cpp) under Omafiles.Services.SearchWorker. Phase 16
// (josema): native replacement for search-recursive.sh.
//
// Not a singleton (like DirectoryModel/ProcessRunner): SearchOps has its
// own instance. The API (search/cancel/results) does not change; logic/ does not
// import Omafiles.Backend directly (rule 8).
Backend.SearchWorker {}

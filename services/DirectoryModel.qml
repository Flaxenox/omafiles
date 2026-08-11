import Omafiles.Backend as Backend

// Directory listing -- thin adapter that re-exports the C++ type
// Omafiles.Backend.DirectoryModel (QAbstractListModel over readdir/stat,
// see backend/DirectoryModel.cpp) under the name
// Omafiles.Services.DirectoryModel. Phase 6.B (josema).
//
// Not a singleton on purpose: like ProcessRunner, several tabs can
// list different paths at once, each with its own instance. The API
// (list/error/loading/count/entries/listed + the model roles) is the
// backend's; logic/ does not import Omafiles.Backend directly (rule 8). It is the
// live source of the listing since Phase 6.C (there is no more list-dir.sh): both the
// active panel (NavigationController) and the background ones (BackgroundPanel)
// list through here via DirLister.
Backend.DirectoryModel {}

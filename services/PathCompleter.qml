pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Path autocompletion -- thin adapter over the C++ singleton
// Omafiles.Backend.PathCompleter (QDir in C++, no external processes, see
// backend/PathCompleter.cpp). Used by the address bar (Ctrl+L).
//
// It exists only to give the name Omafiles.Services.PathCompleter and isolate
// the visual layer from the backend module's name (rule 8 of BACKEND_DESIGN.md).
QtObject {
  function complete(input, base) { return Backend.PathCompleter.complete(input, base, 50) }
  function expandTilde(input) { return Backend.PathCompleter.expandTilde(input) }
}

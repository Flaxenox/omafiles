pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Reading environment variables -- thin adapter over the C++ singleton
// Omafiles.Backend.Env (real qEnvironmentVariable, see
// backend/Env.cpp). Phase 5.C (josema): a SINGLE implementation shared
// by the frontend, loading the
// same .so by import path -- there is no more +standalone variant.
//
// The reason this file exists is only to give the name
// Omafiles.Services.Env and isolate logic/ from the backend module's name
// (rule 8 of BACKEND_DESIGN.md). logic/ keeps calling Env.get(name)
// just like when this delegated to Env().
QtObject {
  function get(name) { return Backend.Env.get(name) }
}

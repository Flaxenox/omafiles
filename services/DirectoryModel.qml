import Omafiles.Backend as Backend

// Listado de directorios -- adaptador fino que re-exporta el tipo C++
// Omafiles.Backend.DirectoryModel (QAbstractListModel sobre readdir/stat,
// ver backend/DirectoryModel.cpp) bajo el nombre
// Omafiles.Services.DirectoryModel. Fase 6.B (josema).
//
// No es singleton a proposito: como ProcessRunner, varias pestanas pueden
// listar rutas distintas a la vez, cada una con su instancia. La API
// (list/error/loading/count/entries/listed + roles del modelo) es la del
// backend; logic/ no importa Omafiles.Backend directamente (regla 8).
//
// En 6.B este adaptador existe para poder validar el modelo por la misma
// costura que usara el consumidor; list-dir.sh sigue siendo la fuente viva
// del panel hasta que la equivalencia este confirmada (Fase 6.C).
Backend.DirectoryModel {}

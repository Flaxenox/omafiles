import Omafiles.Backend as Backend

// Listado de directorios -- adaptador fino que re-exporta el tipo C++
// Omafiles.Backend.DirectoryModel (QAbstractListModel sobre readdir/stat,
// ver backend/DirectoryModel.cpp) bajo el nombre
// Omafiles.Services.DirectoryModel. Fase 6.B (josema).
//
// No es singleton a proposito: como ProcessRunner, varias pestanas pueden
// listar rutas distintas a la vez, cada una con su instancia. La API
// (list/error/loading/count/entries/listed + roles del modelo) es la del
// backend; logic/ no importa Omafiles.Backend directamente (regla 8). Es la
// fuente viva del listado desde la Fase 6.C (ya no hay list-dir.sh): tanto el
// panel activo (NavigationController) como los de fondo (BackgroundPanel)
// listan por aqui via DirLister.
Backend.DirectoryModel {}

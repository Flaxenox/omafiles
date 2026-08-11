import QtQuick
import "../state"
import "../services"

// Lista un directorio y expone el resultado ya ordenado -- vigésimo tercer
// componente extraído de Omafiles.qml (Fase 1.6, josema). Reutilizado por
// NavigationController (panel activo, una instancia) y BackgroundPanel (una
// por pestaña de fondo). Cada uno tiene su instancia: varias pestañas
// pueden listar rutas distintas a la vez.
//
// Fase 6.C/6.D (josema): backend de listado 100% NATIVO. Ya no se lanza
// list-dir.sh ni list-trash.sh; el listado lo hace Omafiles.Backend.
// DirectoryModel (QAbstractListModel sobre readdir/stat), y la vigilancia
// de cambios la hace su QFileSystemWatcher interno (sin forkear
// inotifywait). Adaptador fino sobre el modelo:
//   - carpeta normal -> dirModel.list(path)
//   - Papelera -> trash-roots.sh (descubrir raíces XDG) + dirModel.listMany
//     (fusionar el contenido de todas) + trash-info.sh (metadatos)
// La API pública (entries/pathError/loaded/listed/list) no cambia, así que
// NavigationController y BackgroundPanel siguen igual.
Item {
  id: dirLister
  property string trashDir: ""
  property bool showHidden: false
  property Item sortOps: null

  property var entries: []
  property string pathError: ""
  property bool loaded: false

  // Emitida cada vez que entries se resuelve de verdad (con contenido
  // nuevo o repetido) -- distinto de onEntriesChanged, que con QML no
  // dispara si el array resultante es igual (mismo bug que _apply()
  // evita reasignando solo si cambió). Quien necesite reaccionar a CADA
  // listado, cambie o no el contenido (ej. _finishListLoad en el panel
  // activo: reset de scroll/selección), debe usar esta señal.
  signal listed()

  // El contenido de la carpeta vigilada cambió (reenvía dirModel.
  // directoryChanged, vigilancia nativa). NavigationController se engancha
  // aquí en vez de a inotifywait para su debounce + refresco.
  signal directoryChanged()

  property string _targetPath: ""
  // Modo del último escaneo lanzado al modelo ("dir" o "trash"). Junto con
  // la generación interna del modelo, descarta resultados obsoletos al
  // cambiar entre una carpeta normal y la Papelera (el modelo sirve a
  // ambos): un resultado cuyo modo no coincide con la ruta actual se tira.
  property string _dirMode: "dir"
  // Firma de contenido del último listado APLICADO (DirectoryModel.signature,
  // hash 64-bit calculado en el worker). Fase 27 (PERF_AUDIT_RC1): la guarda
  // "¿cambió la carpeta?" pasa de un Utils.entriesEqual O(n) —que iteraba las
  // 100k entradas en el hilo de UI y forzaba materializar todo el array
  // (medido: 342 ms/refresco a 100k)— a una comparación de string O(1).
  property string _lastSignature: ""

  function list(path) {
    _targetPath = path
    pathError = ""
    if (path === trashDir) {
      // La Papelera agrega la raíz de casa MÁS la .Trash-$UID de cualquier
      // disco montado (spec XDG Trash). FileOperations.trashRoots() las
      // descubre (nativo, Fase 16: sustituye a trash-roots.sh); luego se
      // fusiona el contenido de todas con listMany. No es una carpeta única,
      // por eso no pasa por dirModel.list a secas.
      var paths = FileOperations.trashRoots().map(function (r) { return r + "/files" })
      _dirMode = "trash"
      dirModel.listMany(paths, showHidden)
    } else {
      _dirMode = "dir"
      dirModel.list(path, showHidden)
    }
  }

  // Vigilancia nativa del directorio actual (Fase 6.D). Devuelve false si
  // el modelo no pudo vigilar (ruta inválida, límite de descriptores) para
  // que el llamador caiga al fallback inotifywait.
  function watch(path) {
    return dirModel.watch(path)
  }

  function unwatch() {
    dirModel.unwatch()
  }

  // Reasigna entries SOLO si el contenido de verdad cambió -- QML/
  // ListView no compara el contenido de un array modelo, solo la
  // referencia, así que reasignar aunque los datos sean idénticos
  // dispara un relayout completo (recrea TODAS las filas desde cero,
  // salto visible reportado por josema -- ver el historial de
  // NavigationController/BackgroundPanel antes de esta extracción).
  function _apply() {
    // Guarda "¿cambió la carpeta?" por FIRMA (Fase 27), no por contenido:
    // DirectoryModel.signature es un hash del contenido calculado en el hilo
    // worker. Antes (Fase 10.A) se comparaba con Utils.entriesEqual, O(n) en
    // el hilo de UI, que además forzaba materializar TODO el array perezoso
    // (dirModel.entries) al recorrerlo. Ahora sólo se lee/materializa
    // dirModel.entries cuando la firma cambió de verdad -> los refrescos del
    // watcher sobre carpetas sin cambios cuestan una comparación de string.
    // Se mantiene la MISMA referencia de `entries` cuando no cambió, para que
    // NavigationController pueda comparar por referencia aguas arriba.
    var sig = dirModel.signature
    if (sig !== _lastSignature) {
      _lastSignature = sig
      entries = _sorted(dirModel.entries)
    }
    loaded = true
    listed()
  }

  // Orden final: C++ (DirectoryModel) ya devuelve las entradas ordenadas por
  // naturalCompare (carpetas primero) -- el orden por defecto que ve el
  // usuario. Solo hace falta re-ordenar en JS si el usuario eligió otro
  // criterio (tamaño/fecha/tipo o descendente). Fase 10.A: elimina los ~31 ms
  // de re-ordenar en el hilo de UI lo que C++ ya ordenó.
  function _sorted(raw) {
    return sortOps.isDefaultOrder ? raw : sortOps.sortEntries(raw)
  }

  // Backend nativo de listado (Fase 6.C/6.D). Sirve tanto carpetas normales
  // (list) como la Papelera (listMany). El array dirModel.entries tiene la
  // misma forma {type,name,size,mtime,link} que producía Utils.parseEntries,
  // y pasa por el mismo sortOps.sortEntries + _apply.
  DirectoryModel {
    id: dirModel
    // Cualificado con el id: dirModel TAMBIEN tiene una senal
    // directoryChanged, asi que sin cualificar se reemitiria la del propio
    // modelo (colision de nombres) en vez de la de DirLister.
    onDirectoryChanged: dirLister.directoryChanged()
    onListed: {
      var isTrash = (_targetPath === trashDir)
      // Descarta resultados de un modo que ya no corresponde a la ruta
      // actual (carrera carpeta<->papelera). La generación interna del
      // modelo cubre carpeta->carpeta; esta guarda cubre el cruce de modo.
      if (isTrash !== (_dirMode === "trash")) return

      if (isTrash) {
        // listMany no produce códigos de error (agregado); la Papelera
        // simplemente muestra lo que haya. Metadatos de papelera NATIVOS
        // (FileOperations.trashInfo, Fase 16: sustituye a trash-info.sh):
        // síncronos, así que se rellenan ANTES de pintar -- sin la danza
        // async previa (ni parpadeo). TrashState.trashInfo es compartida por
        // el panel activo y los de fondo; DeleteOps/FileOps la usan para
        // saber la raíz física de cada ítem al restaurar/borrar.
        var arr = FileOperations.trashInfo()
        var info = {}
        for (var i = 0; i < arr.length; i++)
          info[arr[i].name] = { origPath: arr[i].origPath, epoch: arr[i].epoch, trashRoot: arr[i].trashRoot }
        TrashState.trashInfo = info
        _apply()
      } else {
        // Carpeta normal: mapear el error del modelo a pathError con los
        // MISMOS códigos que daban los exit codes de list-dir.sh.
        var e = dirModel.error
        if (e === 2) pathError = "Permission denied"
        else if (e === 3) pathError = "This folder no longer exists"
        else if (e === 4) pathError = "Not a folder"
        else if (e !== 0) pathError = "Couldn't open this folder"
        _apply()
      }
    }
  }
}

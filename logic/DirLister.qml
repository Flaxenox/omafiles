import QtQuick
import "../state"
import "../services"
import "../Utils.js" as Utils

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
  property string pluginDir: ""
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
  property bool _waitingForTrashInfo: false
  property var _pendingEntries: []
  // Modo del último escaneo lanzado al modelo ("dir" o "trash"). Junto con
  // la generación interna del modelo, descarta resultados obsoletos al
  // cambiar entre una carpeta normal y la Papelera (el modelo sirve a
  // ambos): un resultado cuyo modo no coincide con la ruta actual se tira.
  property string _dirMode: "dir"

  function list(path) {
    _targetPath = path
    pathError = ""
    if (path === trashDir) {
      // La Papelera agrega la raíz de casa MÁS la .Trash-$UID de cualquier
      // disco montado (spec XDG Trash). trash-roots.sh las descubre; luego
      // se fusiona el contenido de todas con listMany. No es una carpeta
      // única, por eso no pasa por dirModel.list a secas.
      rootsProc.start([pluginDir + "/trash-roots.sh"])
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
  function _apply(parsed) {
    // Comparación por contenido barata (Fase 10.A): antes eran dos
    // JSON.stringify del array completo por refresco. Se mantiene la MISMA
    // referencia de `entries` cuando no cambió, para que NavigationController
    // pueda comparar por referencia aguas arriba.
    if (!Utils.entriesEqual(parsed, entries)) entries = parsed
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

  // Descubrimiento de raíces de papelera (trash-roots.sh, una línea por
  // raíz). No es "listar una carpeta", es plumbing XDG específico de la
  // papelera, por eso sigue siendo un script pequeño; el listado en sí ya
  // es nativo (dirModel.listMany sobre "<raíz>/files").
  ProcessRunner {
    id: rootsProc
    onFinished: function (result) {
      // Obsoleto si ya se navegó fuera de la Papelera mientras corría.
      if (_targetPath !== trashDir) return
      var roots = String(result.stdout || "").split("\n").filter(function (r) { return r !== "" })
      var paths = roots.map(function (r) { return r + "/files" })
      _dirMode = "trash"
      dirModel.listMany(paths, showHidden)
    }
  }

  // TrashState.trashInfo es COMPARTIDA entre el panel activo y todos los
  // paneles de fondo -- quien llegue primero (activo o cualquiera de
  // fondo) la deja lista para todos los demás, sin que cada lister
  // tenga que esperar a su propia copia.
  ProcessRunner {
    id: trashInfoProc
    onFinished: function (result) {
      var fields = String(result.stdout || "").split("\u0000")
      if (fields.length > 0 && fields[fields.length - 1] === "") fields.pop()
      var info = {}
      for (var i = 0; i + 3 < fields.length; i += 4) {
        info[fields[i]] = { origPath: fields[i + 1], epoch: Number(fields[i + 2] || 0), trashRoot: fields[i + 3] }
      }
      TrashState.trashInfo = info
      if (_waitingForTrashInfo) {
        _waitingForTrashInfo = false
        _apply(_pendingEntries)
      }
    }
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
        // simplemente muestra lo que haya. Coordinación con trash-info
        // idéntica a antes: pintar ya si trashInfo está cargada, o esperar
        // a trash-info.sh la primera vez para no parpadear.
        var parsed = _sorted(dirModel.entries)
        if (Object.keys(TrashState.trashInfo).length > 0) {
          _apply(parsed)
        } else {
          _pendingEntries = parsed
          _waitingForTrashInfo = true
        }
        trashInfoProc.start([pluginDir + "/trash-info.sh"])
      } else {
        // Carpeta normal: mapear el error del modelo a pathError con los
        // MISMOS códigos que daban los exit codes de list-dir.sh.
        var e = dirModel.error
        if (e === 2) pathError = "Permission denied"
        else if (e === 3) pathError = "This folder no longer exists"
        else if (e === 4) pathError = "Not a folder"
        else if (e !== 0) pathError = "Couldn't open this folder"
        _apply(_sorted(dirModel.entries))
      }
    }
  }
}

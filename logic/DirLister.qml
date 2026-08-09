import QtQuick
import "../state"
import "../services"
import "../Utils.js" as Utils

// Lista un directorio (list-dir.sh, o list-trash.sh + trash-info.sh si es
// la Papelera) y expone el resultado ya parseado/ordenado -- vigésimo
// tercer componente extraído de Omafiles.qml (Fase 1.6, josema).
// Reutilizado por NavigationController (panel activo, una instancia) y
// BackgroundPanel (una instancia por pestaña de fondo) -- antes cada uno
// reimplementaba por separado el mismo parseo/orden/mapeo de exitCode a
// error/coordinación con trash-info.sh. Sigue siendo un Process propio
// POR INSTANCIA (no uno global compartido): varias pestañas pueden estar
// listando rutas distintas a la vez, así que compartir un único Process
// las haría pisarse entre sí.
Item {
  property string pluginDir: ""
  property string trashDir: ""
  property bool showHidden: false
  property Item sortOps: null

  property var entries: []
  property string pathError: ""
  property bool loaded: false

  // Fase 6.B.1 (josema): fuente del listado de carpetas normales. true =
  // DirectoryModel nativo (backend C++); false = list-dir.sh (el script,
  // que se mantiene como FALLBACK temporal mientras el nativo se asienta).
  // La Papelera va SIEMPRE por list-trash.sh: agrega varias raices XDG y
  // el modelo nativo no la cubre. Cambiar esto a false (o enlazarlo a una
  // propiedad de root) devuelve el comportamiento anterior sin tocar nada
  // mas -- ni el script ni esta clase pierden ninguna capacidad.
  property bool useNativeLister: true

  // Emitida cada vez que entries se resuelve de verdad (con contenido
  // nuevo o repetido) -- distinto de onEntriesChanged, que con QML no
  // dispara si el array resultante es igual (mismo bug que _apply()
  // evita reasignando solo si cambió). Quien necesite reaccionar a CADA
  // listado, cambie o no el contenido (ej. _finishListLoad en el panel
  // activo: reset de scroll/selección), debe usar esta señal.
  signal listed()

  property string _targetPath: ""
  property bool _waitingForTrashInfo: false
  property var _pendingEntries: []

  function list(path) {
    _targetPath = path
    pathError = ""
    // La Papelera agrega la de casa MÁS la de cualquier otro disco
    // montado que tenga la suya propia (spec de XDG Trash) -- ver
    // list-trash.sh/trash-roots.sh. No es una carpeta real única, así
    // que no puede pasar por list-dir.sh a secas como el resto.
    if (path === trashDir) {
      listProc.start([pluginDir + "/list-trash.sh", showHidden ? "1" : "0"])
    } else if (useNativeLister) {
      dirModel.list(path, showHidden)
    } else {
      listProc.start([pluginDir + "/list-dir.sh", path, showHidden ? "1" : "0"])
    }
  }

  // Reasigna entries SOLO si el contenido de verdad cambió -- QML/
  // ListView no compara el contenido de un array modelo, solo la
  // referencia, así que reasignar aunque los datos sean idénticos
  // dispara un relayout completo (recrea TODAS las filas desde cero,
  // salto visible reportado por josema -- ver el historial de
  // NavigationController/BackgroundPanel antes de esta extracción).
  function _apply(parsed) {
    if (JSON.stringify(parsed) !== JSON.stringify(entries)) entries = parsed
    loaded = true
    listed()
  }

  ProcessRunner {
    id: listProc
    // stdout ya deja entries vacío (list-dir.sh no imprime nada si falla);
    // exitCode solo añade el porqué, según el código de salida documentado
    // en list-dir.sh.
    onFinished: function (result) {
      // Con el lister nativo activo, listProc solo sirve la Papelera. Un
      // resultado que llega cuando ya se navego fuera de ella (trash ->
      // carpeta normal) es obsoleto: descartarlo, no pintar datos de
      // papelera sobre otra carpeta. En modo fallback (useNativeLister
      // false) listProc sirve tambien carpetas normales y no se descarta.
      if (useNativeLister && _targetPath !== trashDir) return
      if (result.exitCode === 2) pathError = "Permission denied"
      else if (result.exitCode === 3) pathError = "This folder no longer exists"
      else if (result.exitCode === 4) pathError = "Not a folder"
      else if (result.exitCode !== 0) pathError = "Couldn't open this folder"
      var parsed = sortOps.sortEntries(Utils.parseEntries(result.stdout))
      if (_targetPath === trashDir) {
        if (Object.keys(TrashState.trashInfo).length > 0) {
          // Ya hay trashInfo cargada -- de este mismo lister en una
          // visita anterior, o COMPARTIDA desde otro (activo o de
          // fondo, ver trashInfoProc: TrashState.trashInfo es una sola
          // copia para todos). Pintar ya con eso; el trashInfoProc de
          // abajo solo la refresca por detrás sin bloquear el pintado.
          _apply(parsed)
        } else {
          // Primera vez que se ve la Papelera en toda la sesión --
          // esperar a que trash-info.sh termine para pintar ya con el
          // texto final ("Deleted X ago · from ...") de una sola vez.
          // Si se pintara ya con solo el tamaño y esa parte llegara un
          // instante después, el texto más largo haría crecer la fila
          // y todo lo de debajo saltaría de sitio (parpadeo real,
          // reportado por josema).
          _pendingEntries = parsed
          _waitingForTrashInfo = true
        }
        trashInfoProc.start([pluginDir + "/trash-info.sh"])
      } else {
        // NO se limpia TrashState.trashInfo al salir de la Papelera --
        // es COMPARTIDA entre todos los listers (activo y de fondo),
        // así que vaciarla aquí sin más se la quitaba también a otro
        // que siguiera mostrando la Papelera en ese mismo instante. Ese
        // vacío + el rellenado casi inmediato que le seguía era el
        // salto real reportado por josema. Dejarla con datos obsoletos
        // sin más uso no hace daño -- solo se consulta cuando la ruta
        // ES la Papelera.
        _apply(parsed)
      }
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

  // Lister nativo de carpetas normales (Fase 6.B.1) -- QAbstractListModel
  // C++ que sustituye a list-dir.sh. Mismo contrato observable que el
  // camino del script: se mapea dirModel.error a pathError con los MISMOS
  // codigos (2/3/4/otros), y dirModel.entries (array {type,name,size,
  // mtime,link}, identico a Utils.parseEntries) pasa por el mismo
  // sortOps.sortEntries + _apply. No cubre la Papelera (eso es listProc).
  DirectoryModel {
    id: dirModel
    onListed: {
      // Resultado obsoleto si ya navegamos a la Papelera (va por listProc).
      if (_targetPath === trashDir) return
      var e = dirModel.error
      if (e === 2) pathError = "Permission denied"
      else if (e === 3) pathError = "This folder no longer exists"
      else if (e === 4) pathError = "Not a folder"
      else if (e !== 0) pathError = "Couldn't open this folder"
      _apply(sortOps.sortEntries(dirModel.entries))
    }
  }
}

import QtQuick

// Servicio de búsqueda GLOBAL. Abstrae tres backends tras un ÚNICO contrato
// (search / cancel / señal results), idéntico al de SearchWorker, para que la
// UI nunca sepa cuál respondió:
//
//   1. Índice del sistema -- scripts/search-index.sh (tracker3 -> plocate ->
//      locate). Rápido, NO recorre disco, devuelve rutas ABSOLUTAS.
//   2. SearchWorker recursivo (C++), SOLO si el script sale con código 2
//      (ningún índice instalado): recorre desde `fallbackRoot`, rutas
//      RELATIVAS a esa carpeta. Es el modo degradado -- mismo resultado que
//      antes de esta fase.
//
// Las entradas indexadas llevan {type,name(basename),path,parent,...} con ruta
// absoluta; las del fallback conservan {type,name(relativo),...}. Utils
// .entryPath() unifica ambas para el resto del código (miniaturas, abrir...).
//
// El orden de relevancia lo aplica aquí _rank() (no el script ni sortOps):
// exacto > prefijo > subcadena > solo-en-ruta; a igualdad, ruta más corta y
// luego alfabético. Es lo que espera Nautilus/Spotlight: lo más "cercano" al
// término, arriba.
Item {
  id: backend

  // Ruta absoluta al script de índice. La fija el llamador (logic/, que sí
  // conoce Paths) para no acoplar services/ a state/.
  property string indexScript: ""

  signal results(var entries, bool truncated)

  readonly property int maxResults: 200

  property string _query: ""
  property string _root: ""
  property bool _hidden: false

  // Coalescing de la consulta EN VUELO. ProcessRunner.start() se niega si ya hay
  // un proceso vivo (devuelve false), así que teclear rápido perdería las
  // búsquedas intermedias mientras el plocate del primer prefijo (cientos de
  // `stat` en bash, ~200ms) sigue corriendo. En vez de encolar, guardamos SOLO
  // la consulta más reciente y cancelamos la actual; al morir (onFinished) se
  // relanza la pendiente. Resultado: "buscar según tecleas" fluido, sin acumular
  // procesos ni bloquear -- es lo que pedía el encargo ("cancelar búsquedas
  // anteriores, sin bloquear la UI").
  property bool _pending: false
  property string _pendingQuery: ""
  property string _pendingRoot: ""
  property bool _pendingHidden: false

  function search(query, showHidden, fallbackRoot) {
    if (indexProc.busy) {
      _pending = true
      _pendingQuery = query
      _pendingRoot = fallbackRoot
      _pendingHidden = showHidden
      indexProc.cancel() // el relanzado ocurre en onFinished(cancelled)
      recursive.cancel()
      return
    }
    _startNow(query, showHidden, fallbackRoot)
  }

  function _startNow(query, showHidden, fallbackRoot) {
    recursive.cancel() // corta cualquier fallback recursivo aún en curso
    _query = query
    _root = fallbackRoot
    _hidden = showHidden
    // Pedimos maxResults+1 al script para poder marcar truncated con exactitud
    // (él sobre-pide internamente para compensar el filtrado de ruido/ocultos).
    indexProc.start([indexScript, query, String(maxResults + 1), showHidden ? "1" : "0"])
  }

  function cancel() {
    _pending = false
    indexProc.cancel()
    recursive.cancel()
  }

  ProcessRunner {
    id: indexProc
    onFinished: function (result) {
      if (backend._pending) {
        // Se canceló para relanzar con la consulta más reciente (coalescing).
        backend._pending = false
        backend._startNow(backend._pendingQuery, backend._pendingHidden, backend._pendingRoot)
        return
      }
      if (result.cancelled)
        return
      if (result.exitCode === 2) {
        // Ningún índice instalado -> recursivo desde la carpeta actual.
        recursive.search(backend._root, backend._query, backend._hidden)
        return
      }
      var parsed = backend._rank(String(result.stdout || ""), backend._query)
      backend.results(parsed.entries, parsed.truncated)
    }
  }

  SearchWorker {
    id: recursive
    // Modo degradado: se re-emite tal cual (rutas relativas, sin re-ordenar).
    onResults: function (entries, truncated) {
      backend.results(entries, truncated)
    }
  }

  // Parsea el TSV del script ("tipo\tRUTA_ABSOLUTA" por línea) y lo ordena por
  // relevancia. Devuelve {entries, truncated}.
  function _rank(stdout, query) {
    var q = query.toLowerCase()
    var lines = stdout.split("\n")
    var scored = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line === "")
        continue
      var tab = line.indexOf("\t")
      if (tab < 0)
        continue
      var type = line.substring(0, tab)
      var path = line.substring(tab + 1)
      var slash = path.lastIndexOf("/")
      var name = slash >= 0 ? path.substring(slash + 1) : path
      var parent = slash > 0 ? path.substring(0, slash) : "/"
      var lname = name.toLowerCase()
      var score = 3
      if (lname === q)
        score = 0
      else if (lname.indexOf(q) === 0)
        score = 1
      else if (lname.indexOf(q) >= 0)
        score = 2
      scored.push({
        "type": type,
        "name": name,
        "path": path,
        "parent": parent,
        "size": 0,
        "mtime": 0,
        "link": false,
        "_score": score,
        "_len": path.length
      })
    }
    scored.sort(function (a, b) {
      if (a._score !== b._score)
        return a._score - b._score
      if (a._len !== b._len)
        return a._len - b._len
      return a.name.localeCompare(b.name)
    })
    var truncated = scored.length > backend.maxResults
    return {
      "entries": scored.slice(0, backend.maxResults),
      "truncated": truncated
    }
  }
}

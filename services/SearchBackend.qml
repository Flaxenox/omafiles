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

  // Ruta absoluta al script de índice de NOMBRES. La fija el llamador (logic/,
  // que sí conoce Paths) para no acoplar services/ a state/.
  property string indexScript: ""
  // Script de búsqueda por CONTENIDO (ripgrep). Cuarto backend, se dispara con
  // el prefijo `content:` en la consulta (Fase 26 / Beta 3).
  property string contentScript: ""

  signal results(var entries, bool truncated)

  readonly property int maxResults: 200

  property string _query: ""
  property string _root: ""
  property bool _hidden: false
  // "name" (índice/recursivo) o "content" (ripgrep) -- fija el parseo y si hay
  // fallback recursivo (solo en name).
  property string _mode: "name"

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
    // Modo CONTENIDO: prefijo `content:`. El término va detrás, sin comillas
    // envolventes (`content:"foo bar"` -> foo bar). Busca DENTRO de los ficheros
    // del árbol de fallbackRoot (la carpeta actual), como `rg` en su cwd.
    if (query.indexOf("content:") === 0) {
      _mode = "content"
      var term = query.substring(8)
      if ((term.charAt(0) === '"' && term.charAt(term.length - 1) === '"')
          || (term.charAt(0) === "'" && term.charAt(term.length - 1) === "'"))
        term = term.substring(1, term.length - 1)
      if (term.length < 2) { // término muy corto: nada que buscar todavía
        backend.results([], false)
        return
      }
      indexProc.start([contentScript, term, fallbackRoot, String(maxResults + 1)])
      return
    }
    // Modo NOMBRE (índice del sistema). Pedimos maxResults+1 para marcar
    // truncated con exactitud (el script sobre-pide para compensar el filtrado).
    _mode = "name"
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
        // Sin backend disponible. En NOMBRE: recursivo desde la carpeta actual.
        // En CONTENIDO: ripgrep no instalado, no hay fallback -> vacío.
        if (backend._mode === "content")
          backend.results([], false)
        else
          recursive.search(backend._root, backend._query, backend._hidden)
        return
      }
      var parsed = backend._mode === "content"
        ? backend._parseContent(String(result.stdout || ""))
        : backend._rank(String(result.stdout || ""), backend._query)
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

  // Parsea el TSV de content-search.sh ("RUTA\tLINEA\tSNIPPET" por línea). El
  // orden lo da ripgrep (recorrido del árbol); no se re-ordena. Cada línea es un
  // resultado independiente (un mismo fichero aparece una vez por coincidencia,
  // con su línea) -> saltar a esa línea concreta. Lleva {line, snippet} extra.
  function _parseContent(stdout) {
    var lines = stdout.split("\n")
    var out = []
    for (var i = 0; i < lines.length && out.length < maxResults; i++) {
      var line = lines[i]
      if (line === "")
        continue
      var t1 = line.indexOf("\t")
      if (t1 < 0)
        continue
      var t2 = line.indexOf("\t", t1 + 1)
      if (t2 < 0)
        continue
      var path = line.substring(0, t1)
      var lineNo = parseInt(line.substring(t1 + 1, t2), 10) || 0
      var snippet = line.substring(t2 + 1)
      var slash = path.lastIndexOf("/")
      out.push({
        "type": "file",
        "name": slash >= 0 ? path.substring(slash + 1) : path,
        "path": path,
        "parent": slash > 0 ? path.substring(0, slash) : "/",
        "size": 0,
        "mtime": 0,
        "link": false,
        "line": lineNo,
        "snippet": snippet
      })
    }
    var truncated = out.length >= maxResults
    return { "entries": out, "truncated": truncated }
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

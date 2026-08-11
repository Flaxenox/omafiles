import QtQuick
import qs.Commons
import "../Utils.js" as Utils
import "../state"
import "../services"

// Acciones definidas por el usuario (Fase 26 / Beta 3): comandos propios que
// se leen de ~/.config/omarchy/omafiles/actions.toml y aparecen tanto en la
// paleta de comandos como en el menú contextual de ítems. Es la vía de escape
// para todo lo que el gestor no trae de serie (abrir en tu editor, optimizar
// una imagen, convertir, subir a algún sitio...) sin tener que tocar el código.
//
// Formato del fichero (subconjunto estricto de TOML, una tabla por acción):
//
//   [[action]]
//   label   = "Abrir en VS Code"
//   command = "code {path}"
//   context = "any"           # opcional: any | file | dir  (por defecto any)
//
// Placeholders sustituidos en `command` (cada uno se entrecomilla para bash,
// así que rutas con espacios/comillas no rompen nada):
//   {path}   ruta absoluta del PRIMER ítem seleccionado
//   {name}   basename del primer ítem
//   {ext}    extensión del primer ítem (sin punto)
//   {dir}    carpeta que contiene al primer ítem
//   {paths}  todas las rutas seleccionadas, separadas por espacio
//
// El comando resultante se lanza con `bash -lc` en modo dispara-y-olvida
// (Detached): las acciones suelen abrir apps GUI o herramientas CLI que
// producen ficheros; no seguimos su salida. Se recargan solas al abrir la
// paleta o el menú (CommandFacade llama a reload()), así que editar el .toml
// no requiere reiniciar la app.
Item {
  property Item root: null

  // Lista parseada: [{label, command, context}]. La rellena reload().
  property var actions: []

  Component.onCompleted: reload()

  // Relee y reparsea el fichero. Barato (fichero diminuto, lectura síncrona) y
  // solo se llama al abrir la paleta/menú, no por cada tecla.
  function reload() {
    var text = _readFile(Paths.actionsFile)
    actions = _parse(text)
  }

  // Lectura file:// síncrona (mismo patrón que qs.Commons/ThemeSource, con
  // QML_XHR_ALLOW_FILE_READ activado en main.cpp). "" si no existe -> sin
  // acciones, sin ruido: el fichero es opcional.
  function _readFile(path) {
    try {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", "file://" + path, false)
      xhr.send()
      return (xhr.status === 0 || xhr.status === 200) ? String(xhr.responseText || "") : ""
    } catch (e) {
      return ""
    }
  }

  // Parser TOML mínimo: solo `[[action]]` (array de tablas) y claves de
  // valor-cadena (label/command/context) entre comillas dobles o simples.
  // Ignora comentarios (#) y líneas en blanco. No es un TOML general -- es
  // deliberadamente estricto para el único esquema que soportamos.
  function _parse(text) {
    var out = []
    var cur = null
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "" || line.charAt(0) === "#")
        continue
      if (line === "[[action]]") {
        cur = { "label": "", "command": "", "context": "any" }
        out.push(cur)
        continue
      }
      if (!cur)
        continue
      var eq = line.indexOf("=")
      if (eq < 0)
        continue
      var key = line.substring(0, eq).trim()
      var raw = line.substring(eq + 1).trim()
      // quita comentario final solo si va fuera de comillas (caso simple:
      // el valor SIEMPRE va entrecomillado, así que un # tras la comilla de
      // cierre es comentario).
      var val = _unquote(raw)
      if (key === "label" || key === "command" || key === "context")
        cur[key] = val
    }
    // Descarta entradas incompletas (sin label o sin command no sirven).
    return out.filter(function (a) { return a.label !== "" && a.command !== "" })
  }

  // Extrae el contenido de un valor "..." o '...'; si no está entrecomillado,
  // devuelve el token tal cual hasta el primer espacio/# (tolerante).
  function _unquote(raw) {
    if (raw.length >= 2) {
      var q = raw.charAt(0)
      if (q === '"' || q === "'") {
        var end = raw.indexOf(q, 1)
        if (end > 0)
          return raw.substring(1, end)
      }
    }
    var hash = raw.indexOf("#")
    return (hash >= 0 ? raw.substring(0, hash) : raw).trim()
  }

  // ¿Aplica esta acción a la selección actual? "any" siempre; "file"/"dir"
  // solo si TODOS los seleccionados son de ese tipo (y hay al menos uno).
  function _matches(context, entries) {
    if (!context || context === "any")
      return true
    if (entries.length === 0)
      return false
    if (context === "file")
      return entries.every(function (e) { return e.type !== "dir" })
    if (context === "dir")
      return entries.every(function (e) { return e.type === "dir" })
    return true
  }

  // Sustituye los placeholders y lanza el comando. `entries` es la selección
  // (puede estar vacía para acciones "any" que solo usan {dir}).
  function run(action, entries) {
    var first = entries.length > 0 ? entries[0] : null
    var firstPath = first ? Utils.entryPath(NavState.currentPath, first) : NavState.currentPath
    var firstDir = firstPath.substring(0, firstPath.lastIndexOf("/")) || "/"
    var name = first ? first.name : ""
    var dot = name.lastIndexOf(".")
    var ext = dot > 0 ? name.substring(dot + 1) : ""
    var allPaths = entries.map(function (e) { return Util.shellQuote(Utils.entryPath(NavState.currentPath, e)) }).join(" ")

    var cmd = String(action.command)
      .split("{paths}").join(allPaths)
      .split("{path}").join(Util.shellQuote(firstPath))
      .split("{name}").join(Util.shellQuote(name))
      .split("{ext}").join(Util.shellQuote(ext))
      .split("{dir}").join(Util.shellQuote(first ? firstDir : NavState.currentPath))

    // cd a la carpeta del ítem (o a la actual) para que la salida relativa del
    // comando aterrice donde el usuario espera, igual que "Terminal here".
    var cwd = first ? firstDir : NavState.currentPath
    Detached.run(["bash", "-lc", "cd -- " + Util.shellQuote(cwd) + " && " + cmd])
    Notifier.notify("Running: " + action.label)
  }

  // Entradas para la PALETA (forma {label, run}). entries = selección actual.
  function paletteEntries(entries) {
    return actions.filter(function (a) { return _matches(a.context, entries) })
      .map(function (a) {
        return { "label": a.label, "run": function () { run(a, entries) } }
      })
  }

  // Acciones para el MENÚ CONTEXTUAL de ítems (forma {label, action}).
  function menuActions(entries) {
    return actions.filter(function (a) { return _matches(a.context, entries) })
      .map(function (a) {
        return { "label": a.label, "action": function () { run(a, entries) } }
      })
  }
}

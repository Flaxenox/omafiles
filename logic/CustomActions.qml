import QtQuick
import qs.Commons
import "../shared/Utils.js" as Utils
import "../state"
import Omafiles.Backend as Backend

// User-defined actions (Phase 26 / Beta 3): custom commands that
// are read from ~/.config/omafiles/actions.toml and appear both in the
// command palette and in the item context menu. It is the escape hatch
// for everything the manager does not ship out of the box (open in your editor, optimize
// an image, convert, upload somewhere...) without having to touch the code.
//
// File format (strict subset of TOML, one table per action):
//
//   [[action]]
//   label   = "Open in VS Code"
//   command = "code {path}"
//   context = "any"           # optional: any | file | dir  (default any)
//
// Placeholders substituted in `command` (each one is quoted for bash,
// so paths with spaces/quotes do not break anything):
//   {path}   absolute path of the FIRST selected item
//   {name}   basename of the first item
//   {ext}    extension of the first item (without the dot)
//   {dir}    folder that contains the first item
//   {paths}  all the selected paths, space-separated
//
// The resulting command is launched with `bash -lc` in fire-and-forget mode
// (Detached): the actions usually open GUI apps or CLI tools that
// produce files; we do not follow their output. They reload on their own on opening
// the palette or the menu (CommandFacade calls reload()), so editing the .toml
// does not require restarting the app.
Item {
  property Item root: null

  // Parsed list: [{label, command, context}]. reload() fills it.
  property var actions: []

  Component.onCompleted: reload()

  // Re-reads and re-parses the file. Cheap (tiny file, synchronous read) and
  // only called on opening the palette/menu, not per keystroke.
  function reload() {
    var text = _readFile(Paths.actionsFile)
    actions = _parse(text)
  }

  // Synchronous file:// read (same pattern as qs.Commons/ThemeSource, with
  // QML_XHR_ALLOW_FILE_READ enabled in main.cpp). "" if it does not exist -> no
  // actions, no noise: the file is optional.
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

  // Minimal TOML parser: only `[[action]]` (array of tables) and
  // string-value keys (label/command/context) in double or single quotes.
  // Ignores comments (#) and blank lines. It is not a general TOML -- it is
  // deliberately strict for the only schema we support.
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
      // strips the trailing comment only if it is outside quotes (simple case:
      // the value is ALWAYS quoted, so a # after the closing
      // quote is a comment).
      var val = _unquote(raw)
      if (key === "label" || key === "command" || key === "context")
        cur[key] = val
    }
    // Discards incomplete entries (without label or without command are useless).
    return out.filter(function (a) { return a.label !== "" && a.command !== "" })
  }

  // Extracts the content of a "..." or '...' value; if it is not quoted,
  // returns the token as is up to the first space/# (tolerant).
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

  // Does this action apply to the current selection? "any" always; "file"/"dir"
  // only if ALL the selected are of that type (and there is at least one).
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

  // Substitutes the placeholders and launches the command. `entries` is the selection
  // (may be empty for "any" actions that only use {dir}).
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

    // cd to the item's folder (or the current one) so the command's relative
    // output lands where the user expects, like "Terminal here".
    var cwd = first ? firstDir : NavState.currentPath
    Backend.Detached.run(["bash", "-lc", "cd -- " + Util.shellQuote(cwd) + " && " + cmd])
    Backend.Notifier.notify("Running: " + action.label)
  }

  // Entries for the PALETTE (form {label, run}). entries = current selection.
  function paletteEntries(entries) {
    return actions.filter(function (a) { return _matches(a.context, entries) })
      .map(function (a) {
        return { "label": a.label, "run": function () { run(a, entries) } }
      })
  }

  // Actions for the item CONTEXT MENU (form {label, action}).
  function menuActions(entries) {
    return actions.filter(function (a) { return _matches(a.context, entries) })
      .map(function (a) {
        return { "label": a.label, "action": function () { run(a, entries) } }
      })
  }
}

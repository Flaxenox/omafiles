pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Theme source of the Qt6 frontend (Phase 17, josema). SYSTEM PARITY, not
// of a specific theme: instead of fixed colors, it reads EXACTLY the same
// sources as the real Omarchy qs.Commons —
//   ~/.local/state/omarchy/current/theme/colors.toml  (foundational palette)
//   ~/.local/state/omarchy/current/theme/shell.toml    (surfaces/typography)
//   ~/.config/omarchy/shell.toml                        (machine override)
// — replicating its parsing (loadColors/parseShell of Color.qml). A Timer
// polls the files and, if they change, reloads: on switching theme in Omarchy,
// the standalone Qt6 follows it LIVE just like Quickshell (which uses FileView).
// Quickshell.Io doesn't exist here; a synchronous XMLHttpRequest reads the
// local files (they're ~KB, polled every 1.5 s: negligible cost).
//
// Color.qml and Style.qml (the stubs) DERIVE from this singleton; they fix nothing.
QtObject {
  id: src

  readonly property string home: Backend.Env.get("HOME")
  readonly property string themeDir: home + "/.local/state/omarchy/current/theme"
  readonly property string colorsPath: themeDir + "/colors.toml"
  readonly property string shellPath: themeDir + "/shell.toml"
  readonly property string userShellPath: home + "/.config/omarchy/shell.toml"

  // Foundational palette (colors.toml). Fallbacks = those of the real Color.qml.
  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"
  property color muted: "#707880"

  // Dict "section.key" -> raw string (theme shell.toml + user override
  // merged). Reassigning it whole is what makes the Color/Style
  // bindings re-evaluate, same as in the real one.
  property var shellValues: ({})

  // Synchronous reading of a local file; "" if it doesn't exist.
  function _read(path) {
    try {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", "file://" + path, false)
      xhr.send()
      return (xhr.status === 0 || xhr.status === 200) ? String(xhr.responseText || "") : ""
    } catch (e) {
      return ""
    }
  }

  // --- parsing parity with the real Color.qml -------------------------------
  function _loadColors(raw) {
    var lines = String(raw || "").split("\n")
    var fg = "", bg = "", acc = "", mut = "", urg = ""
    var c0 = "", c1 = "", c4 = "", c7 = "", c8 = ""
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!m) continue
      var k = m[1], val = m[2]
      if (k === "foreground") fg = val
      else if (k === "background") bg = val
      else if (k === "accent") acc = val
      else if (k === "muted") mut = val
      else if (k === "color0") c0 = val
      else if (k === "color4") c4 = val
      else if (k === "color7") c7 = val
      else if (k === "color8") c8 = val
      else if (k === "red" || k === "color1") urg = val
    }
    if (fg) foreground = fg; else if (c7) foreground = c7
    if (bg) background = bg; else if (c0) background = c0
    if (acc) accent = acc; else if (c4) accent = c4
    muted = mut ? mut : (c8 ? c8 : foreground)
    if (urg) urgent = urg
  }

  function _parseShell(raw) {
    var parsed = ({})
    var text = String(raw || "")
    var lines = text.split("\n")
    var section = ""
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/^\s+|\s+$/g, "")
      if (!line || line.charAt(0) === "#") continue
      var sm = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
      if (sm) { section = sm[1]; continue }
      var kv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/)
        || line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
        || line.match(/^([A-Za-z0-9_-]+)\s*=\s*([A-Za-z][A-Za-z0-9_.-]*)\s*(#.*)?$/)
      if (!kv || !section) continue
      parsed[section + "." + kv[1]] = kv[2]
    }
    return parsed
  }

  property string _lastRaw: ""
  function _reload() {
    var colorsRaw = _read(colorsPath)
    var shellRaw = _read(shellPath)
    var userRaw = _read(userShellPath)
    var combined = colorsRaw + "" + shellRaw + "" + userRaw
    if (combined === _lastRaw)
      return
    _lastRaw = combined
    _loadColors(colorsRaw)
    var merged = ({})
    var themeDict = _parseShell(shellRaw)
    var userDict = _parseShell(userRaw)
    for (var tk in themeDict) merged[tk] = themeDict[tk]
    for (var uk in userDict) merged[uk] = userDict[uk]
    shellValues = merged // whole reassignment -> re-evaluates bindings
  }

  // Polling of the active theme: on switching theme in Omarchy (or running
  // `omarchy display text size`), the standalone picks it up in <=1.5 s.
  property Timer _poll: Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: src._reload()
  }

  Component.onCompleted: _reload()
}

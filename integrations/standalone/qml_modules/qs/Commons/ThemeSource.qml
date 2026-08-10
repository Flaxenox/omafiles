pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Fuente de tema del frontend Qt6 (Fase 17, josema). PARIDAD DE SISTEMA, no
// de un tema concreto: en lugar de colores fijos, lee EXACTAMENTE las mismas
// fuentes que el qs.Commons real de Omarchy —
//   ~/.local/state/omarchy/current/theme/colors.toml  (paleta fundacional)
//   ~/.local/state/omarchy/current/theme/shell.toml    (superficies/tipografía)
//   ~/.config/omarchy/shell.toml                        (override de máquina)
// — replicando su parseo (loadColors/parseShell de Color.qml). Un Timer
// sondea los ficheros y, si cambian, recarga: al cambiar de tema en Omarchy,
// el standalone Qt6 lo sigue EN VIVO igual que Quickshell (que usa FileView).
// Quickshell.Io no existe aquí; XMLHttpRequest síncrono lee los ficheros
// locales (son ~KB, sondeo cada 1,5 s: coste despreciable).
//
// Color.qml y Style.qml (los stubs) DERIVAN de este singleton; no fijan nada.
QtObject {
  id: src

  readonly property string home: Backend.Env.get("HOME")
  readonly property string themeDir: home + "/.local/state/omarchy/current/theme"
  readonly property string colorsPath: themeDir + "/colors.toml"
  readonly property string shellPath: themeDir + "/shell.toml"
  readonly property string userShellPath: home + "/.config/omarchy/shell.toml"

  // Paleta fundacional (colors.toml). Fallbacks = los del Color.qml real.
  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"
  property color muted: "#707880"

  // Dict "seccion.clave" -> string crudo (shell.toml de tema + override de
  // usuario fusionados). Reasignarlo entero es lo que hace re-evaluar los
  // bindings de Color/Style, igual que en el real.
  property var shellValues: ({})

  // Lectura síncrona de un fichero local; "" si no existe.
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

  // --- paridad de parseo con Color.qml real -------------------------------
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
    shellValues = merged // reasignación entera -> re-evalúa bindings
  }

  // Sondeo del tema activo: al cambiar de tema en Omarchy (o ejecutar
  // `omarchy display text size`), el standalone lo recoge en <=1,5 s.
  property Timer _poll: Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: src._reload()
  }

  Component.onCompleted: _reload()
}

pragma Singleton
import QtQuick

// Color de qs.Commons para el frontend Qt6 (Fase 17, josema). Es el MISMO
// Color.qml real de Omarchy (misma resolución de superficies: pick/flatColor/
// composed + los QtObject por superficie), salvo que la paleta fundacional y
// el diccionario shellValues NO se leen aquí con Quickshell.Io/FileView sino
// que vienen de ThemeSource (que sí lee colors.toml/shell.toml y sondea los
// cambios). Así los componentes qs.Ui copiados del real renderizan idéntico a
// Quickshell y siguen el tema en vivo.
QtObject {
  id: root

  // Paleta fundacional (colors.toml) — vía ThemeSource.
  readonly property color foreground: ThemeSource.foreground
  readonly property color background: ThemeSource.background
  readonly property color accent: ThemeSource.accent
  readonly property color urgent: ThemeSource.urgent
  readonly property color muted: ThemeSource.muted

  // Dict "seccion.clave" -> string crudo (shell.toml) — vía ThemeSource.
  readonly property var shellValues: ThemeSource.shellValues

  // --- resolución de superficie (verbatim del Color.qml real) -------------
  function pick(key, fallback) {
    var v = shellValues[key]
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }
  function pickAlpha(key, fallback) {
    var v = shellValues[key]
    if (typeof v !== "string" || v.length === 0) return fallback
    var n = Number(v)
    if (!isFinite(n)) return fallback
    return Util.clampAlpha(n)
  }
  function firstColorToken(value) {
    var parts = String(value || "").replace(/^\s+|\s+$/g, "").split(/\s+/)
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i].match(/^-?\d+(?:\.\d+)?deg$/)) return parts[i]
    }
    return value
  }
  function flatColor(value, fallback) {
    var token = firstColorToken(value)
    var role = String(token || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    if (root.shellValues[role] && root.shellValues[role] !== token) return flatColor(root.shellValues[role], fallback)
    if (role === "foreground" || role === "text") return root.foreground
    if (role === "accent") return root.accent
    if (role === "urgent") return root.urgent
    if (role === "muted") return root.muted
    if (role === "background") return root.background
    if (role === "transparent") return Qt.rgba(0, 0, 0, 0)
    if (String(token || "").charAt(0) === "#") return token
    return fallback
  }
  function composed(colorKey, alphaKey, colorFallback, alphaFallback) {
    return Util.alpha(flatColor(pick(colorKey, colorFallback), colorFallback), pickAlpha(alphaKey, alphaFallback))
  }

  // --- superficies (las que usan Omafiles y sus componentes) --------------
  readonly property QtObject tooltip: QtObject {
    property color background: root.composed("tooltip.background", "tooltip.background-alpha", root.background, 1.0)
    property color text: root.pick("tooltip.text", root.foreground)
    property color border: root.composed("tooltip.border", "tooltip.border-alpha", root.foreground, 1.0)
  }
  readonly property QtObject menu: QtObject {
    property color background: root.composed("menu.background", "menu.background-alpha", root.background, 1.0)
    property color text: root.pick("menu.text", root.foreground)
    property color border: root.composed("menu.border", "menu.border-alpha", root.foreground, 1.0)
    property color scrim: root.composed("menu.scrim", "menu.scrim-alpha", root.background, 0.5)
    property color selectedBackground: root.composed("menu.selected-background", "menu.selected-background-alpha", root.foreground, 0.08)
    property color selectedText: root.pick("menu.selected-text", root.accent)
    property color selectedBorder: root.composed("menu.selected-border", "menu.selected-border-alpha", root.foreground, 0.0)
  }
}

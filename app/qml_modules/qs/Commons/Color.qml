pragma Singleton
import QtQuick

// qs.Commons Color for the Qt6 frontend. It's the SAME
// real Omarchy Color.qml (same surface resolution: pick/flatColor/
// composed + the per-surface QtObject), except that the foundational palette and
// the shellValues dictionary are NOT read here with Quickshell.Io/FileView but
// come from ThemeSource (which does read colors.toml/shell.toml and polls the
// changes). So the qs.Ui components copied from the real one render identical to
// Quickshell and follow the theme live.
QtObject {
  id: root

  // Foundational palette (colors.toml) — via ThemeSource.
  readonly property color foreground: ThemeSource.foreground
  readonly property color background: ThemeSource.background
  readonly property color accent: ThemeSource.accent
  readonly property color urgent: ThemeSource.urgent
  readonly property color muted: ThemeSource.muted

  // Dict "section.key" -> raw string (shell.toml) — via ThemeSource.
  readonly property var shellValues: ThemeSource.shellValues

  // --- surface resolution (verbatim from the real Color.qml) -------------
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

  // --- surfaces (the ones Omafiles and its components use) --------------
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

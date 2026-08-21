.pragma library

// Badge color for a resolved git-status letter (state/GitStatusState.qml's
// codeFor()). Local constants, not global Color/ThemeSource tokens: this
// is the first UI in the app needing a green/amber distinction and
// neither exists in the shared palette (only Color.urgent/Color.muted) --
// adding them there would be a theme-system change orthogonal to this
// feature. Reused by shared/FileRowVisual.qml and shared/FileGridCell.qml
// so the mapping only lives in one place.
function colorFor(status, urgentColor, mutedColor) {
  switch (status) {
    case "U": return urgentColor // conflict
    case "D": return urgentColor // deleted
    case "A": return "#6e9c5c"   // added (muted green)
    case "M": return "#c2984a"   // modified (muted amber)
    default: return mutedColor   // "?" untracked
  }
}

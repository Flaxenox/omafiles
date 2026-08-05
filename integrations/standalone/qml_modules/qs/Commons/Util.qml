pragma Singleton
import QtQuick

// Adaptador MÍNIMO de qs.Commons/Util.qml (Fase 4, josema) -- solo las
// 4 funciones que usa omafiles (shellQuote/fileUrl/alpha/wheelSteps),
// implementaciones directas sin las dependencias del real.
QtObject {
  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function fileUrl(path) {
    if (!path) return ""
    return path.indexOf("file://") === 0 ? path : "file://" + path
  }

  function alpha(color, opacity) {
    var c = (typeof color === "string") ? Qt.color(color) : color
    return Qt.rgba(c.r, c.g, c.b, opacity)
  }

  // Mismo contrato que el real: acumula angleDelta.y hasta superar 120
  // (un "notch" de rueda estándar) y devuelve cuántos pasos completos
  // caben, dejando el resto para la próxima llamada.
  function wheelSteps(accumulator, deltaY) {
    var total = accumulator + deltaY
    var steps = total / 120
    steps = steps >= 0 ? Math.floor(steps) : Math.ceil(steps)
    return { steps: steps, remainder: total - steps * 120 }
  }
}

pragma Singleton
import QtQuick

// Variante standalone de services/Notifier.qml (Fase 4, josema) -- sin
// notify-send vía Quickshell todavía; se queda en consola.
QtObject {
  function notify(text) {
    console.log("[standalone] Notifier.notify:", text)
  }
}

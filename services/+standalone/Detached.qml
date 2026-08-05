pragma Singleton
import QtQuick

// Variante standalone de services/Detached.qml (Fase 4, josema) -- sin
// Quickshell.execDetached() no hay forma de lanzar un proceso
// desatendido todavía; solo deja constancia en consola.
QtObject {
  function run(args) {
    console.warn("[standalone] Detached.run ignorado:", JSON.stringify(args))
  }
}

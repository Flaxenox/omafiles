pragma Singleton
import QtQuick

// Variante standalone de services/Env.qml (Fase 4, josema) -- a
// diferencia del resto de servicios en esta carpeta, ESTE sí es
// funcional de verdad: QML no tiene acceso nativo a variables de
// entorno (por eso Quickshell.env() existe), así que main.cpp expone
// HOME como context property (standaloneHomeDir) antes de cargar
// Main.qml. Solo cubre HOME -- es la única variable que usa el núcleo
// (ver homeDir en core/OmafilesContent.qml y state/TabsState.qml).
QtObject {
  function get(name) {
    if (name === "HOME") return standaloneHomeDir
    return ""
  }
}

pragma Singleton
import QtQuick

// Adaptador MÍNIMO de qs.Commons/Border.qml para el frontend standalone
// (Fase 4, josema) -- el real vive dentro de Quickshell (lee temas del
// usuario, gradientes, anchos por lado...); este solo expone la forma
// que consume omafiles: un "spec" simple {color, width} que
// integrations/standalone/qml_modules/qs/Ui/BorderSurface.qml sabe
// dibujar. Suficiente para el primer arranque, no para verse igual que
// bajo Quickshell.
QtObject {
  function flat(color, width) {
    return { color: color || "transparent", width: width === undefined ? 1 : width }
  }

  function none() {
    return { color: "transparent", width: 0 }
  }
}

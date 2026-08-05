pragma Singleton
import QtQuick

// Estado de "ver" un fichero: vista previa rápida (Espacio) y el selector
// de "Abrir con" -- séptimo singleton de la capa state/. Van juntos porque
// ambos son formas de interactuar con el ítem seleccionado y comparten
// sitios de llamada (ver logic/PreviewLoader.qml y logic/OpenWithOps.qml).
QtObject {
  property bool previewOpen: false
  property bool openWithOpen: false
  property var openWithApps: []
  property var openWithEntry: null
}

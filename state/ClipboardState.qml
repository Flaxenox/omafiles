pragma Singleton
import QtQuick

// Estado del portapapeles interno (copiar/cortar/pegar) -- segundo
// singleton de la capa state/, mismo patrón validado con
// SelectionState.qml (pragma Singleton + qmldir propio). La lógica que
// lo manipula sigue en logic/ClipboardOps.qml.
QtObject {
  property var clipboardPaths: []
  property string clipboardMode: "" // "copy" | "cut"
}

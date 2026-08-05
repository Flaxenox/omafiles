pragma Singleton
import QtQuick

// Feedback visual de "arrastrando por encima de..." durante un
// drag&drop -- decimoséptimo singleton de la capa state/. dropHoverIndex
// es para filas de la lista principal (FileListRow.qml, indexado por
// posición); dropHoverPath es para marcadores/unidades en la barra
// lateral (Sidebar.qml, indexado por ruta) -- dos formas del mismo
// concepto, con la clave que le encaja a cada UI.
QtObject {
  property int dropHoverIndex: -1
  property string dropHoverPath: ""
}

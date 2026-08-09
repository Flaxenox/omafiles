pragma Singleton
import QtQuick

// Criterio de orden actual (nombre/tamaño/fecha/tipo, asc/desc) --
// decimotercer singleton de la capa state/, completa la migración de
// logic/SortOps.qml (su lógica ya estaba extraída; este era el único
// estado que manipulaba y que seguía viviendo en Omafiles.qml).
QtObject {
  property string sortKey: "name"
  property bool sortDesc: false

  // Claves de orden disponibles y sus etiquetas (Fase 14.B, josema, cierra
  // O2/O3 de la revalidación): eran constantes readonly de OmafilesContent
  // (sortKeys/sortKeyLabels) leídas por logic/SortOps. Configuración de
  // orden pura -- su sitio natural es junto a sortKey/sortDesc.
  readonly property var sortKeys: ["name", "size", "mtime", "type"]
  readonly property var sortKeyLabels: ({ name: "Name", size: "Size", mtime: "Date", type: "Type" })
}

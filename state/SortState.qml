pragma Singleton
import QtQuick

// Criterio de orden actual (nombre/tamaño/fecha/tipo, asc/desc) --
// decimotercer singleton de la capa state/, completa la migración de
// logic/SortOps.qml (su lógica ya estaba extraída; este era el único
// estado que manipulaba y que seguía viviendo en Omafiles.qml).
QtObject {
  property string sortKey: "name"
  property bool sortDesc: false
}

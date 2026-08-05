pragma Singleton
import QtQuick

// Modo "dentro de un archivo" (.zip/.7z/.rar/.tar navegado sin extraer)
// -- vigésimo singleton de la capa state/, completa
// logic/ArchiveActions.qml. Leído como guarda ("if (inArchive) return")
// por casi todas las operaciones de fichero -- no tiene sentido
// renombrar/borrar/copiar/etc. dentro de un archivo sin extraer primero.
QtObject {
  property bool inArchive: false
  property string archivePath: ""
  property string archiveSubPath: ""
}

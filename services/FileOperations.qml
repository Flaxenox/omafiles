pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Operaciones de fichero -- adaptador fino sobre el singleton C++
// Omafiles.Backend.FileOperations (QFile/QDir, ver backend/FileOperations.
// cpp). Fase 7 (josema): backend nativo introducido; de momento solo
// "nueva carpeta" (mkdir) lo consume en vivo (ver logic/RenameOps.qml).
//
// Reenvia las llamadas y re-emite progress/finished/error para que logic/
// no importe Omafiles.Backend (regla 8). Integra Notifier (req 4): un
// error se avisa aqui, en un solo sitio, con el mismo texto que daba
// ActionEngine ("Action failed: ..."). El refresco tras la operacion NO se
// dispara aqui -- lo hace el QFileSystemWatcher de DirectoryModel (Fase
// 6.D) al cambiar el directorio activo.
QtObject {
  id: fileOps
  signal progress(string op, string path, var done, var total)
  signal finished(string op, string path)
  signal error(string op, string path, string message)

  function copy(source, destination, overwrite) { Backend.FileOperations.copy(source, destination, overwrite === true) }
  function move(source, destination, overwrite) { Backend.FileOperations.move(source, destination, overwrite === true) }
  function rename(path, newName) { Backend.FileOperations.rename(path, newName) }
  function remove(path, ignoreMissing) { Backend.FileOperations.remove(path, ignoreMissing === true) }
  function mkdir(path) { Backend.FileOperations.mkdir(path) }
  function trash(path) { Backend.FileOperations.trash(path) }
  function restore(path) { Backend.FileOperations.restore(path) }
  // Restaura por ruta original (Fase 13.E): busca el .trashinfo correcto en
  // todas las papeleras. Emite finished("restore", origPath) / error.
  function restoreByOrigPath(origPath) { Backend.FileOperations.restoreByOrigPath(origPath) }

  // Listado nativo de la Papelera (Fase 16): raíces XDG activas y metadatos
  // de los .trashinfo. Sustituyen a trash-roots.sh / trash-info.sh; síncronos.
  function trashRoots() { return Backend.FileOperations.trashRoots() }
  function trashInfo() { return Backend.FileOperations.trashInfo() }
  // Cancela la operación en curso (Fase 13.A). El worker aborta y emite
  // error "cancelled", que onError NO notifica (es una cancelación pedida
  // por el usuario, no un fallo).
  function cancel() { Backend.FileOperations.cancel() }

  // Detección de conflictos nativa (Fase 13.F): subconjunto de `paths` que ya
  // existen. Síncrona; sustituye a los `test -e` de shell en paste/drop.
  function existingPaths(paths) { return Backend.FileOperations.existingPaths(paths) }

  // Tamaño total (bytes) de un conjunto de rutas (Fase 13.G): para el
  // porcentaje de progreso de copy/move sin `du` y el tamaño de una selección
  // múltiple en Properties (BUG-03).
  function totalSize(paths) { return Backend.FileOperations.totalSize(paths) }

  // Modo octal (%a) de cada ruta, en el mismo orden (BUG-03): para prefijar el
  // diálogo de chmod de una selección múltiple sin `stat -c%a -- ...`.
  function octalModes(paths) { return Backend.FileOperations.octalModes(paths) }

  // Cualificado con el id: Backend.FileOperations (el target) tiene señales
  // del mismo nombre; sin el id, re-emitir podría resolverse al signal del
  // propio target en vez del de este adaptador (misma clase de colisión que
  // hubo en DirLister.directoryChanged).
  property Connections _backend: Connections {
    target: Backend.FileOperations
    function onProgress(op, path, done, total) { fileOps.progress(op, path, done, total) }
    function onFinished(op, path) { fileOps.finished(op, path) }
    function onError(op, path, message) {
      // "cancelled" = cancelación pedida por el usuario (FileOperations.
      // cancel), no un fallo: no se avisa. El consumidor (ActionEngine) ya
      // limpia el estado y el destino parcial. Fase 13.A.
      if (message !== "cancelled")
        Backend.Notifier.notify("Action failed: " + message)
      fileOps.error(op, path, message)
    }
  }
}

pragma Singleton
import QtQuick

// Estado del motor de acciones (runAction/cancelAction/progreso de
// copia/movimiento) -- duodécimo singleton de la capa state/, completa
// la migración de logic/ActionEngine.qml (cuyo undoStack/redoStack ya
// viven en state/UndoState.qml). actionBusyDots se queda en Omafiles.qml
// a propósito -- es una animación puramente visual (un Timer en la propia
// UI), ActionEngine.qml no la lee ni la escribe.
QtObject {
  property bool actionBusy: false
  property string actionLabel: ""
  // -1 = sin progreso que mostrar (renombrar/chmod/comprimir...), solo
  // copiar/mover lo rellenan de verdad -- ver startCopyProgress().
  property real actionProgressPct: -1
  property real actionTotalBytes: 0
  property var actionProgressDestPaths: []
  // Callback pendiente del runAction en curso -- ver actionProc.onExited
  // en ActionEngine.qml.
  property var _actionOnSuccess: null
  // true mientras se procesa un cancelAction() explícito -- evita que
  // actionProc.onExited muestre "Action failed" por un proceso que el
  // propio usuario mandó parar.
  property bool _actionCancelled: false
}

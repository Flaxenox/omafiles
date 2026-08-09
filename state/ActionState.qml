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
  // Callback pendiente del runAction en curso -- ver actionProc.onFinished
  // en ActionEngine.qml. (_actionCancelled desapareció en la Fase 1.5:
  // ProcessRunner.finished ya lleva `cancelled` en el resultado, ver
  // services/ProcessRunner.qml.)
  property var _actionOnSuccess: null
}

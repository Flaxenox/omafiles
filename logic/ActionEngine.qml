import QtQuick
import qs.Commons
import "../state"
import "../services"

// El motor central de acciones de fichero (renombrar/borrar/copiar/mover/
// comprimir/extraer/chmod/enlace, todo pasa por aquí) + deshacer/rehacer +
// la barra de progreso de copias/movimientos -- decimotercer componente
// extraído de Omafiles.qml, y el de más impacto: docenas de funciones en
// Omafiles.qml (commitNewFolder, requestDelete, runPaste, runDrop,
// commitChmod, makeLinkFor, restoreFromTrash...) llaman a runAction()/
// pushUndo() como si fueran suyas. Cambiar los 50+ sitios de llamada
// habría sido mucho más riesgo que el beneficio -- en vez de eso, root
// conserva funciones-envoltorio de una línea (`function runAction(...) {
// return actionEngine.runAction(...) }`, ver junto a cada una en
// Omafiles.qml) que delegan aquí. Ningún sitio de llamada existente
// cambió.
Item {
  property Item root: null

  // Pila simple de acciones reversibles: renombrar, nueva carpeta/fichero,
  // borrar (a la papelera), mover (cortar+pegar/arrastrar), renombrado en
  // lote, chmod y enlace. Copiar/comprimir se quedan fuera a propósito --
  // deshacerlos es más ambiguo (¿borrar la copia? ¿y si ya se movió/editó?)
  // que perder por error algo renombrado/movido/borrado/con permisos
  // cambiados. undoStack/redoStack en sí viven en state/UndoState.qml
  // (singleton) -- solo estas tres funciones que las manipulan viven aquí.
  function pushUndo(label, undoFn, redoFn) {
    UndoState.undoStack = UndoState.undoStack.concat([{ label: label, undo: undoFn, redo: redoFn }]).slice(-20)
    UndoState.redoStack = []
  }

  function undoLast() {
    if (UndoState.undoStack.length === 0) return
    var entry = UndoState.undoStack[UndoState.undoStack.length - 1]
    UndoState.undoStack = UndoState.undoStack.slice(0, -1)
    // entry.undo() devuelve lo que runAction() devuelve: false si se
    // descartó por haber otra acción en curso. Antes esto decía "Undone"
    // pase lo que pase, incluso cuando el undo ni siquiera llegó a
    // lanzarse, Y la entrada se perdía de la pila igual. Ahora, si no
    // llegó a lanzarse, se devuelve a la pila para poder reintentarlo.
    var started = entry.undo()
    if (started === false) {
      UndoState.undoStack = UndoState.undoStack.concat([entry])
      Notifier.notify("Couldn't undo \"" + entry.label + "\": still busy with another action")
      return
    }
    // Solo pasa a la pila de redo si de verdad lleva forma de rehacerse
    // -- no todas las entradas del undoStack tienen redoFn (ver el
    // comentario junto a pushUndo).
    if (entry.redo) UndoState.redoStack = UndoState.redoStack.concat([entry]).slice(-20)
    Notifier.notify("Undoing: " + entry.label)
  }

  function redoLast() {
    if (UndoState.redoStack.length === 0) return
    var entry = UndoState.redoStack[UndoState.redoStack.length - 1]
    UndoState.redoStack = UndoState.redoStack.slice(0, -1)
    var started = entry.redo()
    if (started === false) {
      UndoState.redoStack = UndoState.redoStack.concat([entry])
      Notifier.notify("Couldn't redo \"" + entry.label + "\": still busy with another action")
      return
    }
    // De vuelta a undoStack SIN pasar por pushUndo() -- eso vaciaría
    // redoStack, que es justo lo que no queremos en pleno ciclo
    // deshacer/rehacer/deshacer.
    UndoState.undoStack = UndoState.undoStack.concat([entry]).slice(-20)
    Notifier.notify("Redoing: " + entry.label)
  }

  function runAction(cmd, busyLabel, onSuccess) {
    // actionProc es un único proceso compartido por todas las acciones de
    // fichero (renombrar, borrar, copiar/mover, comprimir...). Sin esta
    // guardia, una segunda llamada mientras la primera sigue en marcha
    // (doble clic, o una tecla de más durante una operación larga) le
    // cambiaba el comando y lo reiniciaba, cortando la operación en curso
    // a media copia sin ningún aviso.
    if (actionProc.busy || nativeBusy) {
      Notifier.notify("Still busy with the previous action — try again in a moment")
      return false
    }
    ActionState.actionLabel = busyLabel || ""
    ActionState.actionBusy = !!busyLabel
    ActionState._actionOnSuccess = onSuccess || null
    // group:true -- el comando corre en su propio grupo de procesos en vez
    // de compartir el de Quickshell. Sin esto, cancelAction() solo podría
    // matar el "bash -c" en sí -- cualquier cp/mv/zip que ese bash hubiera
    // lanzado como hijo se quedaba huérfano y seguía corriendo de fondo
    // como si nada, aunque la UI ya diera la acción por cancelada.
    actionProc.start(["bash", "-c", cmd], true)
    return true
  }

  // Une comandos de una operación por lotes (pegar/soltar/borrar N archivos,
  // renombrado masivo...) para que el fallo de uno no se coma los demás.
  // Antes se unían con "&&": en cuanto el ítem 2 de 5 fallaba (ya no
  // existía, permiso denegado...) los ítems 3-5 no se llegaban a intentar
  // y encima no había ningún aviso. Con esto se intentan todos, y si alguno
  // falla el proceso sale con estado != 0 para que actionProc lo reporte
  // (ver runAction/actionProc más arriba) -- sin decir cuál en concreto,
  // pero ya no se pierden en silencio.
  function chainCmds(cmds) {
    if (cmds.length <= 1) return cmds[0] || "true"
    return "st=0; " + cmds.map(function (c) { return "{ " + c + "; } || st=1" }).join("; ") + "; exit $st"
  }

  function cancelAction() {
    // Copia nativa en curso (Fase 13.A): cancelación cooperativa en C++. El
    // worker aborta entre trozos y emite error "cancelled" -> bad() ->
    // _nativeDone limpia estado y refresca. Aquí solo se pide la cancelación
    // y se borra el destino parcial (mismo criterio que la ruta shell: solo
    // si es UN único destino, ver más abajo).
    if (nativeBusy) {
      _cancelling = true
      FileOperations.cancel()
      if (ActionState.actionProgressDestPaths.length === 1)
        Detached.run(["rm", "-rf", "--", ActionState.actionProgressDestPaths[0]])
      return
    }
    // actionProc.cancel() manda la señal a TODO el grupo de procesos
    // (el "bash -c" + el cp/mv/zip real que esté corriendo dentro, ver
    // group:true en runAction()), no solo al primero.
    actionProc.cancel()
    // Cancelar a mitad de una copia/movimiento ENTRE DISCOS (mv no puede
    // hacer un rename atómico, así que copia y borra el origen) deja un
    // fichero parcial a medio escribir en el destino -- bug real
    // (josema: "cancelé al 30% y se quedó ese 30% de la peli"). Solo se
    // limpia cuando es UN único fichero/carpeta (actionProgressDestPaths
    // con 1 elemento): en un lote de varios, SIGTERM puede matar justo el
    // que estaba a medias mientras los anteriores ya habían terminado
    // bien -- borrar TODOS los destPaths a ciegas borraría también esos.
    if (ActionState.actionTotalBytes > 0 && ActionState.actionProgressDestPaths.length === 1) {
      Detached.run(["rm", "-rf", "--", ActionState.actionProgressDestPaths[0]])
    }
    ActionState.actionBusy = false
    ActionState.actionLabel = ""
    ActionState.actionProgressPct = -1
    root.refresh()
    root.refreshTick += 1
  }

  // Lanza el sondeo de progreso para una copia/movimiento -- llamar justo
  // antes de runAction() con los mismos origen/destino. Sin esto
  // actionProgressPct se queda en -1 (sin barra, solo puntos animados)
  // para cualquier otra acción, que es lo que queremos: chmod/comprimir/
  // renombrar no tienen un "tamaño total" que tenga sentido mostrar así.
  function startCopyProgress(sourcePaths, destPaths) {
    ActionState.actionProgressPct = 0
    ActionState.actionTotalBytes = 0
    ActionState.actionProgressDestPaths = destPaths
    var quoted = sourcePaths.map(function (p) { return Util.shellQuote(p) }).join(" ")
    actionProgressTotalProc.start(["bash", "-c", "du -sbc -- " + quoted + " | tail -n1 | cut -f1"])
  }

  // ---------- Copiar/mover nativo (Fase 13.A copy, 13.B move) ----------
  // Reemplaza el `cp -r`/`mv` de shell (runPaste/runDrop) por
  // FileOperations.copy/move (C++: recursivo, symlinks como symlinks,
  // preserva permisos, progreso por bytes, rename atómico + fallback cross-fs
  // en move). MANTIENE exactamente el mismo comportamiento observable que la
  // ruta shell: mismo estado de ocupado (actionBusy/actionLabel), misma barra
  // de progreso (startCopyProgress, sondeo `du` sobre destinos), misma
  // cancelación (cancelAction), mismo refresco. Secuencial (uno a la vez)
  // para conservar la semántica del chainCmds anterior: si uno falla se avisa
  // (una sola vez, en services/FileOperations) y se para. `overwrite` = el
  // diálogo eligió sobrescribir (antes `-f`; sin él, `-n`).
  property bool nativeBusy: false
  property string _nativeKind: "copy"
  property var _batchQueue: []
  property int _batchIdx: 0
  property bool _batchOverwrite: false
  property var _batchOnDone: null
  property bool _cancelling: false

  function runNativeCopy(pairs, busyLabel, overwrite, onDone) {
    return _runNative("copy", pairs, busyLabel, overwrite, onDone)
  }

  function runNativeMove(pairs, busyLabel, overwrite, onDone) {
    return _runNative("move", pairs, busyLabel, overwrite, onDone)
  }

  // Borrado permanente nativo (Fase 13.C): `paths` es una lista de rutas
  // (no pares). ignoreMissing = semántica `rm -f` (no es error que falte).
  // El único llamador (borrado permanente desde la Papelera) pasa
  // busyLabel="" -> sin barra de progreso, como el `rm -rf` anterior.
  function runNativeRemove(paths, busyLabel, ignoreMissing, onDone) {
    var pairs = paths.map(function (p) { return { src: p } })
    return _runNative("remove", pairs, busyLabel, ignoreMissing, onDone)
  }

  function _runNative(kind, pairs, busyLabel, overwrite, onDone) {
    if (actionProc.busy || nativeBusy) {
      Notifier.notify("Still busy with the previous action — try again in a moment")
      return false
    }
    nativeBusy = true
    _cancelling = false
    _nativeKind = kind
    _batchQueue = pairs
    _batchIdx = 0
    _batchOverwrite = overwrite === true
    _batchOnDone = onDone || null
    ActionState.actionLabel = busyLabel || ""
    ActionState.actionBusy = !!busyLabel
    // Sin barra de progreso para operaciones sin etiqueta (undo/redo del
    // movimiento) -- igual que la ruta shell, que no llamaba a
    // startCopyProgress en el undo. Evita un `du` inútil.
    if (busyLabel)
      startCopyProgress(pairs.map(function (p) { return p.src }),
                        pairs.map(function (p) { return p.dest }))
    _batchNext()
    return true
  }

  function _batchNext() {
    if (_cancelling) { _nativeDone(false); return }
    if (_batchIdx >= _batchQueue.length) { _nativeDone(true); return }
    var p = _batchQueue[_batchIdx]
    function ok(op, src) { cleanup(); _batchIdx += 1; _batchNext() }
    // El error ya lo avisó services/FileOperations (salvo "cancelled"); aquí
    // solo se para la secuencia y se limpia el estado.
    function bad(op, src, msg) { cleanup(); _nativeDone(false) }
    function cleanup() {
      FileOperations.finished.disconnect(ok)
      FileOperations.error.disconnect(bad)
    }
    FileOperations.finished.connect(ok)
    FileOperations.error.connect(bad)
    if (_nativeKind === "remove")
      FileOperations.remove(p.src, _batchOverwrite)  // _batchOverwrite = ignoreMissing
    else if (_nativeKind === "move")
      FileOperations.move(p.src, p.dest, _batchOverwrite)
    else
      FileOperations.copy(p.src, p.dest, _batchOverwrite)
  }

  function _nativeDone(success) {
    nativeBusy = false
    ActionState.actionBusy = false
    ActionState.actionLabel = ""
    ActionState.actionProgressPct = -1
    ActionState.actionTotalBytes = 0
    ActionState.actionProgressDestPaths = []
    root.refresh()
    root.refreshTick += 1
    var cb = _batchOnDone
    _batchOnDone = null
    if (success && cb) cb()
  }

  ProcessRunner {
    id: actionProc
    onFinished: function (result) {
      ActionState.actionBusy = false
      ActionState.actionLabel = ""
      ActionState.actionProgressPct = -1
      ActionState.actionTotalBytes = 0
      ActionState.actionProgressDestPaths = []
      root.refresh()
      // Una acción (borrar, mover, pegar...) puede afectar a cualquier
      // panel, no solo al activo -- refreshTick es la señal para que los
      // paneles no activos (cada uno con su propio Process de listado, ver
      // el Repeater de paneles) se refresquen también.
      root.refreshTick += 1
      var cb = ActionState._actionOnSuccess
      ActionState._actionOnSuccess = null
      if (result.exitCode === 0) {
        if (cb) cb()
      } else if (!result.cancelled) {
        // Antes esto se tragaba en silencio -- un mv/cp/chmod/zip/unzip que
        // fallara (permisos, disco lleno, archivo corrupto...) se veía
        // exactamente igual que uno que había ido bien.
        Notifier.notify("Action failed: " + (result.stderr.trim() || "unknown error"))
      }
    }
  }

  // Tamaño total del origen, UNA vez al principio de una copia/movimiento
  // -- ver startCopyProgress().
  ProcessRunner {
    id: actionProgressTotalProc
    onFinished: function (result) {
      var n = parseInt(result.stdout.trim(), 10)
      ActionState.actionTotalBytes = isNaN(n) ? 0 : n
    }
  }

  // Sondeo periódico de cuánto hay ya en el destino mientras
  // actionBusy+actionTotalBytes>0 -- ver el Timer de abajo, que es quien
  // decide CUÁNDO relanzar esto (no tiene sentido más de un sondeo a la
  // vez si el anterior tarda más que el intervalo).
  ProcessRunner {
    id: actionProgressPollProc
    onFinished: function (result) {
      if (ActionState.actionTotalBytes <= 0) return
      var n = parseInt(result.stdout.trim(), 10)
      if (isNaN(n)) return
      ActionState.actionProgressPct = Math.min(100, n / ActionState.actionTotalBytes * 100)
    }
  }

  Timer {
    // Un sondeo "du" sobre destinos grandes no es instantáneo -- esta
    // guardia (en vez de solo "repeat: true") evita amontonar sondeos si
    // uno tarda más que el intervalo.
    id: actionProgressPollTimer
    interval: 600
    repeat: true
    running: ActionState.actionBusy && ActionState.actionTotalBytes > 0 && ActionState.actionProgressDestPaths.length > 0
    onTriggered: {
      if (actionProgressPollProc.busy) return
      var quoted = ActionState.actionProgressDestPaths.map(function (p) { return Util.shellQuote(p) }).join(" ")
      actionProgressPollProc.start(["bash", "-c", "du -sbc -- " + quoted + " 2>/dev/null | tail -n1 | cut -f1"])
    }
  }
}

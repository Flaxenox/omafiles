import QtQuick
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
    // Copia/movimiento nativo en curso (Fase 13.A/G): cancelación cooperativa
    // en C++. El worker aborta entre trozos, LIMPIA ÉL MISMO la copia parcial
    // del destino (forceRemove en backend/FileOperations) y emite error
    // "cancelled" -> bad() -> _nativeDone limpia el estado y refresca. Ya no
    // hay `rm -rf` de shell: el backend es autosuficiente para limpiar.
    if (nativeBusy) {
      _cancelling = true
      FileOperations.cancel()
      return
    }
    // Acciones aún en shell (comprimir/extraer/renombrar/crear): actionProc.
    // cancel() mata todo el grupo de procesos. No tienen progreso ni un
    // destino parcial que limpiar aquí (su overwrite es atómico o lo gestiona
    // su propio comando).
    actionProc.cancel()
    ActionState.actionBusy = false
    ActionState.actionLabel = ""
    ActionState.actionProgressPct = -1
    root.refresh()
    NavState.refreshTick += 1
  }

  // ---------- Progreso nativo por bytes (Fase 13.G) ----------
  // Sustituye el sondeo `du` por el tamaño total (FileOperations.totalSize,
  // una vez) + la señal progress(op,path,done,total) del backend, agregada
  // sobre el lote. Mismo comportamiento observable: actionProgressPct 0..100
  // (barra) para copy/move; -1 (puntos) si no hay tamaño medible.
  property real _progTotal: 0   // bytes totales del lote (todos los orígenes)
  property real _progBase: 0    // bytes ya completados de ítems anteriores
  property real _lastItemTotal: 0 // total del ítem en curso (último progress)

  function startCopyProgress(sourcePaths, destPaths) {
    _progTotal = FileOperations.totalSize(sourcePaths)
    _progBase = 0
    _lastItemTotal = 0
    // Barra desde 0% si hay algo que medir; puntos si el total es 0 (ítems
    // vacíos: no hay progreso que mostrar).
    ActionState.actionProgressPct = _progTotal > 0 ? 0 : -1
  }

  Connections {
    target: FileOperations
    function onProgress(op, path, done, total) {
      if (!nativeBusy || _progTotal <= 0) return
      _lastItemTotal = total
      ActionState.actionProgressPct = Math.min(100, (_progBase + done) * 100 / _progTotal)
    }
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

  // Enviar a papelera nativo (Fase 13.D): `paths` = rutas a enviar. XDG Trash
  // (QFile::moveToTrash: crea el .trashinfo, resuelve colisiones, respeta el
  // disco de origen). El llamador (borrado a papelera desde DeleteOps)
  // registra el undo en onDone (restaurar por ruta original).
  function runNativeTrash(paths, busyLabel, onDone) {
    var pairs = paths.map(function (p) { return { src: p } })
    return _runNative("trash", pairs, busyLabel, false, onDone)
  }

  // Restaurar nativo (Fase 13.E): `origPaths` = rutas ORIGINALES a restaurar.
  // Cada una se localiza por su .trashinfo en cualquier papelera activa.
  function runNativeRestore(origPaths, busyLabel, onDone) {
    var pairs = origPaths.map(function (p) { return { src: p } })
    return _runNative("restore", pairs, busyLabel, false, onDone)
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
    // Barra de progreso (sondeo `du`) SOLO para copy/move con etiqueta:
    // son las únicas con "tamaño total" que crece en el destino. trash/
    // restore/remove no tienen progreso medible así (restore mvería a rutas
    // que aún no existen -> du fallaría y dejaría un 0% fijo en vez de los
    // puntos animados). Sin etiqueta (undo/redo) tampoco, como la ruta shell.
    if (busyLabel && (kind === "copy" || kind === "move"))
      startCopyProgress(pairs.map(function (p) { return p.src }),
                        pairs.map(function (p) { return p.dest }))
    _batchNext()
    return true
  }

  function _batchNext() {
    if (_cancelling) { _nativeDone(false); return }
    if (_batchIdx >= _batchQueue.length) { _nativeDone(true); return }
    var p = _batchQueue[_batchIdx]
    function ok(op, src) {
      cleanup()
      // Progreso agregado: el ítem terminado suma su total a la base.
      _progBase += _lastItemTotal
      _lastItemTotal = 0
      _batchIdx += 1
      _batchNext()
    }
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
    else if (_nativeKind === "trash")
      FileOperations.trash(p.src)
    else if (_nativeKind === "restore")
      FileOperations.restoreByOrigPath(p.src)
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
    NavState.refreshTick += 1
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
      NavState.refreshTick += 1
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

  // (Fase 13.G) Eliminados actionProgressTotalProc / actionProgressPollProc /
  // actionProgressPollTimer: el progreso ya no se sondea con `du`, viene por
  // bytes de la señal FileOperations.progress (ver la Connections de arriba).
}

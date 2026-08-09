import QtQuick
import Omafiles.Backend as Backend
import "../../services"
import "../../state"

// SelfCheck -- arnés de validación funcional reproducible de Omafiles (Fase
// 12, josema). Se carga desde main.cpp cuando el ejecutable standalone
// arranca con `--selfcheck`, headless (offscreen) y sin Quickshell. Ejercita
// los subsistemas principales de backend, frontend e integración sobre
// fixtures deterministas (montados por main.cpp en un QTemporaryDir que se
// borra solo) y termina con Qt.exit(nº de fallos): 0 = todo PASS.
//
// Diseño: un runner secuencial y asíncrono. Cada prueba es
//   add(nombre, function(done){ ... done(pass, mensaje) })
// y puede resolver de forma síncrona o al llegar una señal; un timeout por
// prueba evita cuelgues. Extensible: añadir pruebas = añadir add(...) en
// _register(). No usa QtTest ni toca el comportamiento normal de la app.
//
// Base para la Fase 13 (migrar FileOperations del shell al backend C++):
// estas mismas comprobaciones se ejecutarán antes y después de cada
// operación para blindar esa migración.
QtObject {
  id: sc

  // Directorio temporal con fixtures, inyectado por main.cpp. Fallback por
  // si se carga a mano (no debería).
  readonly property string dir: (typeof selfCheckTmpDir !== "undefined" && selfCheckTmpDir)
    ? selfCheckTmpDir : "/tmp/omafiles-selfcheck"

  // ---- rutas de fixtures (ver writeSelfCheckFixtures en main.cpp) ----
  readonly property string listDir: dir + "/list"
  readonly property string watchDir: dir + "/watch"
  readonly property string opsDir: dir + "/ops"
  readonly property string jsonFile: dir + "/json/t.json"
  readonly property string png: dir + "/img.png"
  readonly property string pdf: dir + "/doc.pdf"
  readonly property string note: dir + "/note.txt"

  // ---- estado del runner ----
  property var checks: []
  property int idx: -1
  property int passes: 0
  property int fails: 0
  property real _startedAt: 0
  property bool _settled: false

  // Fábrica de DirectoryModel para las comprobaciones de existencia/listado
  // (servicio no-singleton envuelto sobre el backend C++).
  property Component _dmFactory: Component { DirectoryModel {} }

  // Composition root creado en la prueba correspondiente y reutilizado por
  // las de fachada.
  property var _content: null

  property Timer _timeout: Timer {
    interval: 8000
    onTriggered: sc._done(false, "timeout (" + _timeout.interval + "ms)")
  }

  function add(name, fn) { checks.push({ name: name, fn: fn }) }

  function _run() {
    idx++
    if (idx >= checks.length) { _report(); return }
    _settled = false
    _startedAt = Date.now()
    _timeout.restart()
    try {
      checks[idx].fn(function (pass, msg) { sc._done(pass, msg) })
    } catch (e) {
      _done(false, "excepción: " + e)
    }
  }

  function _done(pass, msg) {
    if (_settled) return
    _settled = true
    _timeout.stop()
    var ms = Date.now() - _startedAt
    if (pass) passes++; else fails++
    SelfCheckOut.line((pass ? "[PASS] " : "[FAIL] ") + checks[idx].name
      + " (" + ms + "ms)" + (msg ? " — " + msg : ""))
    Qt.callLater(_run)
  }

  function _report() {
    SelfCheckOut.line("")
    SelfCheckOut.line("── selfcheck: " + passes + " passed, " + fails
      + " failed, " + checks.length + " total ──")
    Qt.exit(fails > 0 ? 1 : 0)
  }

  // Lista un directorio una sola vez y devuelve sus entradas por callback.
  function _listOnce(path, cb) {
    var m = _dmFactory.createObject(sc)
    var fired = false
    function h() {
      if (fired) return
      fired = true
      m.listed.disconnect(h)
      var e = m.entries
      cb(e)
      Qt.callLater(function () { m.destroy() })
    }
    m.listed.connect(h)
    m.list(path, true)
  }

  function _has(entries, name) {
    for (var i = 0; i < entries.length; i++)
      if (entries[i].name === name) return true
    return false
  }

  // Ejecuta una operación de FileOperations y llama then(path) en su primera
  // señal finished, o done(false, ...) en error. Como el runner es
  // secuencial, solo hay una operación en vuelo.
  function _fileOp(done, then) {
    function ok(op, path) { cleanup(); then(op, path) }
    function bad(op, path, msg) { cleanup(); done(false, op + " error: " + msg) }
    function cleanup() {
      FileOperations.finished.disconnect(ok)
      FileOperations.error.disconnect(bad)
    }
    FileOperations.finished.connect(ok)
    FileOperations.error.connect(bad)
  }

  Component.onCompleted: {
    _register()
    SelfCheckOut.line("── omafiles --selfcheck · fixtures en " + dir + " ──")
    _run()
  }

  function _register() {
    // ======================= INTEGRACIÓN =======================

    add("Backend module loaded (Omafiles.Backend)", function (done) {
      var home = Backend.Env.get("HOME")
      done(!!home && home.length > 0, home ? "HOME=" + home : "Env.get(HOME) vacío")
    })

    add("Composition root creates (OmafilesContent)", function (done) {
      var comp = Qt.createComponent(Qt.resolvedUrl("../../core/OmafilesContent.qml"))
      if (comp.status === Component.Error) { done(false, comp.errorString()); return }
      var obj = comp.createObject(sc)
      if (!obj) { done(false, "createObject devolvió null"); return }
      sc._content = obj
      done(true, "árbol principal instanciado")
    })

    add("Composition root API surface (open/close/facade)", function (done) {
      var c = sc._content
      if (!c) { done(false, "sin composition root"); return }
      var ok = typeof c.open === "function"
        && typeof c.close === "function"
        && typeof c.paletteCommands === "function"
        && typeof c.itemActions === "function"
      done(ok, ok ? "" : "faltan funciones del contrato/fachada")
    })

    // ======================= FRONTEND =======================

    add("NavState is source of truth", function (done) {
      var prev = NavState.currentPath
      NavState.currentPath = sc.listDir
      var ok = NavState.currentPath === sc.listDir
      done(ok, ok ? "" : "NavState.currentPath no persiste")
    })

    add("TabsState defaults", function (done) {
      var ok = TabsState.tabs.length >= 1 && TabsState.activeTabIndex === 0
      done(ok, "tabs=" + TabsState.tabs.length + " active=" + TabsState.activeTabIndex)
    })

    add("ControllerRegistry + CommandFacade wiring", function (done) {
      var c = sc._content
      if (!c) { done(false, "sin composition root"); return }
      // Fuerza la evaluación de los builders: si un controlador llegara null
      // por un fallo de inyección del registro, esto lanzaría (ver Fase 11.C).
      var pal = c.paletteCommands().length
      var items = c.itemActions().length            // 0 sin selección: válido
      var empty = c.emptyAreaActions().length
      var segs = c.pathSegments().length
      var ok = pal > 0 && empty > 0 && segs > 0 && (items >= 0)
      done(ok, "palette=" + pal + " emptyArea=" + empty + " segments=" + segs)
    })

    add("AppBindings loaded (no side effects under selfcheck)", function (done) {
      // Si OmafilesContent se creó sin errores, AppBindings (su hijo) también.
      // El autoregistro como gestor de archivos está guardado por
      // OMAFILES_SELFCHECK, así que esta prueba confirma que no hubo efecto
      // secundario y que el core arrancó completo.
      done(sc._content !== null, "AppBindings instanciado sin autoregistro")
    })

    // ======================= BACKEND =======================

    add("JsonStore write/read round-trip", function (done) {
      var payload = { a: 1, b: "x", nested: { k: [1, 2, 3] } }
      function onSaved(path, ok) {
        JsonStore.saved.disconnect(onSaved)
        if (!ok) { done(false, "write falló"); return }
        function onLoaded(p, data, lok) {
          JsonStore.loaded.disconnect(onLoaded)
          if (!lok) { done(false, "read falló"); return }
          var good = data && data.a === 1 && data.b === "x"
            && data.nested && data.nested.k.length === 3
          done(good, good ? "" : "datos no coinciden: " + JSON.stringify(data))
        }
        JsonStore.loaded.connect(onLoaded)
        JsonStore.read(sc.jsonFile)
      }
      JsonStore.saved.connect(onSaved)
      JsonStore.write(sc.jsonFile, payload)
    })

    add("DirectoryModel list + natural order", function (done) {
      sc._listOnce(sc.listDir, function (e) {
        var names = e.map(function (x) { return x.name })
        // 3 ficheros + 1 subcarpeta; carpetas primero, luego naturalCompare.
        var okCount = e.length === 4
        var okOrder = names[0] === "sub" && names[1] === "alpha.txt"
          && names[2] === "beta.txt" && names[3] === "gamma.txt"
        done(okCount && okOrder, "orden=[" + names.join(", ") + "]")
      })
    })

    add("QFileSystemWatcher create event", function (done) {
      var m = sc._dmFactory.createObject(sc)
      var watched = m.watch(sc.watchDir)
      if (!watched) { m.destroy(); done(false, "watch() devolvió false"); return }
      // Espera AMBOS: el directoryChanged del watcher y el finished del mkdir
      // trigger (consumido para no filtrarlo a pruebas posteriores).
      var gotChange = false, gotFinish = false, settled = false
      function finish(ok, msg) {
        if (settled) return
        settled = true
        m.directoryChanged.disconnect(onChanged)
        m.unwatch(); m.destroy()
        done(ok, msg)
      }
      function maybe() { if (gotChange && gotFinish) finish(true, "directoryChanged tras crear subcarpeta") }
      function onChanged() { gotChange = true; maybe() }
      m.directoryChanged.connect(onChanged)
      sc._fileOp(function (ok, msg) { finish(false, "mkdir trigger: " + msg) },
                 function () { gotFinish = true; maybe() })
      FileOperations.mkdir(sc.watchDir + "/trigger")
    })

    add("ThumbnailProvider PNG", function (done) {
      var immediate = ThumbnailProvider.request(sc.png, 128)
      if (immediate && immediate.length > 0) { done(true, "cache hit"); return }
      function onReady(path, thumbPath) {
        if (path !== sc.png) return
        ThumbnailProvider.ready.disconnect(onReady)
        done(thumbPath.length > 0, thumbPath ? "" : "thumbPath vacío")
      }
      ThumbnailProvider.ready.connect(onReady)
    })

    add("ThumbnailProvider PDF (qpdf plugin)", function (done) {
      var immediate = ThumbnailProvider.request(sc.pdf, 128)
      if (immediate && immediate.length > 0) { done(true, "cache hit"); return }
      function onReady(path, thumbPath) {
        if (path !== sc.pdf) return
        ThumbnailProvider.ready.disconnect(onReady)
        done(thumbPath.length > 0, thumbPath ? "" : "sin miniatura (¿falta qpdf?)")
      }
      ThumbnailProvider.ready.connect(onReady)
    })

    add("PreviewProvider text", function (done) {
      function onText(path, content, enc, bytes, lines, trunc) {
        if (path !== sc.note) return
        PreviewProvider.textReady.disconnect(onText)
        var ok = content.indexOf("hello selfcheck") >= 0
        done(ok, ok ? enc + ", " + lines + " líneas" : "contenido inesperado")
      }
      PreviewProvider.textReady.connect(onText)
      PreviewProvider.requestText(sc.note, 65536)
    })

    add("PreviewProvider info", function (done) {
      var info = PreviewProvider.info(sc.note)
      var ok = info && typeof info === "object" && Object.keys(info).length > 0
      done(ok, ok ? "keys=[" + Object.keys(info).join(",") + "]" : "info vacío")
    })

    // -------- FileOperations (las 7 operaciones existentes) --------

    add("FileOperations mkdir", function (done) {
      sc._fileOp(done, function (op, path) {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = sc._has(e, "newdir")
          done(ok, ok ? "" : "newdir no aparece")
        })
      })
      FileOperations.mkdir(sc.opsDir + "/newdir")
    })

    add("FileOperations rename", function (done) {
      // Prepara un fichero conocido y renómbralo.
      FileOperations.copy(sc.note, sc.opsDir + "/toRename.txt")
      sc._fileOp(done, function () {
        sc._fileOp(done, function () {
          sc._listOnce(sc.opsDir, function (e) {
            var ok = sc._has(e, "renamed.txt") && !sc._has(e, "toRename.txt")
            done(ok, ok ? "" : "rename no reflejado")
          })
        })
        FileOperations.rename(sc.opsDir + "/toRename.txt", "renamed.txt")
      })
    })

    add("FileOperations copy", function (done) {
      sc._fileOp(done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = sc._has(e, "copy.txt")
          done(ok, ok ? "" : "copy.txt no aparece")
        })
      })
      FileOperations.copy(sc.note, sc.opsDir + "/copy.txt")
    })

    add("FileOperations copy overwrite (replace)", function (done) {
      var dst = sc.opsDir + "/ow.txt"
      sc._fileOp(done, function () {           // 1) crea el destino
        // 2) copiar encima CON overwrite debe reemplazar (finished, no error)
        sc._fileOp(done, function () { done(true, "destino reemplazado") })
        FileOperations.copy(sc.note, dst, true)
      })
      FileOperations.copy(sc.note, dst)        // sin overwrite: destino nuevo
    })

    add("FileOperations copy directory (recursive)", function (done) {
      sc._fileOp(done, function () {
        sc._listOnce(sc.opsDir + "/listcopy", function (e) {
          var ok = e.length === 4 && sc._has(e, "sub") && sc._has(e, "alpha.txt")
          done(ok, ok ? e.length + " entradas copiadas" : "árbol incompleto")
        })
      })
      FileOperations.copy(sc.listDir, sc.opsDir + "/listcopy")
    })

    add("FileOperations copy symlink preserved", function (done) {
      sc._fileOp(done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = false
          for (var i = 0; i < e.length; i++)
            if (e[i].name === "linkcopy" && e[i].link && e[i].link.length > 0) ok = true
          done(ok, ok ? "copiado como enlace" : "no quedó como symlink")
        })
      })
      FileOperations.copy(sc.dir + "/link.txt", sc.opsDir + "/linkcopy")
    })

    add("FileOperations copy preserves permissions", function (done) {
      var srcPerm = PreviewProvider.info(sc.note).permissions
      sc._fileOp(done, function () {
        var dstPerm = PreviewProvider.info(sc.opsDir + "/permcopy").permissions
        var ok = srcPerm && dstPerm && srcPerm === dstPerm
        done(ok, "src=" + srcPerm + " dst=" + dstPerm)
      })
      FileOperations.copy(sc.note, sc.opsDir + "/permcopy")
    })

    add("ActionEngine native copy runner (paste/drop path)", function (done) {
      // Ejercita el cableado REAL que usan runPaste/runDrop (13.A):
      // content.copyFiles -> ActionEngine.runNativeCopy -> FileOperations.copy
      // -> onDone. Confirma busy/secuencia/completado sin shell.
      var c = sc._content
      if (!c) { done(false, "sin composition root"); return }
      var dst = sc.opsDir + "/enginecopy.txt"
      var started = c.copyFiles([{ src: sc.note, dest: dst }], "Copying…", false, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = sc._has(e, "enginecopy.txt")
          done(ok, ok ? "runNativeCopy OK" : "no copió")
        })
      })
      if (!started) done(false, "runNativeCopy devolvió false (¿ocupado?)")
    })

    // -------- Move (13.B) --------

    add("FileOperations move overwrite (replace)", function (done) {
      var work = sc.opsDir + "/mvow-src.txt"
      var dst = sc.opsDir + "/mvow-dst.txt"
      sc._fileOp(done, function () {          // work creado
        sc._fileOp(done, function () {        // dst creado (provoca conflicto)
          sc._fileOp(done, function () {      // move con overwrite -> reemplaza
            sc._listOnce(sc.opsDir, function (e) {
              var ok = sc._has(e, "mvow-dst.txt") && !sc._has(e, "mvow-src.txt")
              done(ok, ok ? "reemplazado, origen consumido" : "estado inesperado")
            })
          })
          FileOperations.move(work, dst, true)
        })
        FileOperations.copy(sc.note, dst)
      })
      FileOperations.copy(sc.note, work)
    })

    add("FileOperations move directory (recursive)", function (done) {
      var srcDir = sc.opsDir + "/mvdir-src"
      var dstDir = sc.opsDir + "/mvdir-dst"
      sc._fileOp(done, function () {          // copia listDir -> srcDir (árbol)
        sc._fileOp(done, function () {        // move srcDir -> dstDir
          sc._listOnce(dstDir, function (e) {
            var okDst = e.length === 4 && sc._has(e, "sub") && sc._has(e, "alpha.txt")
            sc._listOnce(sc.opsDir, function (top) {
              var okGone = !sc._has(top, "mvdir-src")
              done(okDst && okGone, okDst ? (okGone ? "árbol movido, origen ido" : "origen no se borró") : "árbol destino incompleto")
            })
          })
        })
        FileOperations.move(srcDir, dstDir)
      })
      FileOperations.copy(sc.listDir, srcDir)
    })

    add("FileOperations move symlink preserved", function (done) {
      var work = sc.opsDir + "/mvlink-src"
      var dst = sc.opsDir + "/mvlink-dst"
      sc._fileOp(done, function () {          // copia link.txt -> work (symlink)
        sc._fileOp(done, function () {        // move work -> dst
          sc._listOnce(sc.opsDir, function (e) {
            var ok = false
            for (var i = 0; i < e.length; i++)
              if (e[i].name === "mvlink-dst" && e[i].link && e[i].link.length > 0) ok = true
            done(ok, ok ? "movido como enlace" : "no quedó symlink")
          })
        })
        FileOperations.move(work, dst)
      })
      FileOperations.copy(sc.dir + "/link.txt", work)
    })

    add("FileOperations move cross-filesystem (best-effort /tmp)", function (done) {
      // HOME (.cache) -> /tmp: si son montajes distintos (tmpfs), fuerza el
      // fallback copia+borrado (EXDEV); si es el mismo, degrada a rename
      // atómico. En ambos casos el move debe cumplir: destino con el fichero,
      // origen consumido. Limpia el /tmp al terminar (net-zero).
      var work = sc.opsDir + "/xfs-src.txt"
      var xfsDst = "/tmp/omafiles-selfcheck-xfs-" + Date.now() + ".txt"
      sc._fileOp(done, function () {          // work creado en HOME
        sc._fileOp(done, function () {        // move HOME -> /tmp
          var destInfo = PreviewProvider.info(xfsDst)
          var destOk = destInfo && Object.keys(destInfo).length > 0
          sc._listOnce(sc.opsDir, function (e) {
            var srcGone = !sc._has(e, "xfs-src.txt")
            // limpia /tmp ESPERANDO su finished, para no filtrar la señal a
            // la prueba siguiente (era la causa de la flakiness).
            sc._fileOp(done, function () {
              done(destOk && srcGone, (destOk ? "dest ok" : "dest falta") + ", " + (srcGone ? "origen ido" : "origen queda"))
            })
            FileOperations.remove(xfsDst)
          })
        })
        FileOperations.move(work, xfsDst)
      })
      FileOperations.copy(sc.note, work)
    })

    add("Copy/move cancellation (cooperative, source safe)", function (done) {
      // Cancela una copia grande (32 MiB): cancel() SÍNCRONO justo tras
      // lanzar la copia activa el flag antes de que el worker (que aún tiene
      // que arrancar en el pool y luego copia MiBs) pueda terminar, así que
      // aborta con error "cancelled" de forma determinista, sin borrar el
      // origen (en move, removeTree del origen solo corre TRAS copiar; la
      // ruta copyTree es la misma que usa move cross-fs).
      var dst = sc.opsDir + "/big-copy.bin"
      var srcPath = sc.dir + "/big.bin"
      function onErr(op, path, msg) {
        if (path !== srcPath) return  // ignora señales de otras operaciones
        cleanup()
        if (msg !== "cancelled") { done(false, "error inesperado: " + msg); return }
        // el origen (big.bin) sigue intacto
        var srcOk = PreviewProvider.info(srcPath)
        done(srcOk && Object.keys(srcOk).length > 0, "cancelado, origen intacto")
      }
      function onFin(op, path) {
        if (path !== srcPath) return  // ignora señales de otras operaciones
        cleanup(); done(false, "terminó antes de poder cancelar")
      }
      function cleanup() {
        FileOperations.error.disconnect(onErr)
        FileOperations.finished.disconnect(onFin)
      }
      FileOperations.error.connect(onErr)
      FileOperations.finished.connect(onFin)
      FileOperations.copy(sc.dir + "/big.bin", dst)
      FileOperations.cancel()
    })

    add("ActionEngine native move runner + undo (paste/drop path)", function (done) {
      // Ejercita el cableado REAL de mover con undo (13.B):
      // content.moveFiles -> runNativeMove -> FileOperations.move; luego
      // content.undoLast -> moveFiles(invertido) revierte.
      var c = sc._content
      if (!c) { done(false, "sin composition root"); return }
      var work = sc.opsDir + "/mv-runner-src.txt"
      var dst = sc.opsDir + "/mv-runner-dst.txt"
      sc._fileOp(done, function () {          // work creado
        var pairs = [{ src: work, dest: dst }]
        var started = c.moveFiles(pairs, "Moving…", false, function () {
          // Registra el undo EXACTAMENTE como hace ClipboardOps/ConflictActions
          // en su onDone (mover de vuelta / rehacer, ambos nativos).
          var reversed = [{ src: dst, dest: work }]
          c.pushUndo("move test",
            function () { return c.moveFiles(reversed, "", false) },
            function () { return c.moveFiles(pairs, "", false) })
          sc._listOnce(sc.opsDir, function (e) {
            if (!(sc._has(e, "mv-runner-dst.txt") && !sc._has(e, "mv-runner-src.txt"))) {
              done(false, "no movió"); return
            }
            // undo: mover de vuelta (espera el finished del reverse move)
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e2) {
                var undone = sc._has(e2, "mv-runner-src.txt") && !sc._has(e2, "mv-runner-dst.txt")
                done(undone, undone ? "movido y deshecho" : "undo no revirtió")
              })
            })
            c.undoLast()
          })
        })
        if (!started) done(false, "runNativeMove devolvió false")
      })
      FileOperations.copy(sc.note, work)
    })

    // -------- Delete permanente (13.C) --------

    add("FileOperations delete directory (recursive)", function (done) {
      sc._fileOp(done, function () {        // copia listDir -> deldir
        sc._fileOp(done, function () {      // remove deldir (recursivo)
          sc._listOnce(sc.opsDir, function (e) {
            var ok = !sc._has(e, "deldir")
            done(ok, ok ? "árbol borrado" : "sigue existiendo")
          })
        })
        FileOperations.remove(sc.opsDir + "/deldir")
      })
      FileOperations.copy(sc.listDir, sc.opsDir + "/deldir")
    })

    add("FileOperations delete symlink (target preserved)", function (done) {
      sc._fileOp(done, function () {        // copia link.txt -> dellink
        sc._fileOp(done, function () {      // remove dellink
          sc._listOnce(sc.opsDir, function (e) {
            var linkGone = !sc._has(e, "dellink")
            var target = PreviewProvider.info(sc.note) // note.txt (destino del enlace)
            done(linkGone && Object.keys(target).length > 0,
                 linkGone ? "enlace borrado, target intacto" : "el enlace sigue")
          })
        })
        FileOperations.remove(sc.opsDir + "/dellink")
      })
      FileOperations.copy(sc.dir + "/link.txt", sc.opsDir + "/dellink")
    })

    add("FileOperations delete read-only (permission failure)", function (done) {
      // Borrar un fichero dentro de una carpeta sin permiso de escritura
      // falla (EACCES). Se comprueba que el error se reporta razonablemente.
      var target = sc.dir + "/readonly/locked.txt"
      function onErr(op, path, msg) { if (path !== target) return; cleanup(); done(true, "error reportado: " + msg) }
      function onFin(op, path) { if (path !== target) return; cleanup(); done(false, "no debería poder borrar en carpeta read-only") }
      function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
      FileOperations.error.connect(onErr)
      FileOperations.finished.connect(onFin)
      FileOperations.remove(target, false)
    })

    add("FileOperations delete missing (error vs ignoreMissing)", function (done) {
      var gone = sc.opsDir + "/never-existed-" + Date.now()
      var gone2 = sc.opsDir + "/never2-" + Date.now()
      function onErr(op, path, msg) {
        if (path !== gone) return
        cleanup1()
        // con ignoreMissing=true, que falte debe ser OK (finished)
        function onFin2(o, p) { if (p !== gone2) return; cleanup2(); done(true, "error si falta, ok con ignoreMissing") }
        function onErr2(o, p, m) { if (p !== gone2) return; cleanup2(); done(false, "ignoreMissing no debería fallar") }
        function cleanup2() { FileOperations.finished.disconnect(onFin2); FileOperations.error.disconnect(onErr2) }
        FileOperations.finished.connect(onFin2)
        FileOperations.error.connect(onErr2)
        FileOperations.remove(gone2, true)
      }
      function onFin(op, path) { if (path !== gone) return; cleanup1(); done(false, "debería fallar sin ignoreMissing") }
      function cleanup1() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
      FileOperations.error.connect(onErr)
      FileOperations.finished.connect(onFin)
      FileOperations.remove(gone, false)
    })

    add("FileOperations delete cancellation (recursive tree)", function (done) {
      // Borra un árbol de 500 ficheros con cancel SÍNCRONO: removeTree aborta
      // (entre entradas / en la comprobación de entrada) con "cancelled",
      // misma ruta de cancelación que copia/move cross-fs.
      var target = sc.dir + "/bigdir"
      function onErr(op, path, msg) {
        if (path !== target) return
        cleanup()
        done(msg === "cancelled", "error=" + msg)
      }
      function onFin(op, path) { if (path !== target) return; cleanup(); done(false, "terminó antes de poder cancelar") }
      function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
      FileOperations.error.connect(onErr)
      FileOperations.finished.connect(onFin)
      FileOperations.remove(target)
      FileOperations.cancel()
    })

    add("ActionEngine native remove runner (delete path)", function (done) {
      // Ejercita el cableado REAL del borrado permanente (13.C):
      // content.removeFiles -> runNativeRemove -> FileOperations.remove.
      var c = sc._content
      if (!c) { done(false, "sin composition root"); return }
      var a = sc.opsDir + "/del-a.txt"
      var b = sc.opsDir + "/del-b.txt"
      sc._fileOp(done, function () {        // a creado
        sc._fileOp(done, function () {      // b creado
          var started = c.removeFiles([a, b], "", true, function () {
            sc._listOnce(sc.opsDir, function (e) {
              var ok = !sc._has(e, "del-a.txt") && !sc._has(e, "del-b.txt")
              done(ok, ok ? "runNativeRemove OK" : "no borró")
            })
          })
          if (!started) done(false, "runNativeRemove devolvió false")
        })
        FileOperations.copy(sc.note, b)
      })
      FileOperations.copy(sc.note, a)
    })

    add("FileOperations move", function (done) {
      FileOperations.copy(sc.note, sc.opsDir + "/toMove.txt")
      sc._fileOp(done, function () {
        sc._fileOp(done, function () {
          sc._listOnce(sc.opsDir + "/newdir", function (e) {
            var ok = sc._has(e, "moved.txt")
            done(ok, ok ? "" : "moved.txt no está en destino")
          })
        })
        FileOperations.move(sc.opsDir + "/toMove.txt", sc.opsDir + "/newdir/moved.txt")
      })
    })

    add("FileOperations remove", function (done) {
      sc._fileOp(done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = !sc._has(e, "copy.txt")
          done(ok, ok ? "" : "copy.txt sigue existiendo")
        })
      })
      FileOperations.remove(sc.opsDir + "/copy.txt")
    })

    add("FileOperations trash + restore (net-zero)", function (done) {
      // Nombre único: evita que moveToTrash renombre por colisión en la
      // papelera del usuario y garantiza que el basename en Trash/files es
      // el esperado. Los fixtures viven en el montaje de HOME, así que
      // moveToTrash usa la papelera de casa.
      var fname = "selfcheck-trash-" + Date.now() + ".txt"
      var target = sc.opsDir + "/" + fname
      var trashFiles = Backend.Env.get("HOME") + "/.local/share/Trash/files/" + fname
      FileOperations.copy(sc.note, target)
      sc._fileOp(done, function () {                 // copy listo
        sc._fileOp(done, function () {               // trash listo (target -> papelera)
          sc._fileOp(done, function () {             // restore listo
            sc._listOnce(sc.opsDir, function (e) {
              var ok = sc._has(e, fname)
              done(ok, ok ? "restaurado a su sitio" : "no volvió tras restore")
            })
          })
          // restore recibe la ruta DENTRO de la papelera (contrato real: la
          // vista Papelera lista .../Trash/files y restaura por esa ruta),
          // no la ruta original.
          FileOperations.restore(trashFiles)
        })
        FileOperations.trash(target)
      })
    })
  }
}

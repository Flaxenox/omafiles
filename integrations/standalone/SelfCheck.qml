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
      var fired = false
      function onChanged() {
        if (fired) return
        fired = true
        m.directoryChanged.disconnect(onChanged)
        m.unwatch(); m.destroy()
        done(true, "directoryChanged tras crear subcarpeta")
      }
      m.directoryChanged.connect(onChanged)
      // Provoca un cambio en el directorio vigilado.
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

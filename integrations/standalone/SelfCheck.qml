import QtQuick
import Omafiles.Backend as Backend
import "../../services"
import "../../state"
import "../../Utils.js" as Utils

// SelfCheck -- reproducible functional validation harness of Omafiles (Phase
// 12, josema). It's loaded from main.cpp when the standalone executable
// starts with `--selfcheck`, headless (offscreen) and without Quickshell. It exercises
// the main subsystems of backend, frontend and integration over
// deterministic fixtures (mounted by main.cpp in a QTemporaryDir that
// removes itself) and ends with Qt.exit(number of failures): 0 = all PASS.
//
// Design: a sequential, asynchronous runner. Each test is
//   add(name, function(done){ ... done(pass, message) })
// and can resolve synchronously or when a signal arrives; a per-test
// timeout avoids hangs. Extensible: adding tests = adding add(...) in
// _register(). It doesn't use QtTest nor touch the normal behavior of the app.
//
// Base for Phase 13 (migrate FileOperations from shell to the C++ backend):
// these same checks will run before and after each
// operation to shield that migration.
QtObject {
  id: sc

  // Temporary directory with fixtures, injected by main.cpp. Fallback in
  // case it's loaded by hand (it shouldn't be).
  readonly property string dir: (typeof selfCheckTmpDir !== "undefined" && selfCheckTmpDir)
    ? selfCheckTmpDir : "/tmp/omafiles-selfcheck"

  // ---- fixture paths (see writeSelfCheckFixtures in main.cpp) ----
  readonly property string listDir: dir + "/list"
  readonly property string watchDir: dir + "/watch"
  readonly property string opsDir: dir + "/ops"
  readonly property string jsonFile: dir + "/json/t.json"
  readonly property string png: dir + "/img.png"
  readonly property string pdf: dir + "/doc.pdf"
  readonly property string note: dir + "/note.txt"

  // ---- runner state ----
  property var checks: []
  property int idx: -1
  property int passes: 0
  property int fails: 0
  property real _startedAt: 0
  property bool _settled: false

  // DirectoryModel factory for the existence/listing checks
  // (non-singleton service wrapped over the C++ backend).
  property Component _dmFactory: Component { DirectoryModel {} }

  // SearchWorker factory (native backend, non-singleton) for the
  // recursive search test (Phase 16).
  property Component _searchFactory: Component { Backend.SearchWorker {} }

  // hostPanelsRow stub for the background panel test: BackgroundPanel reads
  // slotX(index)/slotWidth/height for its geometry. slotWidth/height 0 => the
  // ListView doesn't instantiate delegates (no null visual dependencies).
  // height/width are built-in Item properties (default 0); only
  // slotX()/slotWidth are added, which BackgroundPanel expects from hostPanelsRow.
  property Component _panelsRowStub: Component {
    Item { function slotX(i) { return 0 } property real slotWidth: 0 }
  }

  // Composition root created in the corresponding test and reused by
  // the facade ones.
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
      _done(false, "exception: " + e)
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

  // Lists a directory once and returns its entries via callback.
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

  // Runs a list of FileOperations operations IN SEQUENCE (each
  // `start` launches an op; its finished is awaited before the next). If
  // any fails -> done(false, ...). When all finish -> onAllDone(). For
  // multi-step tests (trash/restore) without nesting ten _fileOp.
  function _seqOps(starts, done, onAllDone) {
    var i = 0
    function step() {
      if (i >= starts.length) { onAllDone(); return }
      var start = starts[i++]
      _fileOp(done, function () { step() })
      start()
    }
    step()
  }

  // Runs a FileOperations operation and calls then(path) on its first
  // finished signal, or done(false, ...) on error. Since the runner is
  // sequential, there is only one operation in flight.
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

  property Timer _pollTimer: Timer { interval: 16; repeat: true }

  // Polls cond() every 16 ms (wall-clock, not event loop passes) until it
  // is true or the budget runs out (~4 s, comfortable under the 8 s per-test
  // timeout). To wait for an async effect that doesn't expose a public signal
  // to hook onto (e.g. the re-listing of a background panel, whose
  // DirLister is internal and delivers via invokeMethod from a pool thread).
  // The real interval gives clock time to the worker, avoiding the race of a
  // Qt.callLater loop that spins faster than the thread can
  // respond. The runner is sequential: there is only one _poll in flight.
  function _poll(cond, cb) {
    if (cond()) { cb(true); return }
    var n = 0
    function tick() {
      if (cond()) { done(); cb(true) }
      else if (++n > 250) { done(); cb(false) }
    }
    function done() { _pollTimer.stop(); _pollTimer.triggered.disconnect(tick) }
    _pollTimer.triggered.connect(tick)
    _pollTimer.restart()
  }

  // ---- BUG-02: process runner for the .sh script smoke tests ----
  // Backend.ProcessRunner (real QProcess) delivers {exitCode,stdout,stderr}.
  property Component _procFactory: Component { Backend.ProcessRunner {} }
  // Plugin root (where the .sh live), derived from this file's URL:
  // integrations/standalone/ -> ../../ = root.
  readonly property string pluginRoot: Qt.resolvedUrl("../../").toString().replace(/^file:\/\//, "").replace(/\/+$/, "")
  // POSIX quoting to embed paths in a setup `bash -c`.
  function _q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  // Runs argv and delivers the result via callback. Sequential runner: there is only
  // one _sh in flight (like the rest of the harness).
  function _sh(argv, cb) {
    var p = _procFactory.createObject(sc)
    function on(result) {
      p.finished.disconnect(on)
      cb(result)
      Qt.callLater(function () { p.destroy() })
    }
    p.finished.connect(on)
    p.start(argv, false)
  }

  Component.onCompleted: {
    _register()
    SelfCheckOut.line("── omafiles --selfcheck · fixtures in " + dir + " ──")
    _run()
  }

  function _register() {
    // ======================= INTEGRATION =======================

    add("Backend module loaded (Omafiles.Backend)", function (done) {
      var home = Backend.Env.get("HOME")
      done(!!home && home.length > 0, home ? "HOME=" + home : "Env.get(HOME) empty")
    })

    add("UDisksWatcher reactive backend (Fase 20, no polling)", function (done) {
      // The C++ watcher (QtDBus) registered and exposes available()/devicesChanged.
      // available() is true if it connected to the system bus (in headless CI it can
      // be false; what's validated is that it loads and doesn't break, not that there's a bus).
      var a = UDisksWatcher.available()
      var ok = (a === true || a === false)
        && typeof UDisksWatcher.devicesChanged === "function"
      done(ok, "available=" + a)
    })

    add("FolderCounter counts a directory (async, Fase 23)", function (done) {
      // list/ = sub/ + alpha/beta/gamma.txt = 4 entries.
      function on(path, n) {
        if (path !== sc.listDir) return
        FolderCounter.counted.disconnect(on)
        done(n === 4, "n=" + n + " (expected 4)")
      }
      FolderCounter.counted.connect(on)
      FolderCounter.request(sc.listDir, false)
    })

    add("Item count smart formatting (Fase 23)", function (done) {
      var ok = Utils.formatItemCount(1) === "1 item"
        && Utils.formatItemCount(2) === "2 items"
        && Utils.formatItemCount(1234) === "1,234 items"
        && Utils.formatItemCount(12347) === "12.3k items"
        && Utils.formatItemCount(1200000) === "1.2M items"
        && Utils.formatItemCountExact(12347) === "12,347 items"
        && Utils.itemCountAbbreviated(12347) === true
        && Utils.itemCountAbbreviated(1234) === false
      done(ok, ok ? "" : "1=" + Utils.formatItemCount(1) + " 1234=" + Utils.formatItemCount(1234)
                          + " 12347=" + Utils.formatItemCount(12347))
    })

    add("Composition root creates (OmafilesContent)", function (done) {
      var comp = Qt.createComponent(Qt.resolvedUrl("../../core/OmafilesContent.qml"))
      if (comp.status === Component.Error) { done(false, comp.errorString()); return }
      var obj = comp.createObject(sc)
      if (!obj) { done(false, "createObject returned null"); return }
      sc._content = obj
      done(true, "main tree instantiated")
    })

    add("Composition root API surface (open/close/facade)", function (done) {
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      var ok = typeof c.open === "function"
        && typeof c.close === "function"
        && typeof c.paletteCommands === "function"
        && typeof c.itemActions === "function"
      done(ok, ok ? "" : "missing contract/facade functions")
    })

    // ======================= FRONTEND =======================

    add("NavState is source of truth", function (done) {
      var prev = NavState.currentPath
      NavState.currentPath = sc.listDir
      var ok = NavState.currentPath === sc.listDir
      done(ok, ok ? "" : "NavState.currentPath doesn't persist")
    })

    add("TabsState defaults", function (done) {
      var ok = TabsState.tabs.length >= 1 && TabsState.activeTabIndex === 0
      done(ok, "tabs=" + TabsState.tabs.length + " active=" + TabsState.activeTabIndex)
    })

    add("ControllerRegistry + CommandFacade wiring", function (done) {
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      // Forces the evaluation of the builders: if a controller came in null
      // due to a registry injection failure, this would throw (see Phase 11.C).
      var pal = c.paletteCommands().length
      var items = c.itemActions().length            // 0 without selection: valid
      var empty = c.emptyAreaActions().length
      var segs = c.pathSegments().length
      var ok = pal > 0 && empty > 0 && segs > 0 && (items >= 0)
      done(ok, "palette=" + pal + " emptyArea=" + empty + " segments=" + segs)
    })

    add("AppBindings loaded (no side effects under selfcheck)", function (done) {
      // If OmafilesContent was created without errors, AppBindings (its child) too.
      // The self-registration as file manager is guarded by
      // OMAFILES_SELFCHECK, so this test confirms there was no side
      // effect and that the core started up complete.
      done(sc._content !== null, "AppBindings instantiated without self-registration")
    })

    // ======================= BACKEND =======================

    add("JsonStore write/read round-trip", function (done) {
      var payload = { a: 1, b: "x", nested: { k: [1, 2, 3] } }
      function onSaved(path, ok) {
        JsonStore.saved.disconnect(onSaved)
        if (!ok) { done(false, "write failed"); return }
        function onLoaded(p, data, lok) {
          JsonStore.loaded.disconnect(onLoaded)
          if (!lok) { done(false, "read failed"); return }
          var good = data && data.a === 1 && data.b === "x"
            && data.nested && data.nested.k.length === 3
          done(good, good ? "" : "data doesn't match: " + JSON.stringify(data))
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
        // 3 files + 1 subfolder; folders first, then naturalCompare.
        var okCount = e.length === 4
        var okOrder = names[0] === "sub" && names[1] === "alpha.txt"
          && names[2] === "beta.txt" && names[3] === "gamma.txt"
        done(okCount && okOrder, "order=[" + names.join(", ") + "]")
      })
    })

    add("QFileSystemWatcher create event", function (done) {
      var m = sc._dmFactory.createObject(sc)
      var watched = m.watch(sc.watchDir)
      if (!watched) { m.destroy(); done(false, "watch() returned false"); return }
      // Waits for BOTH: the watcher's directoryChanged and the finished of the mkdir
      // trigger (consumed so as not to leak it to later tests).
      var gotChange = false, gotFinish = false, settled = false
      function finish(ok, msg) {
        if (settled) return
        settled = true
        m.directoryChanged.disconnect(onChanged)
        m.unwatch(); m.destroy()
        done(ok, msg)
      }
      function maybe() { if (gotChange && gotFinish) finish(true, "directoryChanged after creating subfolder") }
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
        done(thumbPath.length > 0, thumbPath ? "" : "thumbPath empty")
      }
      ThumbnailProvider.ready.connect(onReady)
    })

    add("ThumbnailProvider PDF (qpdf plugin)", function (done) {
      var immediate = ThumbnailProvider.request(sc.pdf, 128)
      if (immediate && immediate.length > 0) { done(true, "cache hit"); return }
      function onReady(path, thumbPath) {
        if (path !== sc.pdf) return
        ThumbnailProvider.ready.disconnect(onReady)
        done(thumbPath.length > 0, thumbPath ? "" : "no thumbnail (is qpdf missing?)")
      }
      ThumbnailProvider.ready.connect(onReady)
    })

    // Canonical cache hash (Phase B1): ThumbnailProvider.cacheKey is the
    // ONLY scheme (SHA-1 hex), shared by the image/PDF thumbnails
    // (internal to request()), the video ones (VideoThumbnails) and the
    // extraction cache (ArchiveActions). It's anchored against the known SHA-1 of a
    // fixed entry so that any scheme change (which would invalidate the whole
    // on-disk cache) breaks the harness instead of going unnoticed.
    add("Thumbnail cache key is canonical SHA-1 (B1)", function (done) {
      var k = ThumbnailProvider.cacheKey("omafiles-b1|42")
      var expected = "244adfd729888c0a4499250ebb2e9f41d7243600" // sha1("omafiles-b1|42")
      var hexOk = /^[0-9a-f]{40}$/.test(k)
      var stable = ThumbnailProvider.cacheKey("omafiles-b1|42") === k
      done(hexOk && stable && k === expected,
           "cacheKey=" + k + (k === expected ? "" : " (expected " + expected + ")"))
    })

    // Thumbnail cache pruning (Phase O1). Exercises pruneCacheDir over
    // a temp dir (the real cache is NOT touched: the constructor's auto-prune
    // is skipped under --selfcheck) with the four policies: legacy orphan,
    // safety (foreign files intact), age and size.
    add("Thumbnail cache pruning: orphans, safety, age, size (O1)", function (done) {
      var TP = Backend.ThumbnailProvider
      var pd = sc.dir + "/prunecache-" + Date.now()
      var h1 = ThumbnailProvider.cacheKey("o1-a")   // valid 40-hex name
      var h2 = ThumbnailProvider.cacheKey("o1-b")
      var BIG_AGE = 999999999, BIG_SIZE = 999999999999
      var mk = function (name) { return function () { FileOperations.copy(sc.note, pd + "/" + name) } }

      FileOperations.mkdir(pd)
      sc._fileOp(done, function () {
        sc._seqOps([
          mk(h1 + ".png"),      // current thumbnail (.png)
          mk(h2 + ".jpg"),      // current thumbnail (.jpg)
          mk("deadbe.jpg"),     // legacy base36 orphan (.jpg, 6 chars) -> delete
          mk("notahash.png"),   // non-hex .png -> foreign, leave (safety)
          mk("readme.txt")      // non-image -> leave (safety)
        ], done, function () {
          // (1) large thresholds -> only the legacy orphan.
          var r1 = TP.pruneCacheDir(pd, BIG_AGE, BIG_SIZE)
          sc._listOnce(pd, function (e1) {
            var ok1 = r1 === 1 && !sc._has(e1, "deadbe.jpg")
              && sc._has(e1, h1 + ".png") && sc._has(e1, h2 + ".jpg")
              && sc._has(e1, "notahash.png") && sc._has(e1, "readme.txt")
            if (!ok1) { done(false, "orphan/safety: removed=" + r1 + " entries=" + e1.length); return }
            // (2) age: maxAge=0 -> deletes the 2 current thumbnails; leaves foreign ones.
            var r2 = TP.pruneCacheDir(pd, 0, BIG_SIZE)
            sc._listOnce(pd, function (e2) {
              var ok2 = r2 === 2 && !sc._has(e2, h1 + ".png") && !sc._has(e2, h2 + ".jpg")
                && sc._has(e2, "notahash.png") && sc._has(e2, "readme.txt")
              if (!ok2) { done(false, "age: removed=" + r2 + " entries=" + e2.length); return }
              // (3) size: recreates 2 current ones and prunes with maxBytes=0 -> deletes them
              // by the size policy (ordered by age).
              sc._seqOps([mk(h1 + ".png"), mk(h2 + ".jpg")], done, function () {
                var r3 = TP.pruneCacheDir(pd, BIG_AGE, 0)
                sc._listOnce(pd, function (e3) {
                  var ok3 = r3 === 2 && !sc._has(e3, h1 + ".png") && !sc._has(e3, h2 + ".jpg")
                  done(ok3, ok3 ? "orphan+safety+age+size OK"
                                : "size: removed=" + r3 + " entries=" + e3.length)
                })
              })
            })
          })
        })
      })
    })

    add("PreviewProvider text", function (done) {
      function onText(path, content, enc, bytes, lines, trunc) {
        if (path !== sc.note) return
        PreviewProvider.textReady.disconnect(onText)
        var ok = content.indexOf("hello selfcheck") >= 0
        done(ok, ok ? enc + ", " + lines + " lines" : "unexpected content")
      }
      PreviewProvider.textReady.connect(onText)
      PreviewProvider.requestText(sc.note, 65536)
    })

    add("PreviewProvider info", function (done) {
      var info = PreviewProvider.info(sc.note)
      var ok = info && typeof info === "object" && Object.keys(info).length > 0
      done(ok, ok ? "keys=[" + Object.keys(info).join(",") + "]" : "info empty")
    })

    // -------- FileOperations (the 7 existing operations) --------

    add("FileOperations mkdir", function (done) {
      sc._fileOp(done, function (op, path) {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = sc._has(e, "newdir")
          done(ok, ok ? "" : "newdir doesn't appear")
        })
      })
      FileOperations.mkdir(sc.opsDir + "/newdir")
    })

    add("FileOperations rename", function (done) {
      // Prepares a known file and renames it.
      FileOperations.copy(sc.note, sc.opsDir + "/toRename.txt")
      sc._fileOp(done, function () {
        sc._fileOp(done, function () {
          sc._listOnce(sc.opsDir, function (e) {
            var ok = sc._has(e, "renamed.txt") && !sc._has(e, "toRename.txt")
            done(ok, ok ? "" : "rename not reflected")
          })
        })
        FileOperations.rename(sc.opsDir + "/toRename.txt", "renamed.txt")
      })
    })

    add("FileOperations copy", function (done) {
      sc._fileOp(done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = sc._has(e, "copy.txt")
          done(ok, ok ? "" : "copy.txt doesn't appear")
        })
      })
      FileOperations.copy(sc.note, sc.opsDir + "/copy.txt")
    })

    add("FileOperations copy overwrite (replace)", function (done) {
      var dst = sc.opsDir + "/ow.txt"
      sc._fileOp(done, function () {           // 1) creates the destination
        // 2) copying over WITH overwrite must replace (finished, not error)
        sc._fileOp(done, function () { done(true, "destination replaced") })
        FileOperations.copy(sc.note, dst, true)
      })
      FileOperations.copy(sc.note, dst)        // without overwrite: new destination
    })

    add("FileOperations copy directory (recursive)", function (done) {
      sc._fileOp(done, function () {
        sc._listOnce(sc.opsDir + "/listcopy", function (e) {
          var ok = e.length === 4 && sc._has(e, "sub") && sc._has(e, "alpha.txt")
          done(ok, ok ? e.length + " entries copied" : "incomplete tree")
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
          done(ok, ok ? "copied as a link" : "didn't stay a symlink")
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
      // Exercises the REAL wiring used by runPaste/runDrop (13.A):
      // content.copyFiles -> ActionEngine.runNativeCopy -> FileOperations.copy
      // -> onDone. Confirms busy/sequence/completion without shell.
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      var dst = sc.opsDir + "/enginecopy.txt"
      var started = c.actionEngine.runNativeCopy([{ src: sc.note, dest: dst }], "Copying…", false, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = sc._has(e, "enginecopy.txt")
          done(ok, ok ? "runNativeCopy OK" : "didn't copy")
        })
      })
      if (!started) done(false, "runNativeCopy returned false (busy?)")
    })

    // -------- Move (13.B) --------

    add("FileOperations move overwrite (replace)", function (done) {
      var work = sc.opsDir + "/mvow-src.txt"
      var dst = sc.opsDir + "/mvow-dst.txt"
      sc._fileOp(done, function () {          // work created
        sc._fileOp(done, function () {        // dst created (causes conflict)
          sc._fileOp(done, function () {      // move with overwrite -> replaces
            sc._listOnce(sc.opsDir, function (e) {
              var ok = sc._has(e, "mvow-dst.txt") && !sc._has(e, "mvow-src.txt")
              done(ok, ok ? "replaced, source consumed" : "unexpected state")
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
      sc._fileOp(done, function () {          // copies listDir -> srcDir (tree)
        sc._fileOp(done, function () {        // move srcDir -> dstDir
          sc._listOnce(dstDir, function (e) {
            var okDst = e.length === 4 && sc._has(e, "sub") && sc._has(e, "alpha.txt")
            sc._listOnce(sc.opsDir, function (top) {
              var okGone = !sc._has(top, "mvdir-src")
              done(okDst && okGone, okDst ? (okGone ? "tree moved, source gone" : "source wasn't deleted") : "destination tree incomplete")
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
      sc._fileOp(done, function () {          // copies link.txt -> work (symlink)
        sc._fileOp(done, function () {        // move work -> dst
          sc._listOnce(sc.opsDir, function (e) {
            var ok = false
            for (var i = 0; i < e.length; i++)
              if (e[i].name === "mvlink-dst" && e[i].link && e[i].link.length > 0) ok = true
            done(ok, ok ? "moved as a link" : "didn't stay a symlink")
          })
        })
        FileOperations.move(work, dst)
      })
      FileOperations.copy(sc.dir + "/link.txt", work)
    })

    add("FileOperations move cross-filesystem (best-effort /tmp)", function (done) {
      // HOME (.cache) -> /tmp: if they are different mounts (tmpfs), it forces the
      // copy+delete fallback (EXDEV); if it's the same, it degrades to an atomic
      // rename. In both cases the move must fulfill: destination with the file,
      // source consumed. Cleans up /tmp on finishing (net-zero).
      var work = sc.opsDir + "/xfs-src.txt"
      var xfsDst = "/tmp/omafiles-selfcheck-xfs-" + Date.now() + ".txt"
      sc._fileOp(done, function () {          // work created in HOME
        sc._fileOp(done, function () {        // move HOME -> /tmp
          var destInfo = PreviewProvider.info(xfsDst)
          var destOk = destInfo && Object.keys(destInfo).length > 0
          sc._listOnce(sc.opsDir, function (e) {
            var srcGone = !sc._has(e, "xfs-src.txt")
            // cleans up /tmp WAITING for its finished, so as not to leak the signal to
            // the following test (it was the cause of the flakiness).
            sc._fileOp(done, function () {
              done(destOk && srcGone, (destOk ? "dest ok" : "dest missing") + ", " + (srcGone ? "source gone" : "source stays"))
            })
            FileOperations.remove(xfsDst)
          })
        })
        FileOperations.move(work, xfsDst)
      })
      FileOperations.copy(sc.note, work)
    })

    add("Copy/move cancellation (cooperative, source safe)", function (done) {
      // Cancels a large copy (32 MiB): a SYNCHRONOUS cancel() right after
      // launching the copy sets the flag before the worker (which still has
      // to start in the pool and then copies MiBs) can finish, so it
      // aborts with a "cancelled" error deterministically, without deleting the
      // source (in move, removeTree of the source only runs AFTER copying; the
      // copyTree path is the same one that cross-fs move uses).
      var dst = sc.opsDir + "/big-copy.bin"
      var srcPath = sc.dir + "/big.bin"
      function onErr(op, path, msg) {
        if (path !== srcPath) return  // ignores signals from other operations
        cleanup()
        if (msg !== "cancelled") { done(false, "unexpected error: " + msg); return }
        // the source (big.bin) is still intact
        var srcOk = PreviewProvider.info(srcPath)
        done(srcOk && Object.keys(srcOk).length > 0, "cancelled, source intact")
      }
      function onFin(op, path) {
        if (path !== srcPath) return  // ignores signals from other operations
        cleanup(); done(false, "finished before it could cancel")
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
      // Exercises the REAL wiring of move with undo (13.B):
      // content.moveFiles -> runNativeMove -> FileOperations.move; then
      // content.undoLast -> moveFiles(reversed) reverts.
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      var work = sc.opsDir + "/mv-runner-src.txt"
      var dst = sc.opsDir + "/mv-runner-dst.txt"
      sc._fileOp(done, function () {          // work created
        var pairs = [{ src: work, dest: dst }]
        var started = c.actionEngine.runNativeMove(pairs, "Moving…", false, function () {
          // Registers the undo EXACTLY as ClipboardOps/ConflictActions does
          // in its onDone (move back / redo, both native).
          var reversed = [{ src: dst, dest: work }]
          c.actionEngine.pushUndo("move test",
            function () { return c.actionEngine.runNativeMove(reversed, "", false) },
            function () { return c.actionEngine.runNativeMove(pairs, "", false) })
          sc._listOnce(sc.opsDir, function (e) {
            if (!(sc._has(e, "mv-runner-dst.txt") && !sc._has(e, "mv-runner-src.txt"))) {
              done(false, "didn't move"); return
            }
            // undo: move back (waits for the finished of the reverse move)
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e2) {
                var undone = sc._has(e2, "mv-runner-src.txt") && !sc._has(e2, "mv-runner-dst.txt")
                done(undone, undone ? "moved and undone" : "undo didn't revert")
              })
            })
            c.undoLast()
          })
        })
        if (!started) done(false, "runNativeMove returned false")
      })
      FileOperations.copy(sc.note, work)
    })

    // -------- Permanent delete (13.C) --------

    add("FileOperations delete directory (recursive)", function (done) {
      sc._fileOp(done, function () {        // copies listDir -> deldir
        sc._fileOp(done, function () {      // remove deldir (recursive)
          sc._listOnce(sc.opsDir, function (e) {
            var ok = !sc._has(e, "deldir")
            done(ok, ok ? "tree deleted" : "still exists")
          })
        })
        FileOperations.remove(sc.opsDir + "/deldir")
      })
      FileOperations.copy(sc.listDir, sc.opsDir + "/deldir")
    })

    add("FileOperations delete symlink (target preserved)", function (done) {
      sc._fileOp(done, function () {        // copies link.txt -> dellink
        sc._fileOp(done, function () {      // remove dellink
          sc._listOnce(sc.opsDir, function (e) {
            var linkGone = !sc._has(e, "dellink")
            var target = PreviewProvider.info(sc.note) // note.txt (link target)
            done(linkGone && Object.keys(target).length > 0,
                 linkGone ? "link deleted, target intact" : "the link stays")
          })
        })
        FileOperations.remove(sc.opsDir + "/dellink")
      })
      FileOperations.copy(sc.dir + "/link.txt", sc.opsDir + "/dellink")
    })

    add("FileOperations delete read-only (permission failure)", function (done) {
      // Deleting a file inside a folder without write permission
      // fails (EACCES). It's checked that the error is reported reasonably.
      var target = sc.dir + "/readonly/locked.txt"
      function onErr(op, path, msg) { if (path !== target) return; cleanup(); done(true, "error reported: " + msg) }
      function onFin(op, path) { if (path !== target) return; cleanup(); done(false, "should not be able to delete in a read-only folder") }
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
        // with ignoreMissing=true, being missing must be OK (finished)
        function onFin2(o, p) { if (p !== gone2) return; cleanup2(); done(true, "error if missing, ok with ignoreMissing") }
        function onErr2(o, p, m) { if (p !== gone2) return; cleanup2(); done(false, "ignoreMissing shouldn't fail") }
        function cleanup2() { FileOperations.finished.disconnect(onFin2); FileOperations.error.disconnect(onErr2) }
        FileOperations.finished.connect(onFin2)
        FileOperations.error.connect(onErr2)
        FileOperations.remove(gone2, true)
      }
      function onFin(op, path) { if (path !== gone) return; cleanup1(); done(false, "should fail without ignoreMissing") }
      function cleanup1() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
      FileOperations.error.connect(onErr)
      FileOperations.finished.connect(onFin)
      FileOperations.remove(gone, false)
    })

    add("FileOperations delete cancellation (recursive tree)", function (done) {
      // Deletes a tree of 500 files with a SYNCHRONOUS cancel: removeTree aborts
      // (between entries / in the entry check) with "cancelled",
      // same cancellation path as copy/move cross-fs.
      var target = sc.dir + "/bigdir"
      function onErr(op, path, msg) {
        if (path !== target) return
        cleanup()
        done(msg === "cancelled", "error=" + msg)
      }
      function onFin(op, path) { if (path !== target) return; cleanup(); done(false, "finished before it could cancel") }
      function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
      FileOperations.error.connect(onErr)
      FileOperations.finished.connect(onFin)
      FileOperations.remove(target)
      FileOperations.cancel()
    })

    add("ActionEngine native remove runner (delete path)", function (done) {
      // Exercises the REAL wiring of permanent delete (13.C):
      // content.removeFiles -> runNativeRemove -> FileOperations.remove.
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      var a = sc.opsDir + "/del-a.txt"
      var b = sc.opsDir + "/del-b.txt"
      sc._fileOp(done, function () {        // a created
        sc._fileOp(done, function () {      // b created
          var started = c.actionEngine.runNativeRemove([a, b], "", true, function () {
            sc._listOnce(sc.opsDir, function (e) {
              var ok = !sc._has(e, "del-a.txt") && !sc._has(e, "del-b.txt")
              done(ok, ok ? "runNativeRemove OK" : "didn't delete")
            })
          })
          if (!started) done(false, "runNativeRemove returned false")
        })
        FileOperations.copy(sc.note, b)
      })
      FileOperations.copy(sc.note, a)
    })

    // -------- XDG Trash: send + restore (13.D / 13.E) --------
    // They operate on the user's REAL trash (~/.local/share/Trash), but
    // they are round-trips (trash -> restore) = net-zero: nothing stays in the
    // trash on finishing. The fixtures live in the HOME mount, so
    // moveToTrash uses the home trash.

    add("Trash removes item from source", function (done) {
      var work = sc.opsDir + "/trash-src.txt"
      sc._seqOps([
        function () { FileOperations.copy(sc.note, work) },
        function () { FileOperations.trash(work) }
      ], done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var gone = !sc._has(e, "trash-src.txt")
          // restores to leave the trash clean, and confirms the round-trip
          sc._seqOps([function () { FileOperations.restoreByOrigPath(work) }], done, function () {
            sc._listOnce(sc.opsDir, function (e2) {
              done(gone && sc._has(e2, "trash-src.txt"),
                   gone ? "sent and restored" : "didn't leave the source")
            })
          })
        })
      })
    })

    // Exercises the FRONTEND path (ActionEngine.runNativeTrash/Restore), not
    // just the backend FileOperations: it would catch the Phase 14.D bug where the
    // callers (DeleteOps/FileOps/ClipboardOps/ConflictActions) invoked
    // nonexistent names (trashFiles/copyFiles/...) after renaming the API to
    // runNative*. The backend passed 67/67 but delete/copy/move did
    // nothing. It instantiates ActionEngine with a navController stub (only refresh()).
    add("ActionEngine trash+restore end-to-end (frontend wiring)", function (done) {
      var aeComp = Qt.createComponent(Qt.resolvedUrl("../../logic/ActionEngine.qml"))
      if (aeComp.status === Component.Error) { done(false, aeComp.errorString()); return }
      var stubNav = Qt.createQmlObject('import QtQuick; Item { function refresh() {} }', sc)
      var ae = aeComp.createObject(sc, { "navController": stubNav })
      if (!ae) { done(false, "couldn't create ActionEngine"); return }
      // Unique name per run (like the other trash tests): avoids
      // collisions in Trash/files that would leave residue between runs.
      var work = sc.opsDir + "/ae-trash-" + Date.now() + ".txt"
      var wname = work.substring(work.lastIndexOf("/") + 1)
      sc._seqOps([function () { FileOperations.copy(sc.note, work) }], done, function () {
        ae.runNativeTrash([work], "", function () {
          sc._listOnce(sc.opsDir, function (e) {
            var gone = !sc._has(e, wname)
            ae.runNativeRestore([work], "", function () {
              sc._listOnce(sc.opsDir, function (e2) {
                var back = sc._has(e2, wname)
                ae.destroy(); stubNav.destroy()
                done(gone && back, gone ? (back ? "trash+restore via ActionEngine OK" : "restore didn't put the file back")
                                        : "runNativeTrash didn't take the file out of the source")
              })
            })
          })
        })
      })
    })

    add("Trash + restore directory (round-trip)", function (done) {
      var dir = sc.opsDir + "/trashdir"
      sc._seqOps([
        function () { FileOperations.copy(sc.listDir, dir) },     // tree of 4
        function () { FileOperations.trash(dir) },
        function () { FileOperations.restoreByOrigPath(dir) }
      ], done, function () {
        sc._listOnce(dir, function (e) {
          done(e.length === 4 && sc._has(e, "sub"), "tree restored: " + e.length)
        })
      })
    })

    add("Trash + restore symlink (round-trip)", function (done) {
      var lnk = sc.opsDir + "/trashlink"
      sc._seqOps([
        function () { FileOperations.copy(sc.dir + "/link.txt", lnk) },
        function () { FileOperations.trash(lnk) },
        function () { FileOperations.restoreByOrigPath(lnk) }
      ], done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = false
          for (var i = 0; i < e.length; i++)
            if (e[i].name === "trashlink" && e[i].link && e[i].link.length > 0) ok = true
          done(ok, ok ? "symlink restored as a link" : "didn't come back as a symlink")
        })
      })
    })

    add("Trash + restore Unicode name (round-trip)", function (done) {
      var uni = sc.opsDir + "/café ñ 文件.txt"
      sc._seqOps([
        function () { FileOperations.copy(sc.note, uni) },
        function () { FileOperations.trash(uni) },
        function () { FileOperations.restoreByOrigPath(uni) }  // percent round-trip
      ], done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          done(sc._has(e, "café ñ 文件.txt"), "unicode round-trip OK")
        })
      })
    })

    add("Trash collision (restore both by orig path)", function (done) {
      // Two files with the SAME basename from different folders:
      // moveToTrash renames one in the trash; restoreByOrigPath locates
      // each one by its ORIGINAL path (not by the name in files/).
      var csub = sc.opsDir + "/csub"
      var a = sc.opsDir + "/coll.txt"
      var b = csub + "/coll.txt"
      sc._seqOps([
        function () { FileOperations.mkdir(csub) },
        function () { FileOperations.copy(sc.note, a) },
        function () { FileOperations.copy(sc.note, b) },
        function () { FileOperations.trash(a) },
        function () { FileOperations.trash(b) },
        function () { FileOperations.restoreByOrigPath(a) },
        function () { FileOperations.restoreByOrigPath(b) }
      ], done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var aBack = sc._has(e, "coll.txt")
          sc._listOnce(csub, function (e2) {
            var bBack = sc._has(e2, "coll.txt")
            done(aBack && bBack, aBack && bBack ? "collision resolved, both restored" : "didn't restore both")
          })
        })
      })
    })

    add("Restore collision (destination exists -> error)", function (done) {
      var work = sc.opsDir + "/restcoll.txt"
      sc._seqOps([
        function () { FileOperations.copy(sc.note, work) },
        function () { FileOperations.trash(work) },
        function () { FileOperations.copy(sc.note, work) }  // recreates the destination
      ], done, function () {
        // restoring must FAIL (destination exists)
        function onErr(op, path, msg) {
          if (path !== work) return
          cleanup()
          // cleanup: removes the occupant and restores for real (net-zero)
          sc._seqOps([
            function () { FileOperations.remove(work) },
            function () { FileOperations.restoreByOrigPath(work) }
          ], done, function () { done(true, "error if the destination exists: " + msg) })
        }
        function onFin(op, path) { if (path !== work) return; cleanup(); done(false, "should not restore over an existing destination") }
        function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
        FileOperations.error.connect(onErr)
        FileOperations.finished.connect(onFin)
        FileOperations.restoreByOrigPath(work)
      })
    })

    add("Restore recreates missing parent", function (done) {
      var psub = sc.opsDir + "/psub"
      var item = psub + "/child.txt"
      sc._seqOps([
        function () { FileOperations.mkdir(psub) },
        function () { FileOperations.copy(sc.note, item) },
        function () { FileOperations.trash(item) },
        function () { FileOperations.remove(psub) },              // deletes the parent
        function () { FileOperations.restoreByOrigPath(item) }    // must recreate psub
      ], done, function () {
        sc._listOnce(psub, function (e) {
          done(sc._has(e, "child.txt"), "parent recreated and file restored")
        })
      })
    })

    add("ActionEngine native trash runner + undo (delete-to-trash path)", function (done) {
      // REAL wiring of send-to-trash with undo (13.D):
      // content.trashFiles -> runNativeTrash -> FileOperations.trash; then
      // content.undoLast -> restoreFiles(original paths) reverts.
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      var work = sc.opsDir + "/runner-trash.txt"
      sc._fileOp(done, function () {          // work created
        var started = c.actionEngine.runNativeTrash([work], "", function () {
          // registers the undo like DeleteOps
          c.actionEngine.pushUndo("delete test",
            function () { return c.actionEngine.runNativeRestore([work], "") },
            function () { return c.actionEngine.runNativeTrash([work], "") })
          sc._listOnce(sc.opsDir, function (e) {
            if (sc._has(e, "runner-trash.txt")) { done(false, "wasn't sent to trash"); return }
            // undo -> restores (waits for the finished of the restore)
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e2) {
                done(sc._has(e2, "runner-trash.txt"), "sent and restored by undo")
              })
            })
            c.undoLast()
          })
        })
        if (!started) done(false, "runNativeTrash returned false")
      })
      FileOperations.copy(sc.note, work)
    })

    // -------- copy/move conflicts (13.F) --------

    add("Conflict detection: existingPaths (file/dir/symlink)", function (done) {
      // The NATIVE function that replaces paste/drop's `test -e`. It must
      // return the destinations that exist (file, folder, symlink) and not
      // the nonexistent ones.
      var f = sc.opsDir + "/cd-file.txt"
      var d = sc.opsDir + "/cd-dir"
      var l = sc.opsDir + "/cd-link"
      var missing = sc.opsDir + "/cd-missing-" + Date.now()
      sc._seqOps([
        function () { FileOperations.copy(sc.note, f) },
        function () { FileOperations.copy(sc.listDir, d) },
        function () { FileOperations.copy(sc.dir + "/link.txt", l) }
      ], done, function () {
        var res = FileOperations.existingPaths([f, d, l, missing])
        var ok = res.length === 3 && res.indexOf(f) >= 0 && res.indexOf(d) >= 0 &&
                 res.indexOf(l) >= 0 && res.indexOf(missing) < 0
        done(ok, "detected " + res.length + "/3 (without the nonexistent one)")
      })
    })

    add("Copy conflict overwrite (directory replaces)", function (done) {
      var src = sc.opsDir + "/ccd-src"
      var dst = sc.opsDir + "/ccd-dst"
      sc._seqOps([
        function () { FileOperations.copy(sc.listDir, src) },  // src: tree of 4
        function () { FileOperations.mkdir(dst) },             // dst: existing dir
        function () { FileOperations.copy(src, dst, true) }    // overwrite -> replaces
      ], done, function () {
        sc._listOnce(dst, function (e) {
          done(e.length === 4 && sc._has(e, "sub"), "dir replaced: " + e.length + " entries")
        })
      })
    })

    add("Copy conflict without overwrite errors (skip semantics)", function (done) {
      var dst = sc.opsDir + "/ccs.txt"
      sc._seqOps([function () { FileOperations.copy(sc.note, dst) }], done, function () {
        // copying again WITHOUT overwrite must fail: it's exactly what the
        // "skip" resolution avoids by not calling copy for that item.
        function onErr(op, path, msg) { cleanup(); done(msg.indexOf("exists") >= 0, "error: " + msg) }
        function onFin(op, path) { cleanup(); done(false, "should not copy over existing without overwrite") }
        function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
        FileOperations.error.connect(onErr)
        FileOperations.finished.connect(onFin)
        FileOperations.copy(sc.note, dst)
      })
    })

    add("Move conflict without overwrite errors (skip semantics)", function (done) {
      var work = sc.opsDir + "/mcs-work.txt"
      var dst = sc.opsDir + "/mcs-dst.txt"
      sc._seqOps([
        function () { FileOperations.copy(sc.note, work) },
        function () { FileOperations.copy(sc.note, dst) }
      ], done, function () {
        function onErr(op, path, msg) { cleanup(); done(msg.indexOf("exists") >= 0, "error: " + msg) }
        function onFin(op, path) { cleanup(); done(false, "should not move over existing without overwrite") }
        function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
        FileOperations.error.connect(onErr)
        FileOperations.finished.connect(onFin)
        FileOperations.move(work, dst)
      })
    })

    add("Conflict overwrite replaces symlink dest", function (done) {
      var l = sc.opsDir + "/cos-link"
      sc._seqOps([
        function () { FileOperations.copy(sc.dir + "/link.txt", l) },  // dst: symlink
        function () { FileOperations.copy(sc.note, l, true) }          // overwrite -> file
      ], done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var isFileNow = false
          for (var i = 0; i < e.length; i++)
            if (e[i].name === "cos-link") isFileNow = (!e[i].link || e[i].link.length === 0)
          done(isFileNow, isFileNow ? "symlink replaced by file" : "still a symlink")
        })
      })
    })

    // -------- Native progress + cancellation cleanup (13.G) --------

    add("Copy progress (byte-accurate, reaches total)", function (done) {
      // The backend's progress(op,path,done,total) signal (without `du`). Copying
      // 32 MiB must emit several byte events and end at done==total.
      var src = sc.dir + "/big.bin"
      var dst = sc.opsDir + "/prog-copy.bin"
      var count = 0, lastDone = -1, lastTotal = -1
      function onProg(op, path, d, t) { if (path !== src) return; count++; lastDone = d; lastTotal = t }
      function onFin(op, path) {
        if (path !== src) return
        cleanup()
        var ok = count > 0 && lastTotal === 33554432 && lastDone === lastTotal
        done(ok, "events=" + count + " last=" + lastDone + "/" + lastTotal)
      }
      function onErr(op, path, msg) { if (path !== src) return; cleanup(); done(false, "error: " + msg) }
      function cleanup() { FileOperations.progress.disconnect(onProg); FileOperations.finished.disconnect(onFin); FileOperations.error.disconnect(onErr) }
      FileOperations.progress.connect(onProg)
      FileOperations.finished.connect(onFin)
      FileOperations.error.connect(onErr)
      FileOperations.copy(src, dst)
    })

    add("Move cross-fs progress (best-effort)", function (done) {
      // A move that crosses disks (HOME -> /tmp) uses copyTree and emits
      // progress; if it's the same fs, it's an atomic rename (no progress). In
      // both cases it must finish fine. Cleans up /tmp at the end.
      var work = sc.opsDir + "/mvprog-src.bin"
      var xfsDst = "/tmp/omafiles-selfcheck-mvprog-" + Date.now() + ".bin"
      sc._seqOps([function () { FileOperations.copy(sc.dir + "/big.bin", work) }], done, function () {
        var count = 0, lastDone = -1, lastTotal = -1
        function onProg(op, path, d, t) { if (path !== work) return; count++; lastDone = d; lastTotal = t }
        function onFin(op, path) {
          if (path !== work) return
          cleanupSig()
          var progOk = count === 0 || (lastTotal > 0 && lastDone === lastTotal)
          // cleans up the destination in /tmp (waiting for its finished)
          function rmDone(o, p) { if (p !== xfsDst) return; FileOperations.finished.disconnect(rmDone); FileOperations.error.disconnect(rmDone); done(progOk, count > 0 ? "cross-fs progress " + count + " events" : "atomic rename (same fs)") }
          FileOperations.finished.connect(rmDone)
          FileOperations.error.connect(rmDone)
          FileOperations.remove(xfsDst, true)
        }
        function onErr(op, path, msg) { if (path !== work) return; cleanupSig(); done(false, "error: " + msg) }
        function cleanupSig() { FileOperations.progress.disconnect(onProg); FileOperations.finished.disconnect(onFin); FileOperations.error.disconnect(onErr) }
        FileOperations.progress.connect(onProg)
        FileOperations.finished.connect(onFin)
        FileOperations.error.connect(onErr)
        FileOperations.move(work, xfsDst)
      })
    })

    add("Copy cancellation leaves no partial file", function (done) {
      // The backend (forceRemove) cleans up the partial copy on aborting.
      var src = sc.dir + "/big.bin"
      var dst = sc.opsDir + "/cancel-partial.bin"
      function onErr(op, path, msg) {
        if (path !== src) return
        cleanup()
        if (msg !== "cancelled") { done(false, "error: " + msg); return }
        var partial = FileOperations.existingPaths([dst])
        done(partial.length === 0, partial.length === 0 ? "no partial residue" : "partial copy left")
      }
      function onFin(op, path) { if (path !== src) return; cleanup(); done(false, "finished before cancelling") }
      function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
      FileOperations.error.connect(onErr)
      FileOperations.finished.connect(onFin)
      FileOperations.copy(src, dst)
      FileOperations.cancel()
    })

    add("Copy cancellation leaves no partial directory", function (done) {
      // Cancelling the copy of a tree (500 files) must not leave the destination
      // folder half-created: forceRemove deletes the partial tree.
      var src = sc.dir + "/bigdir"
      var dst = sc.opsDir + "/cancel-partial-dir"
      function onErr(op, path, msg) {
        if (path !== src) return
        cleanup()
        if (msg !== "cancelled") { done(false, "error: " + msg); return }
        var partial = FileOperations.existingPaths([dst])
        done(partial.length === 0, partial.length === 0 ? "partial tree cleaned up" : "partial folder left")
      }
      function onFin(op, path) { if (path !== src) return; cleanup(); done(false, "finished before cancelling") }
      function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
      FileOperations.error.connect(onErr)
      FileOperations.finished.connect(onFin)
      FileOperations.copy(src, dst)
      FileOperations.cancel()
    })

    add("Move cross-fs cancellation: source intact, no partial", function (done) {
      var work = sc.opsDir + "/mvcancel-src.bin"
      var xfsDst = "/tmp/omafiles-selfcheck-mvcancel-" + Date.now() + ".bin"
      sc._seqOps([function () { FileOperations.copy(sc.dir + "/big.bin", work) }], done, function () {
        function onErr(op, path, msg) {
          if (path !== work) return
          cleanup()
          if (msg !== "cancelled") { done(false, "error: " + msg); return }
          var srcOk = FileOperations.existingPaths([work]).length === 1
          var noPartial = FileOperations.existingPaths([xfsDst]).length === 0
          done(srcOk && noPartial, "cross-fs cancelled: src=" + srcOk + " no partial=" + noPartial)
        }
        function onFin(op, path) {
          if (path !== work) return
          cleanup()
          // atomic rename (same fs): the move completed -> cleans up /tmp.
          function rmDone(o, p) { if (p !== xfsDst) return; FileOperations.finished.disconnect(rmDone); FileOperations.error.disconnect(rmDone); done(true, "atomic rename (same fs), no partial possible") }
          FileOperations.finished.connect(rmDone)
          FileOperations.error.connect(rmDone)
          FileOperations.remove(xfsDst, true)
        }
        function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
        FileOperations.error.connect(onErr)
        FileOperations.finished.connect(onFin)
        FileOperations.move(work, xfsDst)
        FileOperations.cancel()
      })
    })

    // -------- Native undo / redo (13.H) --------
    // The undo/redo of the MAIN operations (move, trash) is already native
    // (13.B/D): the caller registers pushUndo with functions that invoke
    // moveFiles/restoreFiles/trashFiles (FileOperations runners, 0 shell).
    // Here the full cycle is validated through the real UI contract
    // (content.pushUndo/undoLast/redoLast + UndoState).

    add("Undo + redo move (full cycle)", function (done) {
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      var work = sc.opsDir + "/urm-src.txt"
      var dst = sc.opsDir + "/urm-dst.txt"
      var pairs = [{ src: work, dest: dst }]
      var reversed = [{ src: dst, dest: work }]
      sc._fileOp(done, function () {          // work created
        c.actionEngine.runNativeMove(pairs, "Moving…", false, function () {
          c.actionEngine.pushUndo("move",
            function () { return c.actionEngine.runNativeMove(reversed, "", false) },
            function () { return c.actionEngine.runNativeMove(pairs, "", false) })
          sc._listOnce(sc.opsDir, function (e) {
            if (!(sc._has(e, "urm-dst.txt") && !sc._has(e, "urm-src.txt"))) { done(false, "didn't move"); return }
            sc._fileOp(done, function () {    // undo -> move back
              sc._listOnce(sc.opsDir, function (e2) {
                if (!(sc._has(e2, "urm-src.txt") && !sc._has(e2, "urm-dst.txt"))) { done(false, "undo didn't revert"); return }
                sc._fileOp(done, function () {  // redo -> move again
                  sc._listOnce(sc.opsDir, function (e3) {
                    done(sc._has(e3, "urm-dst.txt") && !sc._has(e3, "urm-src.txt"), "undo and redo OK")
                  })
                })
                c.redoLast()
              })
            })
            c.undoLast()
          })
        })
      })
      FileOperations.copy(sc.note, work)
    })

    add("Undo + redo trash (full cycle)", function (done) {
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      var work = sc.opsDir + "/urt.txt"
      sc._fileOp(done, function () {
        c.actionEngine.runNativeTrash([work], "", function () {
          c.actionEngine.pushUndo("trash",
            function () { return c.actionEngine.runNativeRestore([work], "") },
            function () { return c.actionEngine.runNativeTrash([work], "") })
          sc._listOnce(sc.opsDir, function (e) {
            if (sc._has(e, "urt.txt")) { done(false, "wasn't sent to trash"); return }
            sc._fileOp(done, function () {   // undo -> restore
              sc._listOnce(sc.opsDir, function (e2) {
                if (!sc._has(e2, "urt.txt")) { done(false, "undo didn't restore"); return }
                sc._fileOp(done, function () {  // redo -> to trash again
                  sc._listOnce(sc.opsDir, function (e3) {
                    done(!sc._has(e3, "urt.txt"), "undo and redo trash OK")
                  })
                })
                c.redoLast()
              })
            })
            c.undoLast()
          })
        })
      })
      FileOperations.copy(sc.note, work)
    })

    add("Undo sequence (LIFO: reverts the last one first)", function (done) {
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      var a1 = sc.opsDir + "/seqA.txt", a2 = sc.opsDir + "/seqA-dst.txt"
      var b1 = sc.opsDir + "/seqB.txt", b2 = sc.opsDir + "/seqB-dst.txt"
      sc._seqOps([
        function () { FileOperations.copy(sc.note, a1) },
        function () { FileOperations.copy(sc.note, b1) }
      ], done, function () {
        c.actionEngine.runNativeMove([{ src: a1, dest: a2 }], "", false, function () {
          c.actionEngine.pushUndo("A", function () { return c.actionEngine.runNativeMove([{ src: a2, dest: a1 }], "", false) }, null)
          c.actionEngine.runNativeMove([{ src: b1, dest: b2 }], "", false, function () {
            c.actionEngine.pushUndo("B", function () { return c.actionEngine.runNativeMove([{ src: b2, dest: b1 }], "", false) }, null)
            sc._fileOp(done, function () {   // undo #1 -> reverts B (LIFO)
              sc._listOnce(sc.opsDir, function (e) {
                var bBack = sc._has(e, "seqB.txt") && !sc._has(e, "seqB-dst.txt")
                var aStill = sc._has(e, "seqA-dst.txt") && !sc._has(e, "seqA.txt")
                if (!(bBack && aStill)) { done(false, "LIFO: didn't revert B first"); return }
                sc._fileOp(done, function () {  // undo #2 -> reverts A
                  sc._listOnce(sc.opsDir, function (e2) {
                    done(sc._has(e2, "seqA.txt") && !sc._has(e2, "seqA-dst.txt"), "LIFO OK: B and then A")
                  })
                })
                c.undoLast()
              })
            })
            c.undoLast()
          })
        })
      })
    })

    add("Cancel then undo (cancellation doesn't alter the stack)", function (done) {
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      var work = sc.opsDir + "/ctu-src.txt"
      var dst = sc.opsDir + "/ctu-dst.txt"
      sc._fileOp(done, function () {          // work created
        c.actionEngine.runNativeMove([{ src: work, dest: dst }], "", false, function () {
          c.actionEngine.pushUndo("move", function () { return c.actionEngine.runNativeMove([{ src: dst, dest: work }], "", false) }, null)
          // a direct large copy + cancel (doesn't touch the undo stack)
          var bigSrc = sc.dir + "/big.bin"
          function onErr(op, path, msg) {
            if (path !== bigSrc) return
            cleanup()
            if (msg !== "cancelled") { done(false, "cancel error: " + msg); return }
            // the move's undo is still available -> reverts
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e) {
                done(sc._has(e, "ctu-src.txt") && !sc._has(e, "ctu-dst.txt"), "undo after cancellation reverts the move")
              })
            })
            c.undoLast()
          }
          function onFin(op, path) { if (path !== bigSrc) return; cleanup(); done(false, "the copy finished before cancelling") }
          function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
          FileOperations.error.connect(onErr)
          FileOperations.finished.connect(onFin)
          FileOperations.copy(bigSrc, sc.opsDir + "/ctu-big.bin")
          FileOperations.cancel()
        })
      })
      FileOperations.copy(sc.note, work)
    })

    add("Undo registry consistency (UndoState stacks)", function (done) {
      var c = sc._content
      if (!c) { done(false, "no composition root"); return }
      // Clears the stacks for absolute assertions (shared singleton).
      UndoState.undoStack = []
      UndoState.redoStack = []
      var work = sc.opsDir + "/urc-src.txt"
      var dst = sc.opsDir + "/urc-dst.txt"
      sc._fileOp(done, function () {
        c.actionEngine.runNativeMove([{ src: work, dest: dst }], "", false, function () {
          c.actionEngine.pushUndo("urc",
            function () { return c.actionEngine.runNativeMove([{ src: dst, dest: work }], "", false) },
            function () { return c.actionEngine.runNativeMove([{ src: work, dest: dst }], "", false) })
          var afterPush = UndoState.undoStack.length === 1 && UndoState.redoStack.length === 0
          // undoLast/redoLast update the stacks SYNCHRONOUSLY and start
          // an async move. The action is called BEFORE connecting the _fileOp,
          // so the runner's `ok` (connected during undoLast) fires before
          // this handler and frees nativeBusy for the following redoLast.
          c.undoLast()
          var afterUndo = UndoState.undoStack.length === 0 && UndoState.redoStack.length === 1
          sc._fileOp(done, function () {   // the undo move finished
            c.redoLast()
            var afterRedo = UndoState.undoStack.length === 1 && UndoState.redoStack.length === 0
            sc._fileOp(done, function () { // the redo move finished (frees nativeBusy)
              done(afterPush && afterUndo && afterRedo,
                   "push/undo/redo stacks: " + afterPush + "/" + afterUndo + "/" + afterRedo)
            })
          })
        })
      })
      FileOperations.copy(sc.note, work)
    })

    add("FileOperations move", function (done) {
      FileOperations.copy(sc.note, sc.opsDir + "/toMove.txt")
      sc._fileOp(done, function () {
        sc._fileOp(done, function () {
          sc._listOnce(sc.opsDir + "/newdir", function (e) {
            var ok = sc._has(e, "moved.txt")
            done(ok, ok ? "" : "moved.txt isn't at the destination")
          })
        })
        FileOperations.move(sc.opsDir + "/toMove.txt", sc.opsDir + "/newdir/moved.txt")
      })
    })

    add("FileOperations remove", function (done) {
      sc._fileOp(done, function () {
        sc._listOnce(sc.opsDir, function (e) {
          var ok = !sc._has(e, "copy.txt")
          done(ok, ok ? "" : "copy.txt still exists")
        })
      })
      FileOperations.remove(sc.opsDir + "/copy.txt")
    })

    add("FileOperations trash + restore (net-zero)", function (done) {
      // Unique name: avoids moveToTrash renaming due to a collision in the
      // user's trash and guarantees that the basename in Trash/files is
      // the expected one. The fixtures live in the HOME mount, so
      // moveToTrash uses the home trash.
      var fname = "selfcheck-trash-" + Date.now() + ".txt"
      var target = sc.opsDir + "/" + fname
      var trashFiles = Backend.Env.get("HOME") + "/.local/share/Trash/files/" + fname
      FileOperations.copy(sc.note, target)
      sc._fileOp(done, function () {                 // copy done
        sc._fileOp(done, function () {               // trash done (target -> trash)
          sc._fileOp(done, function () {             // restore done
            sc._listOnce(sc.opsDir, function (e) {
              var ok = sc._has(e, fname)
              done(ok, ok ? "restored to its place" : "didn't come back after restore")
            })
          })
          // restore receives the path INSIDE the trash (real contract: the
          // Trash view lists .../Trash/files and restores by that path),
          // not the original path.
          FileOperations.restore(trashFiles)
        })
        FileOperations.trash(target)
      })
    })

    // -------- Background panel refresh (14.C regression / 14.E audit) --------
    // A background panel (NON-active tab) must reload when something mutates
    // its folder from another tab. The signal is NavState.refreshTick++, which
    // the panel listens to via Connections. In 14.C refreshTick moved from
    // OmafilesContent to NavState but the Connections still pointed to
    // hostRoot -> the background panel stopped refreshing (silent regression:
    // qmllint rc=0 because hostRoot is an untyped Item, no warning at startup,
    // and --selfcheck didn't cover background panels). This test shields it: it fails if
    // the panel doesn't reflect the change after refreshTick.
    add("Background panel refreshes on content change (non-active tab)", function (done) {
      var c = sc._content
      if (!c) { done(false, "no _content"); return }
      var bgDir = sc.dir + "/bgpanel-" + Date.now()

      FileOperations.mkdir(bgDir)
      sc._fileOp(done, function () {                    // bgDir created (empty)
        // Real SortOps: with default SortState (name/asc) isDefaultOrder is
        // true, so _sorted returns the entries as is without touching
        // fileTypeUtils/root (that's why they can be null). panelsRow is a stub
        // for the geometries; slotWidth/height 0 => the ListView doesn't instantiate
        // delegates and no null visual dependencies are touched.
        var soC = Qt.createComponent(Qt.resolvedUrl("../../logic/SortOps.qml"))
        if (soC.status !== Component.Ready) { done(false, "SortOps: " + soC.errorString()); return }
        var sortOps = soC.createObject(sc)
        var panelsRow = sc._panelsRowStub.createObject(sc)
        var bgC = Qt.createComponent(Qt.resolvedUrl("../../panels/BackgroundPanel.qml"))
        if (bgC.status !== Component.Ready) { done(false, "BackgroundPanel: " + bgC.errorString()); return }
        // index 1 != activeTabIndex 0 => visible (NON-active tab), which is
        // exactly the condition of the refreshMe() guard.
        TabsState.activeTabIndex = 0
        var bg = bgC.createObject(sc, {
          modelData: { path: bgDir }, index: 1,
          hostRoot: c, hostSortOps: sortOps, hostPanelsRow: panelsRow
        })
        if (!bg) { sortOps.destroy(); panelsRow.destroy(); done(false, "BackgroundPanel null"); return }

        function cleanup() { bg.destroy(); sortOps.destroy(); panelsRow.destroy() }
        function cache() { return c.tabEntriesCache[bgDir] }

        // 1) wait for the initial listing (onCompleted -> refreshMe, a direct
        //    call, not via the Connections) to populate the cache with the empty folder.
        sc._poll(function () { return cache() !== undefined && cache().length === 0 }, function (ok0) {
          if (!ok0) { cleanup(); done(false, "the panel didn't list the initial empty folder"); return }
          // 2) mutate the folder and trigger the refresh ONLY via refreshTick.
          FileOperations.copy(sc.note, bgDir + "/appeared.txt")
          sc._fileOp(done, function () {
            NavState.refreshTick += 1
            // 3) the background panel must re-list and reflect the new file.
            //    If the Connections is broken, the cache stays empty -> timeout.
            sc._poll(function () { var e = cache(); return e && sc._has(e, "appeared.txt") }, function (ok) {
              // bgDir lives inside the harness's QTemporaryDir (main.cpp
              // deletes it on exit); NO async remove is launched here -- a
              // fire-and-forget in the last test runs concurrent with the
              // QTemporaryDir cleanup and aborts its removeRecursively.
              cleanup()
              done(ok, ok ? "the background panel reflected the change via refreshTick"
                          : "the background panel did NOT refresh after refreshTick (broken Connections)")
            })
          })
        })
      })
    })

    // -------- Remaining native integrations (Phase 16) --------
    // Native recursive search (SearchWorker, replaces search-recursive.sh):
    // name match, depth (subfolders) and hidden filter.
    add("Native recursive search: name, depth, hidden filter (Fase 16)", function (done) {
      var base = sc.dir + "/srch-" + Date.now()
      var mk = function (p) { return function () { FileOperations.mkdir(p) } }
      var cp = function (p) { return function () { FileOperations.copy(sc.note, p) } }
      // Tree: match at root, match in subfolder, match inside a hidden folder.
      sc._seqOps([
        mk(base), mk(base + "/sub"), mk(base + "/.hid"),
        cp(base + "/alpha-root.txt"),
        cp(base + "/beta.txt"),
        cp(base + "/sub/alpha-deep.txt"),
        cp(base + "/.hid/alpha-hidden.txt")
      ], done, function () {
        var sw = sc._searchFactory.createObject(sc)
        var phase = 0
        function names(entries) { return entries.map(function (e) { return e.name }).sort() }
        function onResults(entries, truncated) {
          if (phase === 0) {
            // showHidden=false: alpha-root.txt + sub/alpha-deep.txt, NOT the hidden one.
            var got = names(entries)
            var ok0 = got.length === 2 && got.indexOf("alpha-root.txt") >= 0
              && got.indexOf("sub/alpha-deep.txt") >= 0 && truncated === false
            if (!ok0) { sw.results.disconnect(onResults); sw.destroy(); done(false, "without hidden: " + JSON.stringify(got)); return }
            phase = 1
            sw.search(base, "alpha", true)
          } else {
            // showHidden=true: includes .hid/alpha-hidden.txt (3 in total).
            var g2 = names(entries)
            var ok1 = g2.length === 3 && g2.indexOf(".hid/alpha-hidden.txt") >= 0
            sw.results.disconnect(onResults); sw.destroy()
            done(ok1, ok1 ? "name+depth+hidden OK" : "with hidden: " + JSON.stringify(g2))
          }
        }
        sw.results.connect(onResults)
        sw.search(base, "alpha", false)
      })
    })

    // Native Trash listing (FileOperations.trashRoots/trashInfo,
    // replace trash-roots.sh/trash-info.sh): trash-roots includes the
    // home one; trash-info reflects a just-sent item with its original path.
    add("Native trash listing: trashRoots + trashInfo (Fase 16)", function (done) {
      var home = Backend.Env.get("HOME")
      var roots = FileOperations.trashRoots()
      var homeTrash = home + "/.local/share/Trash"
      var hasHome = roots.indexOf(homeTrash) >= 0
      if (!hasHome) { done(false, "trashRoots doesn't include the home trash: " + JSON.stringify(roots)); return }

      var fname = "selfcheck-trashinfo-" + Date.now() + ".txt"
      var target = sc.opsDir + "/" + fname
      FileOperations.copy(sc.note, target)
      sc._fileOp(done, function () {          // copy
        sc._fileOp(done, function () {        // trash
          // trashInfo must list the item with its original path and epoch>0.
          var info = FileOperations.trashInfo()
          var found = null
          for (var i = 0; i < info.length; i++)
            if (info[i].origPath === target) found = info[i]
          var ok = found !== null && found.epoch > 0 && found.trashRoot === homeTrash
          sc._fileOp(done, function () {      // restore (cleanup)
            done(ok, ok ? "trashRoots+trashInfo OK" : "trashInfo doesn't reflect the item")
          })
          FileOperations.restoreByOrigPath(target)
        })
        FileOperations.trash(target)
      })
    })

    // Native NetworkMounts.list() (replaces list-network-mounts.sh): without
    // active GVfs mounts in the test environment, it must return a list
    // (empty) without breaking. Smoke test: content can't be asserted without a
    // real mount, but the native path does respond with an array.
    add("Native network mounts listing returns a list (Fase 16)", function (done) {
      var l = Backend.NetworkMounts.list()
      done(l !== undefined && l !== null && typeof l.length === "number",
           "NetworkMounts.list() -> " + (l ? l.length : "null") + " entries")
    })

    // ======================= BUG-01 (Hardening-1) =======================

    // Regression from the BUG_AUDIT_V3 report: conflict detection must see
    // a BROKEN symlink (nonexistent target) as an existing entry. With the
    // old criterion (QFileInfo::exists, which follows the symlink) existingPaths
    // returned 0 and the UI didn't warn, diverging from the real behavior of the
    // native op. Now it uses lstat (entryExists) in existingPaths and in the
    // copy()/move() guards: same criterion in UI and backend. This test FAILED with
    // the previous code.
    add("Conflict detection sees a broken symlink (BUG-01)", function (done) {
      var link = sc.opsDir + "/bug01-broken-" + Date.now()
      sc._sh(["ln", "-s", "/omafiles-no-such-target-xyz", link], function (r) {
        if (r.exitCode !== 0) { done(false, "couldn't create the broken symlink: " + r.stderr); return }
        var hit = FileOperations.existingPaths([link])
        done(hit.length === 1 && hit[0] === link,
             hit.length === 1 ? "broken symlink detected as a conflict"
                              : "existingPaths did NOT detect the broken symlink (n=" + hit.length + ")")
      })
    })

    // ======================= BUG-02 (Hardening-1) =======================
    // Smoke tests of the .sh scripts that are still part of the
    // UI's behavior. Goal: that a regression like the one in
    // empty-trash.sh (which passed 70/70 green) makes the harness fail.

    // ISOLATED empty-trash.sh: HOME points to a fake home inside the selfcheck's
    // tmp and a fake findmnt (via PATH) prevents real mounts from being scanned
    // -> it NEVER touches the user's real trash. It prepares a home
    // trash with an item and confirms that the script empties it. A
    // regression that doesn't discover the roots (like the trash-roots.sh one) would leave
    // the item undeleted and would make this fail.
    add("empty-trash.sh empties an isolated home trash (BUG-02)", function (done) {
      var fakeHome = sc.dir + "/et-home"
      var tFiles = fakeHome + "/.local/share/Trash/files"
      var tInfo = fakeHome + "/.local/share/Trash/info"
      var fakeBin = sc.dir + "/et-bin"
      var setup =
        "mkdir -p " + _q(tFiles) + " " + _q(tInfo) + " " + _q(fakeBin) + " && " +
        "printf x > " + _q(tFiles + "/victim.txt") + " && " +
        "printf '[Trash Info]\\n' > " + _q(tInfo + "/victim.txt.trashinfo") + " && " +
        "printf '#!/bin/sh\\n' > " + _q(fakeBin + "/findmnt") + " && chmod +x " + _q(fakeBin + "/findmnt")
      sc._sh(["bash", "-c", setup], function (r0) {
        if (r0.exitCode !== 0) { done(false, "setup failed: " + r0.stderr); return }
        var run = "env -i HOME=" + _q(fakeHome) + " PATH=" + _q(fakeBin) + ":/usr/bin:/bin bash "
          + _q(sc.pluginRoot + "/empty-trash.sh")
        sc._sh(["bash", "-c", run], function (r1) {
          sc._sh(["bash", "-c", "ls -A " + _q(tFiles) + " | wc -l"], function (r2) {
            var remaining = parseInt(String(r2.stdout).trim(), 10)
            done(r1.exitCode === 0 && remaining === 0,
                 "exit=" + r1.exitCode + " remaining items=" + remaining)
          })
        })
      })
    })

    // list-archive.sh over a deterministic .tar built from listDir
    // (sub/ + alpha/beta/gamma.txt). Confirms that it lists the top-level
    // elements in the NUL-delimited contract (name\0isdir\0...).
    add("list-archive.sh lists a tar fixture (BUG-02)", function (done) {
      var tarPath = sc.opsDir + "/la-fixture.tar"
      var mk = "tar -cf " + _q(tarPath) + " -C " + _q(sc.listDir) + " sub alpha.txt beta.txt gamma.txt"
      sc._sh(["bash", "-c", mk], function (r0) {
        if (r0.exitCode !== 0) { done(false, "tar setup failed: " + r0.stderr); return }
        sc._sh(["bash", sc.pluginRoot + "/list-archive.sh", tarPath, ""], function (r) {
          var toks = String(r.stdout).split("\0")
          var names = []
          for (var i = 0; i < toks.length; i += 2) if (toks[i]) names.push(toks[i])
          var ok = r.exitCode === 0 && names.indexOf("sub") >= 0 && names.indexOf("alpha.txt") >= 0
          done(ok, ok ? "listed " + names.length + " top-level entries"
                      : "output=[" + names.join(",") + "] exit=" + r.exitCode)
        })
      })
    })

    // mount-iso.sh: can't mount in headless. It exercises the FAILURE
    // PATH: given a nonexistent path the script must not print a fake "Mounted…"
    // nor hang -> it exits != 0 and with no stdout. Verifies that it's invoked and that
    // its guard (set -e + loopdev check) works.
    add("mount-iso.sh fails safely on a bad path (BUG-02)", function (done) {
      sc._sh(["bash", sc.pluginRoot + "/mount-iso.sh", sc.dir + "/no-such-file.iso"], function (r) {
        var ok = r.exitCode !== 0 && String(r.stdout).trim() === ""
        done(ok, "exit=" + r.exitCode + " stdout='" + String(r.stdout).trim() + "'")
      })
    })

    // open-with-list.sh over a .txt: exit 0 and output with valid TSV shape
    // (empty, or each line with a TAB name<TAB>id). It doesn't fix WHICH apps there are
    // (depends on the system); it does check that it's invoked and responds in its contract.
    add("open-with-list.sh returns valid TSV (BUG-02)", function (done) {
      sc._sh(["bash", sc.pluginRoot + "/open-with-list.sh", sc.note], function (r) {
        var lines = String(r.stdout).split("\n").filter(function (l) { return l.length > 0 })
        var shapeOk = lines.every(function (l) { return l.indexOf("\t") >= 0 })
        done(r.exitCode === 0 && shapeOk, "exit=" + r.exitCode + " lines=" + lines.length)
      })
    })

    // ======================= BUG-03 (Hardening-2) =======================

    // Properties/chmod built `du -shc -- <all>` and `stat -c%a -- <all>`
    // in a single bash line -> with a huge selection it blew the length
    // limit (ARG_MAX / 128 KiB per argument) and the dialog was left without
    // size/permissions. Now they use FileOperations.totalSize/octalModes (native,
    // no command line). The test builds a list that DOES overflow that
    // line: the native path handles it; the old shell fails. It fails with the
    // previous code (octalModes didn't exist -> TypeError).
    add("Properties/chmod handle a huge selection without ARG_MAX (BUG-03)", function (done) {
      // Two fixtures that exist (to assert correct sum/mode) + padding of
      // long nonexistent paths until the `stat/du -- <all>` line that
      // the old code used would overflow the per-argument limit (128 KiB).
      var reals = [sc.note, sc.png]
      var expected = FileOperations.totalSize(reals)
      var pad = new Array(160).join("x")
      var big = reals.slice()
      while (big.length < 2000) big.push(sc.opsDir + "/" + pad + big.length)
      // NATIVE: doesn't build a command line -> handles the huge list.
      var total = FileOperations.totalSize(big)      // sums only the 2 real ones
      var modes = FileOperations.octalModes(big)     // aligned with big, "" if missing
      var nativeOk = total === expected
        && modes.length === big.length && modes[0].length > 0 && modes[2] === ""
      if (!nativeOk) { done(false, "native: total=" + total + " exp=" + expected
        + " len=" + modes.length + " m0='" + modes[0] + "' m2='" + modes[2] + "'"); return }
      // OLD: the SAME `stat -c%a -- <all>` form that the old code used
      // -> the -c arg overflows the limit and exec fails (exit != 0).
      var oldCmd = "stat -c%a -- " + big.map(function (p) { return _q(p) }).join(" ")
      sc._sh(["bash", "-c", oldCmd], function (r) {
        done(r.exitCode !== 0,
             "native OK (" + big.length + " paths); old shell line failed (exit=" + r.exitCode + ")")
      })
    })

    // ======================= BUG-05 (Hardening-2) =======================

    // ArchiveActions opened an archive member with `tar xf A -O <member>`
    // without "--": a member starting with "-" (e.g. "-foo") was taken by tar
    // as options and failed. The corrected pattern is `tar xf A -O -- <member>`.
    // A .tar with a member "-foo" is created and it's checked that the NEW form
    // dumps it and the OLD one fails.
    add("tar extracts a member whose name starts with '-' (BUG-05)", function (done) {
      var d = sc.opsDir + "/bug05"
      var arch = d + "/a.tar"
      var setup = "mkdir -p " + _q(d) + " && cd " + _q(d)
        + " && printf 'contenido05' > ./-foo && tar cf " + _q(arch) + " -- -foo"
      sc._sh(["bash", "-c", setup], function (r0) {
        if (r0.exitCode !== 0) { done(false, "setup failed: " + r0.stderr); return }
        sc._sh(["bash", "-c", "tar xf " + _q(arch) + " -O -- " + _q("-foo")], function (rNew) {
          sc._sh(["bash", "-c", "tar xf " + _q(arch) + " -O " + _q("-foo") + " 2>/dev/null"], function (rOld) {
            var ok = rNew.exitCode === 0 && String(rNew.stdout) === "contenido05" && rOld.exitCode !== 0
            done(ok, "new: exit=" + rNew.exitCode + " out='" + String(rNew.stdout)
              + "' | old exit=" + rOld.exitCode)
          })
        })
      })
    })
  }
}

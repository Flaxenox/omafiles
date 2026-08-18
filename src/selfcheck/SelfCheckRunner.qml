import QtQuick
import Omafiles.Backend as Backend
import "../../state"
import "../../shared/Utils.js" as Utils
import "."

// SelfCheck -- reproducible functional validation harness of Omafiles (Phase
// 12, josema). It's loaded from main.cpp when the standalone executable
// Starts with `--selfcheck`, headless (offscreen) functional verification test harness.
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
  readonly property string wav: dir + "/audio.wav"
  readonly property string note: dir + "/note.txt"

  // ---- runner state ----
  property var checks: []
  property int idx: -1
  property int passes: 0
  property int fails: 0
  property real _startedAt: 0
  property bool _settled: false

  // Root cause of the intermittent Trash-test batch failures (P2.7,
  // 2026-08-17): Backend.FileOperations is a singleton with no busy/mutex
  // guard of its own (verified: no such guard exists in FileOperations.h/
  // .cpp) and its finished/error signals carry no request id -- just
  // (op, path). _fileOp() below used to connect one-shot handlers to
  // those signals and rely entirely on "the runner is sequential, only
  // one operation is ever in flight" to stay correct. Under real disk-I/O
  // contention, an operation can still be genuinely in flight when this
  // test's own 8s _timeout fires and _done() moves on to the NEXT test --
  // but the old handler stayed connected. When that late operation (or
  // the next test's own, unrelated one) finally fired `finished`, BOTH
  // the stale handler and the current test's handler received it, and
  // the stale one blindly accepted it as its own (no path check),
  // corrupting whatever _seqOps sequence the next test was mid-way
  // through. This is exactly the failure shape seen three times this
  // session: a cluster of Trash tests, some timing out, some failing
  // fast with a plausible-but-wrong result, never reproducing on an
  // immediate rerun (a rerun has no backlog of delayed operations).
  // Fix: track the one _fileOp currently awaiting a signal; _done()
  // forcibly disconnects it if the test settles (pass, fail, OR timeout)
  // before its own handler ever got the chance to self-disconnect.
  property var _activeFileOpCleanup: null

  // DirectoryModel factory for the existence/listing checks
  // (non-singleton service wrapped over the C++ backend).
  property Component _dmFactory: Component { Backend.DirectoryModel {} }

  // SearchWorker factory (native backend, non-singleton) for the
  // recursive search test.
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

  // timeoutMs (optional): per-test override of the default 8000ms hang
  // watchdog above -- for a test that legitimately needs more room (e.g.
  // one waiting on a background-thread-pool listing that can be genuinely
  // slower under contention from other tests' real file ops run earlier in
  // the same process), not a general knob to reach for. Every other test
  // keeps the default.
  function add(name, fn, timeoutMs) { checks.push({ name: name, fn: fn, timeoutMs: timeoutMs || 0 }) }

  function _run() {
    idx++
    if (idx >= checks.length) { _report(); return }
    _settled = false
    _startedAt = Date.now()
    _timeout.interval = checks[idx].timeoutMs || 8000
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
    // See _activeFileOpCleanup's comment above the property. In the
    // normal (non-timeout) path this is already null -- the operation's
    // own ok()/bad() handler already ran cleanup() and cleared it before
    // calling into done()/then() -- so this is a no-op there. It only
    // does real work on the timeout path, where the operation never
    // completed in time and would otherwise stay silently connected.
    if (_activeFileOpCleanup) { _activeFileOpCleanup(); _activeFileOpCleanup = null }
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

  // Selects NavState.visibleEntries by name; false (no selection change) if
  // any requested name isn't currently listed. Was copy-pasted identically
  // 5 times across src/selfcheck/checks/CheckActions.qml (cleanup pass).
  function _selectByNames(names) {
    var entries = NavState.visibleEntries
    var idx = []
    for (var i = 0; i < entries.length; i++)
      if (names.indexOf(entries[i].name) >= 0) idx.push(i)
    if (idx.length !== names.length) return false
    SelectionState.selectedIndices = idx
    return true
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
  // finished signal, or done(false, ...) on error. Normally there is only
  // one operation in flight (the runner is sequential) -- but see
  // _activeFileOpCleanup's comment: if THIS operation is still genuinely
  // in flight when its governing test times out, _done() disconnects
  // `cleanup` on our behalf so a late finished/error can never misfire
  // into whatever test runs next.
  function _fileOp(done, then) {
    function ok(op, path) { cleanup(); then(op, path) }
    function bad(op, path, msg) { cleanup(); done(false, op + " error: " + msg) }
    function cleanup() {
      Backend.FileOperations.finished.disconnect(ok)
      Backend.FileOperations.error.disconnect(bad)
      if (sc._activeFileOpCleanup === cleanup) sc._activeFileOpCleanup = null
    }
    Backend.FileOperations.finished.connect(ok)
    Backend.FileOperations.error.connect(bad)
    sc._activeFileOpCleanup = cleanup
  }

  property Timer _pollTimer: Timer { interval: 16; repeat: true }

  // Polls cond() every 16 ms (wall-clock, not event loop passes) until it
  // is true or the budget runs out (default ~4 s / 250 ticks, comfortable
  // under the 8 s per-test timeout). To wait for an async effect that
  // doesn't expose a public signal to hook onto (e.g. the re-listing of a
  // background panel, whose DirLister is internal and delivers via
  // invokeMethod from a pool thread). The real interval gives clock time to
  // the worker, avoiding the race of a Qt.callLater loop that spins faster
  // than the thread can respond. The runner is sequential: there is only
  // one _poll in flight.
  // maxTicks (optional): overrides the default 250 -- pairs with add()'s
  // own timeoutMs override for a test that needs more room end to end; the
  // default is unchanged for every other caller.
  function _poll(cond, cb, maxTicks) {
    if (cond()) { cb(true); return }
    var n = 0
    var limit = maxTicks || 250
    function tick() {
      if (cond()) { done(); cb(true) }
      else if (++n > limit) { done(); cb(false) }
    }
    function done() { _pollTimer.stop(); _pollTimer.triggered.disconnect(tick) }
    _pollTimer.triggered.connect(tick)
    _pollTimer.restart()
  }

  // ---- BUG-02: process runner for the .sh script smoke tests ----
  // Backend.ProcessRunner (real QProcess) delivers {exitCode,stdout,stderr}.
  property Component _procFactory: Component { Backend.ProcessRunner {} }
  // Resource root (where the .sh live), derived from this file's URL:
  readonly property string resourceRoot: Qt.resolvedUrl("../../").toString().replace(/^file:\/\//, "").replace(/\/+$/, "")

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


  property SelfCheckRegistry selfCheckRegistry: SelfCheckRegistry {}


  Component.onCompleted: {
    selfCheckRegistry.registerAll(sc)
    SelfCheckOut.line("── omafiles --selfcheck · fixtures in " + dir + " ──")
    _run()
  }
}

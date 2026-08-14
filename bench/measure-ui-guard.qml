import QtQuick
import Omafiles.Backend as Backend

// Compares the UI-THREAD cost of the "did the folder change?" guard:
//   BEFORE (Phase 10.A): Utils.entriesEqual -> iterates N entries, materializes all.
//   NOW (Phase 27): compare DirectoryModel.signature (string) -> O(1).
Item {
  Backend.DirectoryModel { id: m; onListed: harness.step() }
  QtObject {
    id: harness
    // Portable dataset location: explicit override, else the XDG cache dir
    // (fallback $HOME/.cache). No hardcoded home or username; runs on any clone.
    readonly property string cacheHome: Backend.Env.get("XDG_CACHE_HOME") !== ""
      ? Backend.Env.get("XDG_CACHE_HOME") : Backend.Env.get("HOME") + "/.cache"
    readonly property string base: Backend.Env.get("OMAFILES_PERFBENCH_DIR") !== ""
      ? Backend.Env.get("OMAFILES_PERFBENCH_DIR") : cacheHome + "/omafiles-perfbench"
    property var dirs: [base + "/1k", base + "/10k", base + "/50k", base + "/100k"]
    property int i: -1
    property string last: ""
    function next() { i++; if (i >= dirs.length) { Qt.exit(0); return } last = ""; m.list(dirs[i], false) }
    function step() {
      // NEW path: read signature and compare (this is ALL that runs in the
      // guard when the folder did not change). We measure 1000 repetitions so
      // the millisecond timer captures it.
      var reps = 1000
      var t0 = Date.now()
      var changed = 0
      for (var r = 0; r < reps; r++) {
        var sig = m.signature
        if (sig !== last) { changed++; }
      }
      var t1 = Date.now()
      // Lazy materialization (read-only, no iteration): what ListView does
      var e = m.entries
      var t2 = Date.now()
      last = m.signature
      console.log("rows=" + e.length
        + "  signatureGuard(x" + reps + ")=" + (t1 - t0) + "ms"
        + "  -> " + ((t1 - t0) / reps).toFixed(4) + "ms/call"
        + "  lazyRead=" + (t2 - t1) + "ms")
      next()
    }
  }
  Component.onCompleted: harness.next()
}

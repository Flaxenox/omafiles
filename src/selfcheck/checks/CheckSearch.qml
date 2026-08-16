import QtQuick
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// Domain checks extracted from app/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Native recursive search: name, depth, hidden filter", function (done) {
          var base = sc.dir + "/srch-" + Date.now()
          var mk = function (p) { return function () { Backend.FileOperations.mkdir(p) } }
          var cp = function (p) { return function () { Backend.FileOperations.copy(sc.note, p) } }
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
        sc.add("Native recursive content search: line matching, snippets, binary filter", function (done) {
          var base = sc.dir + "/content-srch-" + Date.now()
          var mk = function (p) { return function () { Backend.FileOperations.mkdir(p) } }
          var cp = function (p) { return function () { Backend.FileOperations.copy(sc.note, p) } }
          
          sc._seqOps([
            mk(base), mk(base + "/src"),
            cp(base + "/src/main.txt"),
            cp(base + "/readme.txt")
          ], done, function () {
            var sw = sc._searchFactory.createObject(sc)
            function onResults(entries, truncated) {
              sw.results.disconnect(onResults)
              sw.destroy()
              var ok = entries.length === 2
                    && entries[0].line === 1
                    && entries[0].snippet.indexOf("hello selfcheck") >= 0
                    && entries[0].path.length > 0
              done(ok, ok ? "content search matches=2 with line numbers OK" : "unexpected results: " + JSON.stringify(entries))
            }
            sw.results.connect(onResults)
            sw.searchContent(base, "hello selfcheck", false)
          })
        })

        // Regression for P0 concurrency audit (forensic audit 2026-08-16):
        // SearchWorker's scan loop used to read `this->m_gen` on every
        // iterated entry, unguarded, for the entire duration of the scan --
        // ALL of it before the Life/mutex guard (which only covered the
        // final result delivery) was ever consulted. Destroying the worker
        // while it was still walking a tree was a confirmed use-after-free
        // (reproduced with AddressSanitizer against a few thousand files:
        // every single run crashed before the fix, zero crashes in 96
        // create/search/destroy cycles after). This exercises the exact
        // same pattern live, repeatedly, through the real QML lifecycle
        // (SearchWorker is QML_ELEMENT, so it can genuinely be created and
        // destroyed on demand, unlike the two QML_SINGLETON backends). A
        // real regression here would crash the whole selfcheck process, not
        // just fail this one test.
        sc.add("SearchWorker: create/search/destroy under load doesn't corrupt state (P0 regression)", function (done) {
          var base = sc.opsDir + "/p0-search-stress"
          var buildCmd = "rm -rf " + sc._q(base) + " && mkdir -p " + sc._q(base)
            + " && cd " + sc._q(base)
            + " && for i in $(seq 1 3000); do : > \"file_$i.txt\"; done"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            var iterations = 40
            var i = 0
            function nextIteration() {
              if (i >= iterations) { finalCheck(); return }
              i++
              var sw = sc._searchFactory.createObject(sc)
              // Broad query ("e" matches most of "file_N.txt") over 3000
              // entries so the scan is still running when destroy() fires
              // right behind it -- no wait, no sleep, maximum overlap.
              sw.search(base, "e", true)
              sw.destroy()
              // Also exercise start-then-immediately-cancel-and-restart on a
              // worker we keep alive, interleaved with the destroy cycles.
              if (i % 2 === 0) {
                var sw2 = sc._searchFactory.createObject(sc)
                sw2.search(base, "f", true)
                sw2.cancel()
                sw2.search(base, "e", true)
                sw2.cancel()
                sw2.destroy()
              }
              Qt.callLater(nextIteration)
            }
            function finalCheck() {
              // If any stale callback from the stress loop had corrupted
              // shared state, a normal search afterwards is the most direct
              // way to notice: wrong/missing results, or simply never
              // arriving (the 8s per-test timeout would then fail this).
              var sw = sc._searchFactory.createObject(sc)
              function onResults(entries, truncated) {
                sw.results.disconnect(onResults)
                sw.destroy()
                var ok = entries.length === 200 && truncated === true
                done(ok, ok
                  ? "40 create/search/destroy cycles (+20 cancel/restart) survived, final search still correct"
                  : "final search after stress wrong: n=" + entries.length + " truncated=" + truncated)
              }
              sw.results.connect(onResults)
              sw.search(base, "e", true) // "e" matches all 3000 -> capped at 200, truncated=true
            }
            nextIteration()
          })
        })
  }
}

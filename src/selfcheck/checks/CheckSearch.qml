import QtQuick
import Omafiles.Backend as Backend
import "../../../services"
import "../../../state"
import "../../../Utils.js" as Utils

// Domain checks extracted from app/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Native recursive search: name, depth, hidden filter (Fase 16)", function (done) {
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
  }
}

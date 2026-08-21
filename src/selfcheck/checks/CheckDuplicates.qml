import QtQuick
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// Duplicate-file finder domain checks (v1.2, git status + duplicate finder).
// Backend.DuplicateFinder is QML_ELEMENT (one scan per caller), same
// structural shape as SearchWorker -- see CheckSearch.qml's P0 regression
// test, whose cancel-then-reuse pattern the cancellation test here copies.
QtObject {
  function register(sc) {
        sc.add("DuplicateFinder: size+hash grouping excludes symlink/empty/hidden, oldest path first (includeHidden=false)", function (done) {
          var base = sc.opsDir + "/dupfind-" + Date.now()
          var build = "rm -rf " + sc._q(base) + " && mkdir -p " + sc._q(base + "/sub")
            + " && printf 'dup content for selfcheck\\n' > " + sc._q(base + "/a.txt")
            + " && cp " + sc._q(base + "/a.txt") + " " + sc._q(base + "/sub/a-copy.txt")
            + " && touch -d '2020-01-01' " + sc._q(base + "/a.txt")
            + " && touch -d '2021-01-01' " + sc._q(base + "/sub/a-copy.txt")
            + " && head -c 100000 /dev/zero | tr '\\0' 'x' > " + sc._q(base + "/big.bin")
            + " && cp " + sc._q(base + "/big.bin") + " " + sc._q(base + "/sub/big-copy.bin")
            + " && printf 'unique content\\n' > " + sc._q(base + "/unique.txt")
            + " && : > " + sc._q(base + "/empty.txt")
            + " && ln -s " + sc._q(base + "/a.txt") + " " + sc._q(base + "/link.txt")
            + " && printf 'hidden dup\\n' > " + sc._q(base + "/.hid.txt")
            + " && cp " + sc._q(base + "/.hid.txt") + " " + sc._q(base + "/sub/.hid-copy.txt")
          sc._sh(["bash", "-c", build], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            var df = sc._dupFinderFactory.createObject(sc)
            function onFinished(groups) {
              df.finished.disconnect(onFinished)
              df.destroy()
              if (groups.length !== 2) { done(false, "expected 2 groups (symlink/empty/hidden/unique excluded), got " + groups.length + ": " + JSON.stringify(groups)); return }
              var big = groups.filter(function (g) { return g.size === 100000 })[0]
              var small = groups.filter(function (g) { return g.size !== 100000 })[0]
              if (!big || !small) { done(false, "unexpected group sizes: " + JSON.stringify(groups.map(function (g) { return g.size }))); return }
              var okBig = big.paths.length === 2
              // touch -d gave a.txt an OLDER mtime than sub/a-copy.txt -- the
              // group must list it first (see DuplicateFinder.cpp's
              // std::sort by lastModified, ascending).
              var okOrder = small.paths.length === 2
                && small.paths[0].indexOf("/sub/") < 0 && small.paths[0].indexOf("a.txt") >= 0
                && small.paths[1].indexOf("/sub/a-copy.txt") >= 0
              done(okBig && okOrder, (okBig && okOrder) ? "2 groups correct, oldest-first order OK" : "group contents wrong: " + JSON.stringify(groups))
            }
            df.finished.connect(onFinished)
            df.scan(base, false)
          })
        })

        sc.add("DuplicateFinder: includeHidden=true picks up dotfile duplicates", function (done) {
          var base = sc.opsDir + "/duphidden-" + Date.now()
          var build = "mkdir -p " + sc._q(base) + " && printf 'hidden dup\\n' > " + sc._q(base + "/.hid.txt")
            + " && cp " + sc._q(base + "/.hid.txt") + " " + sc._q(base + "/.hid-copy.txt")
          sc._sh(["bash", "-c", build], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            var df = sc._dupFinderFactory.createObject(sc)
            function onFinishedWithout(groups) {
              df.finished.disconnect(onFinishedWithout)
              df.destroy()
              var without = groups.length === 0
              var df2 = sc._dupFinderFactory.createObject(sc)
              function onFinishedWith(groups2) {
                df2.finished.disconnect(onFinishedWith)
                df2.destroy()
                var withHidden = groups2.length === 1 && groups2[0].paths.length === 2
                done(without && withHidden, (without && withHidden)
                  ? "hidden dup excluded by default, included with includeHidden=true"
                  : "without=" + JSON.stringify(groups) + " with=" + JSON.stringify(groups2))
              }
              df2.finished.connect(onFinishedWith)
              df2.scan(base, true)
            }
            df.finished.connect(onFinishedWithout)
            df.scan(base, false)
          })
        })

        // Same generation-counter cancellation shape as SearchWorker (see
        // CheckSearch.qml's P0 regression comment) -- cancel() is called
        // synchronously right after scan(), before the QThreadPool worker
        // has a real chance to run, so a correct implementation must never
        // deliver `finished` for the cancelled call. The instance is then
        // reused for a real scan to confirm cancelling didn't corrupt it.
        sc.add("DuplicateFinder: cancel() suppresses delivery, instance still usable afterwards", function (done) {
          var base = sc.opsDir + "/dupcancel-" + Date.now()
          var build = "mkdir -p " + sc._q(base) + " && cd " + sc._q(base)
            + " && for i in $(seq 1 300); do printf 'same content\\n' > \"f_$i.txt\"; done"
          sc._sh(["bash", "-c", build], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            var df = sc._dupFinderFactory.createObject(sc)
            var finishedFired = false
            function onFinished() { finishedFired = true }
            df.finished.connect(onFinished)
            df.scan(base, false)
            df.cancel()
            // ~160ms grace window (reusing _poll purely as a delay, same
            // trick as elsewhere in this harness) for a wrongly-delivered
            // signal to show up before declaring the cancellation clean.
            sc._poll(function () { return false }, function () {
              df.finished.disconnect(onFinished)
              if (finishedFired) { df.destroy(); done(false, "cancelled scan still delivered finished"); return }
              function onFinished2(groups2) {
                df.finished.disconnect(onFinished2)
                df.destroy()
                var ok = groups2.length === 1 && groups2[0].paths.length === 300
                done(ok, ok ? "cancel suppressed delivery, instance still usable afterwards" : "post-cancel scan wrong: " + JSON.stringify(groups2.map(function (g) { return g.paths.length })))
              }
              df.finished.connect(onFinished2)
              df.scan(base, false)
            }, 10)
          })
        })

        sc.add("DuplicatesState: reset/toggle/selectAllButFirstPerGroup/selectedCount", function (done) {
          DuplicatesState.reset("/some/path")
          var okReset = DuplicatesState.rootPath === "/some/path" && DuplicatesState.scanning === true
            && DuplicatesState.filesScanned === 0 && DuplicatesState.groups.length === 0
            && DuplicatesState.selectedCount === 0
          DuplicatesState.groups = [
            { size: 10, paths: ["/a", "/b", "/c"] },
            { size: 20, paths: ["/d", "/e"] }
          ]
          DuplicatesState.toggle("/a")
          var okToggleOn = DuplicatesState.selected["/a"] === true && DuplicatesState.selectedCount === 1
          DuplicatesState.toggle("/a")
          var okToggleOff = !DuplicatesState.selected["/a"] && DuplicatesState.selectedCount === 0
          DuplicatesState.selectAllButFirstPerGroup()
          var sel = DuplicatesState.selected
          var okSelectAllButFirst = DuplicatesState.selectedCount === 3
            && !sel["/a"] && sel["/b"] && sel["/c"] && !sel["/d"] && sel["/e"]
          DuplicatesState.clearSelection()
          var okClear = DuplicatesState.selectedCount === 0
          var ok = okReset && okToggleOn && okToggleOff && okSelectAllButFirst && okClear
          done(ok, ok ? "state helpers correct" : "reset=" + okReset + " toggleOn=" + okToggleOn
            + " toggleOff=" + okToggleOff + " selectAllButFirst=" + okSelectAllButFirst + " clear=" + okClear)
        })

        sc.add("ActionEngine: startDuplicateFinder scans + commitDuplicateTrash sends selected to real trash (undo restores)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var base = sc.opsDir + "/dupaction-" + Date.now()
          var build = "mkdir -p " + sc._q(base) + " && printf 'dup content\\n' > " + sc._q(base + "/keep.txt")
            + " && cp " + sc._q(base + "/keep.txt") + " " + sc._q(base + "/trash-me.txt")
            + " && touch -d '2020-01-01' " + sc._q(base + "/keep.txt")
            + " && touch -d '2021-01-01' " + sc._q(base + "/trash-me.txt")
          sc._sh(["bash", "-c", build], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            c.actionEngine.startDuplicateFinder(base)
            // No public signal to hook for "scan finished" from here --
            // ActionEngine owns the DuplicateFinder instance privately --
            // so poll DuplicatesState.scanning like _poll's own doc comment
            // recommends for exactly this situation.
            sc._poll(function () { return !DuplicatesState.scanning }, function (settled) {
              if (!settled) { done(false, "scan never finished"); return }
              if (DuplicatesState.groups.length !== 1 || DuplicatesState.groups[0].paths.length !== 2) {
                done(false, "unexpected groups: " + JSON.stringify(DuplicatesState.groups)); return
              }
              DuplicatesState.selectAllButFirstPerGroup() // keeps keep.txt (oldest), selects trash-me.txt
              var selectedPaths = Object.keys(DuplicatesState.selected)
              if (selectedPaths.length !== 1 || selectedPaths[0].indexOf("trash-me.txt") < 0) {
                done(false, "selection picked the wrong file: " + JSON.stringify(selectedPaths)); return
              }
              sc._fileOp(done, function () {
                sc._listOnce(base, function (e) {
                  var trashed = sc._has(e, "keep.txt") && !sc._has(e, "trash-me.txt")
                  if (!trashed) { done(false, "trash-me.txt still present after commitDuplicateTrash"); return }
                  c.undoLast()
                  sc._fileOp(done, function () {
                    sc._listOnce(base, function (e2) {
                      var restored = sc._has(e2, "trash-me.txt")
                      done(restored, restored ? "duplicate trashed + undo restored it" : "undo did not restore trash-me.txt")
                    })
                  })
                })
              })
              c.actionEngine.commitDuplicateTrash()
            })
          })
        })
  }
}

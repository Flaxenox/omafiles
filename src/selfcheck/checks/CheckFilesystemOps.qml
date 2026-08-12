import QtQuick
import Omafiles.Backend as Backend
import "../../../services"
import "../../../state"
import "../../../Utils.js" as Utils

// Filesystem basic operations domain checks (Phase 30).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("FileOperations mkdir", function (done) {
          sc._fileOp(done, function (op, path) {
            sc._listOnce(sc.opsDir, function (e) {
              var ok = sc._has(e, "newdir")
              done(ok, ok ? "" : "newdir doesn't appear")
            })
          })
          FileOperations.mkdir(sc.opsDir + "/newdir")
        })

        sc.add("FileOperations rename", function (done) {
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

        sc.add("FileOperations copy", function (done) {
          sc._fileOp(done, function () {
            sc._listOnce(sc.opsDir, function (e) {
              var ok = sc._has(e, "copy.txt")
              done(ok, ok ? "" : "copy.txt doesn't appear")
            })
          })
          FileOperations.copy(sc.note, sc.opsDir + "/copy.txt")
        })

        sc.add("FileOperations copy overwrite (replace)", function (done) {
          var dst = sc.opsDir + "/ow.txt"
          sc._fileOp(done, function () {
            sc._fileOp(done, function () { done(true, "destination replaced") })
            FileOperations.copy(sc.note, dst, true)
          })
          FileOperations.copy(sc.note, dst)
        })

        sc.add("FileOperations copy directory (recursive)", function (done) {
          sc._fileOp(done, function () {
            sc._listOnce(sc.opsDir + "/listcopy", function (e) {
              var ok = e.length === 4 && sc._has(e, "sub") && sc._has(e, "alpha.txt")
              done(ok, ok ? e.length + " entries copied" : "incomplete tree")
            })
          })
          FileOperations.copy(sc.listDir, sc.opsDir + "/listcopy")
        })

        sc.add("FileOperations copy symlink preserved", function (done) {
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

        sc.add("FileOperations copy preserves permissions", function (done) {
          var srcPerm = PreviewProvider.info(sc.note).permissions
          sc._fileOp(done, function () {
            var dstPerm = PreviewProvider.info(sc.opsDir + "/permcopy").permissions
            var ok = srcPerm && dstPerm && srcPerm === dstPerm
            done(ok, "src=" + srcPerm + " dst=" + dstPerm)
          })
          FileOperations.copy(sc.note, sc.opsDir + "/permcopy")
        })

        sc.add("ActionEngine native copy runner (paste/drop path)", function (done) {
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

        sc.add("FileOperations move overwrite (replace)", function (done) {
          var work = sc.opsDir + "/mvow-src.txt"
          var dst = sc.opsDir + "/mvow-dst.txt"
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              sc._fileOp(done, function () {
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

        sc.add("FileOperations move directory (recursive)", function (done) {
          var srcDir = sc.opsDir + "/mvdir-src"
          var dstDir = sc.opsDir + "/mvdir-dst"
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
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

        sc.add("FileOperations move symlink preserved", function (done) {
          var work = sc.opsDir + "/mvlink-src"
          var dst = sc.opsDir + "/mvlink-dst"
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
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

        sc.add("FileOperations move cross-filesystem (best-effort /tmp)", function (done) {
          var work = sc.opsDir + "/xfs-src.txt"
          var xfsDst = "/tmp/omafiles-selfcheck-xfs-" + Date.now() + ".txt"
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              var destInfo = PreviewProvider.info(xfsDst)
              var destOk = destInfo && Object.keys(destInfo).length > 0
              sc._listOnce(sc.opsDir, function (e) {
                var srcGone = !sc._has(e, "xfs-src.txt")
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

        sc.add("Copy/move cancellation (cooperative, source safe)", function (done) {
          var dst = sc.opsDir + "/big-copy.bin"
          var srcPath = sc.dir + "/big.bin"
          function onErr(op, path, msg) {
            if (path !== srcPath) return
            cleanup()
            if (msg !== "cancelled") { done(false, "unexpected error: " + msg); return }
            var srcOk = PreviewProvider.info(srcPath)
            done(srcOk && Object.keys(srcOk).length > 0, "cancelled, source intact")
          }
          function onFin(op, path) {
            if (path !== srcPath) return
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

        sc.add("ActionEngine native move runner + undo (paste/drop path)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var work = sc.opsDir + "/mv-runner-src.txt"
          var dst = sc.opsDir + "/mv-runner-dst.txt"
          sc._fileOp(done, function () {
            var pairs = [{ src: work, dest: dst }]
            var started = c.actionEngine.runNativeMove(pairs, "Moving…", false, function () {
              var reversed = [{ src: dst, dest: work }]
              c.actionEngine.pushUndo("move test",
                function () { return c.actionEngine.runNativeMove(reversed, "", false) },
                function () { return c.actionEngine.runNativeMove(pairs, "", false) })
              sc._listOnce(sc.opsDir, function (e) {
                if (!(sc._has(e, "mv-runner-dst.txt") && !sc._has(e, "mv-runner-src.txt"))) {
                  done(false, "didn't move"); return
                }
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

        sc.add("FileOperations delete directory (recursive)", function (done) {
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e) {
                var ok = !sc._has(e, "deldir")
                done(ok, ok ? "tree deleted" : "still exists")
              })
            })
            FileOperations.remove(sc.opsDir + "/deldir")
          })
          FileOperations.copy(sc.listDir, sc.opsDir + "/deldir")
        })

        sc.add("FileOperations delete symlink (target preserved)", function (done) {
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e) {
                var linkGone = !sc._has(e, "dellink")
                var target = PreviewProvider.info(sc.note)
                done(linkGone && Object.keys(target).length > 0,
                     linkGone ? "link deleted, target intact" : "the link stays")
              })
            })
            FileOperations.remove(sc.opsDir + "/dellink")
          })
          FileOperations.copy(sc.dir + "/link.txt", sc.opsDir + "/dellink")
        })

        sc.add("FileOperations delete read-only (permission failure)", function (done) {
          var target = sc.dir + "/readonly/locked.txt"
          function onErr(op, path, msg) { if (path !== target) return; cleanup(); done(true, "error reported: " + msg) }
          function onFin(op, path) { if (path !== target) return; cleanup(); done(false, "should not be able to delete in a read-only folder") }
          function cleanup() { FileOperations.error.disconnect(onErr); FileOperations.finished.disconnect(onFin) }
          FileOperations.error.connect(onErr)
          FileOperations.finished.connect(onFin)
          FileOperations.remove(target, false)
        })

        sc.add("FileOperations delete missing (error vs ignoreMissing)", function (done) {
          var gone = sc.opsDir + "/never-existed-" + Date.now()
          var gone2 = sc.opsDir + "/never2-" + Date.now()
          function onErr(op, path, msg) {
            if (path !== gone) return
            cleanup1()
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

        sc.add("FileOperations delete cancellation (recursive tree)", function (done) {
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

        sc.add("ActionEngine native remove runner (delete path)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var a = sc.opsDir + "/del-a.txt"
          var b = sc.opsDir + "/del-b.txt"
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
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
  }
}

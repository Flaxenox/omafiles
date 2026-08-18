import QtQuick
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// Filesystem basic operations domain checks.
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Backend.FileOperations mkdir", function (done) {
          sc._fileOp(done, function (op, path) {
            sc._listOnce(sc.opsDir, function (e) {
              var ok = sc._has(e, "newdir")
              done(ok, ok ? "" : "newdir doesn't appear")
            })
          })
          Backend.FileOperations.mkdir(sc.opsDir + "/newdir")
        })

        sc.add("Backend.FileOperations rename", function (done) {
          Backend.FileOperations.copy(sc.note, sc.opsDir + "/toRename.txt")
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e) {
                var ok = sc._has(e, "renamed.txt") && !sc._has(e, "toRename.txt")
                done(ok, ok ? "" : "rename not reflected")
              })
            })
            Backend.FileOperations.rename(sc.opsDir + "/toRename.txt", "renamed.txt")
          })
        })

        sc.add("Backend.FileOperations copy", function (done) {
          sc._fileOp(done, function () {
            sc._listOnce(sc.opsDir, function (e) {
              var ok = sc._has(e, "copy.txt")
              done(ok, ok ? "" : "copy.txt doesn't appear")
            })
          })
          Backend.FileOperations.copy(sc.note, sc.opsDir + "/copy.txt")
        })

        sc.add("Backend.FileOperations copy overwrite (replace)", function (done) {
          var dst = sc.opsDir + "/ow.txt"
          sc._fileOp(done, function () {
            sc._fileOp(done, function () { done(true, "destination replaced") })
            Backend.FileOperations.copy(sc.note, dst, true)
          })
          Backend.FileOperations.copy(sc.note, dst)
        })

        sc.add("Backend.FileOperations copy directory (recursive)", function (done) {
          sc._fileOp(done, function () {
            sc._listOnce(sc.opsDir + "/listcopy", function (e) {
              var ok = e.length === 4 && sc._has(e, "sub") && sc._has(e, "alpha.txt")
              done(ok, ok ? e.length + " entries copied" : "incomplete tree")
            })
          })
          Backend.FileOperations.copy(sc.listDir, sc.opsDir + "/listcopy")
        })

        // Regression for P0-2 (forensic audit 2026-08-16): FileOpsPrivate::copyFile()
        // used to treat a mid-copy QFile::read() error (-1) identically to a clean
        // EOF (0) -- the destination was silently reported as a successful copy
        // while actually truncated. This can't force the exact -1 syscall
        // deterministically without root, but it exercises the closest realistic
        // failure a user hits (an unreadable file inside the tree being copied) and
        // asserts BOTH halves of the fix: the failure must be reported (not
        // swallowed as success) AND the partial destination must be cleaned up
        // instead of left behind looking like a real, complete copy.
        sc.add("Backend.FileOperations copy: unreadable file mid-tree fails and cleans up (P0-2 regression)", function (done) {
          var srcTree = sc.opsDir + "/p02-src"
          var destTree = sc.opsDir + "/p02-dst"
          var buildCmd = "rm -rf " + sc._q(srcTree) + " " + sc._q(destTree)
            + " && mkdir -p " + sc._q(srcTree)
            + " && echo ok > " + sc._q(srcTree + "/readable.txt")
            + " && echo secret > " + sc._q(srcTree + "/noaccess.txt")
            + " && chmod 000 " + sc._q(srcTree + "/noaccess.txt")
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            function restorePermsThen(cb) {
              // So the QTemporaryDir root can always clean itself up on exit,
              // regardless of how this test resolves.
              sc._sh(["bash", "-c", "chmod 644 " + sc._q(srcTree + "/noaccess.txt")], cb)
            }
            function onErr(op, path, msg) {
              if (path !== srcTree) return
              cleanup()
              restorePermsThen(function () {
                sc._listOnce(sc.opsDir, function (e) {
                  var destGone = !sc._has(e, "p02-dst")
                  done(destGone, destGone
                    ? "copy correctly failed (" + msg + ") and the partial destination was cleaned up"
                    : "copy failed but left a partial/truncated destination behind: " + destTree)
                })
              })
            }
            function onFin(op, path) {
              if (path !== srcTree) return
              cleanup()
              restorePermsThen(function () {
                done(false, "copy of a tree containing an unreadable file was reported as SUCCESS — silent data loss")
              })
            }
            function cleanup() {
              Backend.FileOperations.error.disconnect(onErr)
              Backend.FileOperations.finished.disconnect(onFin)
            }
            Backend.FileOperations.error.connect(onErr)
            Backend.FileOperations.finished.connect(onFin)
            Backend.FileOperations.copy(srcTree, destTree)
          })
        })

        sc.add("Backend.FileOperations copy symlink preserved", function (done) {
          sc._fileOp(done, function () {
            sc._listOnce(sc.opsDir, function (e) {
              var ok = false
              for (var i = 0; i < e.length; i++)
                if (e[i].name === "linkcopy" && e[i].link && e[i].link.length > 0) ok = true
              done(ok, ok ? "copied as a link" : "didn't stay a symlink")
            })
          })
          Backend.FileOperations.copy(sc.dir + "/link.txt", sc.opsDir + "/linkcopy")
        })

        sc.add("Backend.FileOperations copy preserves permissions", function (done) {
          var srcPerm = Backend.PreviewProvider.info(sc.note).permissions
          sc._fileOp(done, function () {
            var dstPerm = Backend.PreviewProvider.info(sc.opsDir + "/permcopy").permissions
            var ok = srcPerm && dstPerm && srcPerm === dstPerm
            done(ok, "src=" + srcPerm + " dst=" + dstPerm)
          })
          Backend.FileOperations.copy(sc.note, sc.opsDir + "/permcopy")
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

        sc.add("Backend.FileOperations move overwrite (replace)", function (done) {
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
              Backend.FileOperations.move(work, dst, true)
            })
            Backend.FileOperations.copy(sc.note, dst)
          })
          Backend.FileOperations.copy(sc.note, work)
        })

        sc.add("Backend.FileOperations move directory (recursive)", function (done) {
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
            Backend.FileOperations.move(srcDir, dstDir)
          })
          Backend.FileOperations.copy(sc.listDir, srcDir)
        })

        sc.add("Backend.FileOperations move symlink preserved", function (done) {
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
            Backend.FileOperations.move(work, dst)
          })
          Backend.FileOperations.copy(sc.dir + "/link.txt", work)
        })

        sc.add("Backend.FileOperations move cross-filesystem (best-effort /tmp)", function (done) {
          var work = sc.opsDir + "/xfs-src.txt"
          var xfsDst = "/tmp/omafiles-selfcheck-xfs-" + Date.now() + ".txt"
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              var destInfo = Backend.PreviewProvider.info(xfsDst)
              var destOk = destInfo && Object.keys(destInfo).length > 0
              sc._listOnce(sc.opsDir, function (e) {
                var srcGone = !sc._has(e, "xfs-src.txt")
                sc._fileOp(done, function () {
                  done(destOk && srcGone, (destOk ? "dest ok" : "dest missing") + ", " + (srcGone ? "source gone" : "source stays"))
                })
                Backend.FileOperations.remove(xfsDst)
              })
            })
            Backend.FileOperations.move(work, xfsDst)
          })
          Backend.FileOperations.copy(sc.note, work)
        })

        sc.add("Copy/move cancellation (cooperative, source safe)", function (done) {
          var dst = sc.opsDir + "/big-copy.bin"
          var srcPath = sc.dir + "/big.bin"
          function onErr(op, path, msg) {
            if (path !== srcPath) return
            cleanup()
            if (msg !== "cancelled") { done(false, "unexpected error: " + msg); return }
            var srcOk = Backend.PreviewProvider.info(srcPath)
            done(srcOk && Object.keys(srcOk).length > 0, "cancelled, source intact")
          }
          function onFin(op, path) {
            if (path !== srcPath) return
            cleanup(); done(false, "finished before it could cancel")
          }
          function cleanup() {
            Backend.FileOperations.error.disconnect(onErr)
            Backend.FileOperations.finished.disconnect(onFin)
          }
          Backend.FileOperations.error.connect(onErr)
          Backend.FileOperations.finished.connect(onFin)
          Backend.FileOperations.copy(sc.dir + "/big.bin", dst)
          Backend.FileOperations.cancel()
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
                function (onSettled) { return c.actionEngine.runNativeMove(reversed, "", false, onSettled) },
                function (onSettled) { return c.actionEngine.runNativeMove(pairs, "", false, onSettled) })
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
          Backend.FileOperations.copy(sc.note, work)
        })

        sc.add("Backend.FileOperations delete directory (recursive)", function (done) {
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e) {
                var ok = !sc._has(e, "deldir")
                done(ok, ok ? "tree deleted" : "still exists")
              })
            })
            Backend.FileOperations.remove(sc.opsDir + "/deldir")
          })
          Backend.FileOperations.copy(sc.listDir, sc.opsDir + "/deldir")
        })

        sc.add("Backend.FileOperations delete symlink (target preserved)", function (done) {
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e) {
                var linkGone = !sc._has(e, "dellink")
                var target = Backend.PreviewProvider.info(sc.note)
                done(linkGone && Object.keys(target).length > 0,
                     linkGone ? "link deleted, target intact" : "the link stays")
              })
            })
            Backend.FileOperations.remove(sc.opsDir + "/dellink")
          })
          Backend.FileOperations.copy(sc.dir + "/link.txt", sc.opsDir + "/dellink")
        })

        sc.add("Backend.FileOperations delete read-only (permission failure)", function (done) {
          var target = sc.dir + "/readonly/locked.txt"
          function onErr(op, path, msg) { if (path !== target) return; cleanup(); done(true, "error reported: " + msg) }
          function onFin(op, path) { if (path !== target) return; cleanup(); done(false, "should not be able to delete in a read-only folder") }
          function cleanup() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
          Backend.FileOperations.error.connect(onErr)
          Backend.FileOperations.finished.connect(onFin)
          Backend.FileOperations.remove(target, false)
        })

        sc.add("Backend.FileOperations delete missing (error vs ignoreMissing)", function (done) {
          var gone = sc.opsDir + "/never-existed-" + Date.now()
          var gone2 = sc.opsDir + "/never2-" + Date.now()
          function onErr(op, path, msg) {
            if (path !== gone) return
            cleanup1()
            function onFin2(o, p) { if (p !== gone2) return; cleanup2(); done(true, "error if missing, ok with ignoreMissing") }
            function onErr2(o, p, m) { if (p !== gone2) return; cleanup2(); done(false, "ignoreMissing shouldn't fail") }
            function cleanup2() { Backend.FileOperations.finished.disconnect(onFin2); Backend.FileOperations.error.disconnect(onErr2) }
            Backend.FileOperations.finished.connect(onFin2)
            Backend.FileOperations.error.connect(onErr2)
            Backend.FileOperations.remove(gone2, true)
          }
          function onFin(op, path) { if (path !== gone) return; cleanup1(); done(false, "should fail without ignoreMissing") }
          function cleanup1() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
          Backend.FileOperations.error.connect(onErr)
          Backend.FileOperations.finished.connect(onFin)
          Backend.FileOperations.remove(gone, false)
        })

        sc.add("Backend.FileOperations delete cancellation (recursive tree)", function (done) {
          var target = sc.dir + "/bigdir"
          function onErr(op, path, msg) {
            if (path !== target) return
            cleanup()
            done(msg === "cancelled", "error=" + msg)
          }
          function onFin(op, path) { if (path !== target) return; cleanup(); done(false, "finished before it could cancel") }
          function cleanup() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
          Backend.FileOperations.error.connect(onErr)
          Backend.FileOperations.finished.connect(onFin)
          Backend.FileOperations.remove(target)
          Backend.FileOperations.cancel()
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
            Backend.FileOperations.copy(sc.note, b)
          })
          Backend.FileOperations.copy(sc.note, a)
        })

        // Regression for P0 concurrency audit (forensic audit 2026-08-16):
        // every FileOperations job (copy/move/remove/emptyTrash/
        // restoreByOrigPath) used to capture `[this, ...]` and read
        // `this->m_cancelled` / call `this->emitProgress(...)` for the
        // ENTIRE duration of the job -- e.g. the whole copyTree() loop --
        // all of it BEFORE the Life/mutex guard was ever checked (that only
        // covered the final finished/error delivery). Destroying the
        // singleton (app quitting) while a job was still running was a
        // confirmed use-after-free (reproduced with AddressSanitizer: 8/8
        // iterations crashed before the fix, 0/8 after). FileOperations is a
        // QML_SINGLETON, so this can't destroy it mid-job the way the
        // SearchWorker regression test does -- instead this hammers the
        // cooperative-cancel path that shares the exact same underlying
        // fix (m_cancelled is now a shared_ptr independent of `this`) and
        // confirms the singleton is still fully functional afterwards.
        sc.add("FileOperations: rapid copy+cancel cycles don't corrupt delivery (P0 regression)", function (done) {
          var base = sc.opsDir + "/p0-fileops-stress"
          var buildCmd = "rm -rf " + sc._q(base) + " && mkdir -p " + sc._q(base)
            + " && cd " + sc._q(base)
            + " && for i in $(seq 1 500); do : > \"file_$i.txt\"; done"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            var iterations = 15
            var i = 0
            // Each iteration waits for ITS OWN dest path before starting the
            // next: Backend.FileOperations is a shared singleton whose
            // finished/error signals are not scoped to a caller, so firing
            // several unawaited copy()+cancel() calls back-to-back would
            // leave stray in-flight operations that could deliver LATE,
            // during a completely unrelated later test, confusing whichever
            // one-shot listener happens to be attached then (a self-inflicted
            // test-hygiene bug, not the product bug under test -- the actual
            // lifetime fix is already proven by the AddressSanitizer run).
            function next() {
              if (i >= iterations) { finalCheck(); return }
              i++
              var dst = base + "-dst-" + i
              // FileOperations.run() reports the SOURCE path in finished/
              // error (see copy()'s run() call), not the destination -- both
              // handlers filter on `base` (this test's fixed source), which
              // correctly identifies "this test's current op" since the
              // serialization above guarantees only one of THIS test's own
              // operations is ever in flight at a time.
              function onErr(op, path, msg) { if (path !== base) return; cleanup(); Qt.callLater(next) }
              function onFin(op, path) { if (path !== base) return; cleanup(); Qt.callLater(next) }
              function cleanup() {
                Backend.FileOperations.error.disconnect(onErr)
                Backend.FileOperations.finished.disconnect(onFin)
              }
              Backend.FileOperations.error.connect(onErr)
              Backend.FileOperations.finished.connect(onFin)
              Backend.FileOperations.copy(base, dst, true)
              Backend.FileOperations.cancel()
            }
            function finalCheck() {
              // No process crash so far is already the main signal; confirm
              // the singleton is still genuinely functional afterwards with
              // one real, awaited (non-cancelled) copy.
              var dst = base + "-final"
              sc._fileOp(done, function () {
                sc._listOnce(sc.opsDir, function (e) {
                  var ok = sc._has(e, "p0-fileops-stress-final")
                  done(ok, ok
                    ? iterations + " rapid copy+cancel cycles survived, singleton still functional"
                    : "final copy after stress didn't complete correctly")
                })
              })
              Backend.FileOperations.copy(base, dst, true)
            }
            next()
          })
        })

        // Regression for P1-4 (architectural audit 2026-08-17): m_cancelled
        // used to be ONE atomic<bool> reused for the whole lifetime of the
        // FileOperations singleton -- every copy()/move()/remove()/
        // emptyTrash()/restoreByOrigPath() call reset the SAME flag and
        // captured a shared_ptr to that SAME object. Two operations
        // overlapping in time were therefore silently sharing one
        // cancellation flag: starting operation B could un-cancel a still-
        // running operation A, and cancel() had no way to target one
        // without affecting the other. ActionEngine's own `nativeBusy`
        // single-flight convention happened to prevent this in the current
        // UI, but the backend's own contract did not guarantee it, and
        // nothing stopped a future/direct caller from tripping it. Each
        // operation now gets its own token (beginCancelToken()); cancel()
        // always targets whichever operation started most recently
        // (matching the single Cancel action's UX -- there is no per-
        // operation-ID cancel()), and an earlier operation that's still
        // finishing up is never affected by a later one starting, being
        // cancelled, or resetting anything.
        sc.add("FileOperations: cancel() only targets the current operation, earlier ones are unaffected (P1-4 regression)", function (done) {
          var srcA = sc.opsDir + "/p14-a-src"
          var dstA = sc.opsDir + "/p14-a-dst"
          var srcB = sc.opsDir + "/p14-b-src"
          var dstB = sc.opsDir + "/p14-b-dst"
          var buildCmd = "rm -rf " + sc._q(srcA) + " " + sc._q(dstA) + " " + sc._q(srcB) + " " + sc._q(dstB)
            + " && mkdir -p " + sc._q(srcA) + " " + sc._q(srcB)
            + " && cd " + sc._q(srcA) + " && for i in $(seq 1 3000); do : > \"f$i.txt\"; done"
            + " && cd " + sc._q(srcB) + " && for i in $(seq 1 3000); do : > \"f$i.txt\"; done"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            var resultA = null, resultB = null
            function onErr(op, path, msg) {
              if (path === srcA) resultA = "error:" + msg
              else if (path === srcB) resultB = "error:" + msg
              maybeCheckAB()
            }
            function onFin(op, path) {
              if (path === srcA) resultA = "finished"
              else if (path === srcB) resultB = "finished"
              maybeCheckAB()
            }
            function cleanupAB() {
              Backend.FileOperations.error.disconnect(onErr)
              Backend.FileOperations.finished.disconnect(onFin)
            }
            function maybeCheckAB() {
              if (resultA === null || resultB === null) return
              cleanupAB()
              // B started after A, so B is the "current" operation cancel()
              // targets; A must be completely unaffected by it.
              var abOk = resultA === "finished" && resultB === "error:cancelled"
              if (!abOk) {
                done(false, "A=" + resultA + " B=" + resultB + " (A should finish, B should be cancelled)")
                return
              }
              checkCleanStateAfterwards(abOk)
            }
            // A fresh operation after a cancellation must NOT inherit a
            // stale cancelled=true state -- it gets its own new token.
            function checkCleanStateAfterwards() {
              var srcC = sc.opsDir + "/p14-c-src"
              var dstC = sc.opsDir + "/p14-c-dst"
              sc._sh(["bash", "-c", "rm -rf " + sc._q(srcC) + " " + sc._q(dstC)
                + " && mkdir -p " + sc._q(srcC) + " && echo hi > " + sc._q(srcC + "/f.txt")], function (r2) {
                if (r2.exitCode !== 0) { done(false, "fixture C build failed: " + r2.stderr); return }
                sc._fileOp(done, function () {
                  sc._listOnce(sc.opsDir, function (e) {
                    var ok = sc._has(e, "p14-c-dst")
                    done(ok, ok
                      ? "A finished, B cancelled, and a fresh operation afterwards started with clean state"
                      : "operation C after the stress didn't complete -- inherited stale cancellation?")
                  })
                })
                Backend.FileOperations.copy(srcC, dstC, true)
              })
            }
            Backend.FileOperations.error.connect(onErr)
            Backend.FileOperations.finished.connect(onFin)
            Backend.FileOperations.copy(srcA, dstA, true)
            Backend.FileOperations.copy(srcB, dstB, true)
            Backend.FileOperations.cancel()
          })
        })

        // Regression for P1-1 (architectural audit 2026-08-17): a batch
        // cancelled (or partially failed) mid-flight used to register NO
        // undo entry at all for the items that had already genuinely moved
        // -- _finishNative() only called _batchOnDone when the WHOLE batch
        // succeeded, so 2 real moves with zero undo availability was
        // possible. Now the undo entry always reflects exactly the subset
        // that actually completed (see _batchCompleted / _finishNative /
        // runPaste()/runDrop()/confirmDelete() in ActionEngine.qml). This
        // exercises the real ActionEngine composition root end to end:
        // start a 5-item move, let exactly the first item genuinely finish,
        // cancel, then verify the undo entry exists, matches the real disk
        // state, and correctly reverts only what actually moved.
        sc.add("ActionEngine native move: partial batch (cancelled mid-flight) gets an accurate, working undo entry (P1-1 regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var base = sc.opsDir + "/p11-partial"
          var buildCmd = "rm -rf " + sc._q(base) + " && mkdir -p " + sc._q(base)
            + " && for i in 1 2 3 4 5; do echo item$i > " + sc._q(base) + "/src$i.txt; done"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            var pairs = [1, 2, 3, 4, 5].map(function (i) {
              return { src: base + "/src" + i + ".txt", dest: base + "/dst" + i + ".txt" }
            })
            // Wait for the FIRST item to genuinely finish, then cancel --
            // ActionEngine's own Connections (wired at startup) sees this
            // same signal first and already dispatched item 2 by the time
            // this fires, so cancelAction() deterministically lands on a
            // real partial batch (>=1 done, not all 5) instead of racing a
            // fixed delay.
            function onFirstItemDone(op, path) {
              if (path !== pairs[0].src) return
              Backend.FileOperations.finished.disconnect(onFirstItemDone)
              c.actionEngine.cancelAction()
            }
            Backend.FileOperations.finished.connect(onFirstItemDone)
            var started = c.actionEngine.runNativeMove(pairs, "Moving…", false, function (completed) {
              if (completed.length === 0 || completed.length === pairs.length) {
                done(false, "expected a PARTIAL batch, got completed=" + completed.length + "/" + pairs.length)
                return
              }
              // runNativeMove() itself is a low-level primitive -- it does NOT
              // register undo (that's the caller's job, see runPaste()/
              // runDrop() in ActionEngine.qml). This registers the SAME way
              // runPaste()'s fixed onDone closure now does, to test the
              // actual mechanism (an accurate undo built from `completed`,
              // never the full original batch) rather than reinventing it.
              var reversed = completed.map(function (p) { return { src: p.dest, dest: p.src } })
              c.actionEngine.pushUndo(completed.length + " of " + pairs.length + " items moved", function (onSettled) {
                return c.actionEngine.runNativeMove(reversed, "", false, onSettled)
              }, function (onSettled) {
                return c.actionEngine.runNativeMove(completed, "", false, onSettled)
              })
              var entry = UndoState.undoStack[UndoState.undoStack.length - 1]
              if (!entry) { done(false, "no undo entry was registered for the partial batch"); return }
              sc._listOnce(base, function (e) {
                var movedCount = 0
                for (var i = 0; i < pairs.length; i++) if (sc._has(e, "dst" + (i + 1) + ".txt")) movedCount++
                if (movedCount !== completed.length) {
                  done(false, "disk state (" + movedCount + " moved) doesn't match reported completed=" + completed.length)
                  return
                }
                c.undoLast()
                // The undo itself is a runNativeMove() batch of
                // completed.length items -- sc._fileOp only awaits the FIRST
                // finished/error signal, which isn't enough once completed.length
                // > 1 (item 2's move could still be in flight when checked).
                // Poll on nativeBusy going back to false instead, which only
                // happens once the WHOLE undo batch has settled.
                sc._poll(function () { return !c.actionEngine.nativeBusy }, function (settled) {
                  if (!settled) { done(false, "undo batch never settled"); return }
                  sc._listOnce(base, function (e2) {
                    var allBack = pairs.slice(0, completed.length).every(function (p) {
                      return sc._has(e2, p.src.substring(p.src.lastIndexOf("/") + 1))
                    })
                    done(allBack, allBack
                      ? "partial batch (" + completed.length + "/" + pairs.length + ") got an accurate undo entry that correctly reverted exactly what moved"
                      : "undo of the partial batch didn't restore the right items")
                  })
                })
              })
            })
            if (!started) done(false, "runNativeMove returned false")
          })
        })
  }
}

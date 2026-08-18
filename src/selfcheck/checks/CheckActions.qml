import QtQuick
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// ActionEngine / Undo / Redo domain checks.
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Undo + redo move (full cycle)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var work = sc.opsDir + "/ur-src.txt"
          var dst = sc.opsDir + "/ur-dst.txt"
          sc._fileOp(done, function () {
            var pairs = [{ src: work, dest: dst }]
            c.actionEngine.runNativeMove(pairs, "Moving…", false, function () {
              var reversed = [{ src: dst, dest: work }]
              c.actionEngine.pushUndo("move test",
                function (onSettled) { return c.actionEngine.runNativeMove(reversed, "", false, onSettled) },
                function (onSettled) { return c.actionEngine.runNativeMove(pairs, "", false, onSettled) })
              sc._fileOp(done, function () {
                sc._listOnce(sc.opsDir, function (e) {
                  var undone = sc._has(e, "ur-src.txt") && !sc._has(e, "ur-dst.txt")
                  if (!undone) { done(false, "undo failed"); return }
                  sc._fileOp(done, function () {
                    sc._listOnce(sc.opsDir, function (e2) {
                      var redone = sc._has(e2, "ur-dst.txt") && !sc._has(e2, "ur-src.txt")
                      done(redone, redone ? "undo and redo OK" : "redo didn't re-apply")
                    })
                  })
                  c.redoLast()
                })
              })
              c.undoLast()
            })
          })
          Backend.FileOperations.copy(sc.note, work)
        })

        sc.add("Undo + redo trash (full cycle)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var work = sc.opsDir + "/urt-src.txt"
          sc._fileOp(done, function () {
            c.actionEngine.runNativeTrash([work], "", function () {
              c.actionEngine.pushUndo("delete test",
                function (onSettled) { return c.actionEngine.runNativeRestore([work], "", onSettled) },
                function (onSettled) { return c.actionEngine.runNativeTrash([work], "", onSettled) })
              sc._fileOp(done, function () {
                sc._listOnce(sc.opsDir, function (e) {
                  var undone = sc._has(e, "urt-src.txt")
                  if (!undone) { done(false, "undo didn't restore"); return }
                  sc._fileOp(done, function () {
                    sc._listOnce(sc.opsDir, function (e2) {
                      var redone = !sc._has(e2, "urt-src.txt")
                      done(redone, redone ? "undo and redo trash OK" : "redo trash failed")
                    })
                  })
                  c.redoLast()
                })
              })
              c.undoLast()
            })
          })
          Backend.FileOperations.copy(sc.note, work)
        })

        sc.add("Undo sequence (LIFO: reverts the last one first)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var a = sc.opsDir + "/lifo-a.txt"
          var b = sc.opsDir + "/lifo-b.txt"
          var da = sc.opsDir + "/lifo-da.txt"
          var db = sc.opsDir + "/lifo-db.txt"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.note, a) },
            function () { Backend.FileOperations.copy(sc.note, b) }
          ], done, function () {
            c.actionEngine.runNativeMove([{ src: a, dest: da }], "", false, function () {
              c.actionEngine.pushUndo("move A",
                function (onSettled) { return c.actionEngine.runNativeMove([{ src: da, dest: a }], "", false, onSettled) },
                function (onSettled) { return c.actionEngine.runNativeMove([{ src: a, dest: da }], "", false, onSettled) })
              c.actionEngine.runNativeMove([{ src: b, dest: db }], "", false, function () {
                c.actionEngine.pushUndo("move B",
                  function (onSettled) { return c.actionEngine.runNativeMove([{ src: db, dest: b }], "", false, onSettled) },
                  function (onSettled) { return c.actionEngine.runNativeMove([{ src: b, dest: db }], "", false, onSettled) })
                sc._fileOp(done, function () {
                  sc._listOnce(sc.opsDir, function (e) {
                    var bReverted = sc._has(e, "lifo-b.txt") && sc._has(e, "lifo-da.txt")
                    if (!bReverted) { done(false, "first undo didn't revert B"); return }
                    sc._fileOp(done, function () {
                      sc._listOnce(sc.opsDir, function (e2) {
                        var aReverted = sc._has(e2, "lifo-a.txt")
                        done(aReverted, aReverted ? "LIFO OK: B and then A" : "second undo didn't revert A")
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

        sc.add("Cancel then undo (cancellation doesn't alter the stack)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var work = sc.opsDir + "/ctu-src.txt"
          var dst = sc.opsDir + "/ctu-dst.txt"
          sc._fileOp(done, function () {
            var pairs = [{ src: work, dest: dst }]
            c.actionEngine.runNativeMove(pairs, "", false, function () {
              var reversed = [{ src: dst, dest: work }]
              c.actionEngine.pushUndo("valid move",
                function (onSettled) { return c.actionEngine.runNativeMove(reversed, "", false, onSettled) },
                function (onSettled) { return c.actionEngine.runNativeMove(pairs, "", false, onSettled) })
              var bigDst = sc.opsDir + "/ctu-big-copy.bin"
              function onErr(op, path, msg) {
                if (path !== sc.dir + "/big.bin") return
                cleanup()
                sc._fileOp(done, function () {
                  sc._listOnce(sc.opsDir, function (e) {
                    var undone = sc._has(e, "ctu-src.txt")
                    done(undone, undone ? "undo after cancellation reverts the move" : "stack corrupted")
                  })
                })
                c.undoLast()
              }
              function onFin(op, path) { if (path !== sc.dir + "/big.bin") return; cleanup(); done(false, "big copy didn't cancel") }
              function cleanup() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
              Backend.FileOperations.error.connect(onErr)
              Backend.FileOperations.finished.connect(onFin)
              Backend.FileOperations.copy(sc.dir + "/big.bin", bigDst)
              Backend.FileOperations.cancel()
            })
          })
          Backend.FileOperations.copy(sc.note, work)
        })

        sc.add("Undo registry consistency (UndoState stacks)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          UndoState.undoStack = []
          UndoState.redoStack = []
          var work = sc.opsDir + "/urc-src.txt"
          var dst = sc.opsDir + "/urc-dst.txt"
          sc._fileOp(done, function () {
            c.actionEngine.runNativeMove([{ src: work, dest: dst }], "", false, function () {
              c.actionEngine.pushUndo("urc",
                function (onSettled) { return c.actionEngine.runNativeMove([{ src: dst, dest: work }], "", false, onSettled) },
                function (onSettled) { return c.actionEngine.runNativeMove([{ src: work, dest: dst }], "", false, onSettled) })
              var afterPush = UndoState.undoStack.length === 1 && UndoState.redoStack.length === 0
              c.undoLast()
              // undoStack.length===0 happens synchronously (undoLast() pops
              // immediately), but redoStack only gains the entry once the
              // undo genuinely completes -- exactly the "started vs
              // finished" fix this test exists to verify -- so poll for it
              // instead of assuming same-tick timing.
              sc._poll(function () { return UndoState.redoStack.length === 1 }, function (undoSettled) {
                var afterUndo = UndoState.undoStack.length === 0 && UndoState.redoStack.length === 1
                if (!undoSettled) { done(false, "undo never settled (redoStack stayed empty)"); return }
                c.redoLast()
                sc._poll(function () { return UndoState.undoStack.length === 1 }, function (redoSettled) {
                  var afterRedo = UndoState.undoStack.length === 1 && UndoState.redoStack.length === 0
                  done(afterPush && afterUndo && afterRedo,
                       "push/undo/redo stacks: " + afterPush + "/" + afterUndo + "/" + afterRedo)
                })
              })
            })
          })
          Backend.FileOperations.copy(sc.note, work)
        })

        // Directly proves the race the "started vs finished" fix (see
        // undoLast()/redoLast()'s doc comment in ActionEngine.qml) closes:
        // before the fix, undoLast() pushed the entry to redoStack as soon
        // as the undo merely STARTED, so a redo fired in the very same
        // tick (before the undo's real native move had any chance to
        // finish) would already find it there and attempt to redo
        // something whose own undo hadn't completed -- a genuine
        // correctness hazard. After the fix, redoStack is provably still
        // empty at that exact point, so the immediate redo must be a safe
        // no-op (UndoState.undoStack's own guard), and the eventual settle
        // still lands correctly once the real undo genuinely finishes.
        sc.add("Undo/redo race: redo fired in the same tick as undo doesn't fire while the undo is still in flight (correctness fix regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          UndoState.undoStack = []
          UndoState.redoStack = []
          var work = sc.opsDir + "/urace-src.txt"
          var dst = sc.opsDir + "/urace-dst.txt"
          sc._fileOp(done, function () {
            c.actionEngine.runNativeMove([{ src: work, dest: dst }], "", false, function () {
              c.actionEngine.pushUndo("urace",
                function (onSettled) { return c.actionEngine.runNativeMove([{ src: dst, dest: work }], "", false, onSettled) },
                function (onSettled) { return c.actionEngine.runNativeMove([{ src: work, dest: dst }], "", false, onSettled) })
              c.undoLast()
              var redoStackHadEntryTooEarly = UndoState.redoStack.length > 0
              c.redoLast() // same tick, real undo above hasn't had a chance to settle yet
              var immediateRedoFired = UndoState.undoStack.length > 0 // redoLast() re-pushes to undoStack only if it actually fires
              sc._poll(function () { return UndoState.redoStack.length === 1 }, function (settled) {
                var finalOk = settled && UndoState.undoStack.length === 0 && UndoState.redoStack.length === 1
                sc._listOnce(sc.opsDir, function (e) {
                  var diskOk = sc._has(e, "urace-src.txt") && !sc._has(e, "urace-dst.txt")
                  var pass = !redoStackHadEntryTooEarly && !immediateRedoFired && finalOk && diskOk
                  done(pass, pass ? "redo correctly no-opped while undo was still in flight, settled correctly afterward"
                                   : "tooEarly=" + redoStackHadEntryTooEarly + " immediateFired=" + immediateRedoFired + " finalOk=" + finalOk + " diskOk=" + diskOk)
                })
              })
            })
          })
          Backend.FileOperations.copy(sc.note, work)
        })

        // Transfer queue (V1.1): copy/move issued while another one is
        // already running used to be flatly rejected ("still busy — try
        // again"); now it's queued and runs automatically once the first
        // one frees up. Both runNativeCopy() calls happen in the SAME JS
        // tick here on purpose -- nativeBusy is set synchronously inside
        // _runNative() before any Qt signal has a chance to fire, so the
        // second call is deterministically forced onto the queue path
        // regardless of how fast the underlying copy actually completes.
        sc.add("Transfer queue: a second native copy issued while the first is still running gets queued, not rejected", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var srcA = sc.opsDir + "/tq-a.txt"
          var srcB = sc.opsDir + "/tq-b.txt"
          var dstA = sc.opsDir + "/tq-a-dst.txt"
          var dstB = sc.opsDir + "/tq-b-dst.txt"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.note, srcA) },
            function () { Backend.FileOperations.copy(sc.note, srcB) }
          ], done, function () {
            var startedA = c.actionEngine.runNativeCopy([{ src: srcA, dest: dstA }], "Copying A…", false, function () {})
            var startedB = c.actionEngine.runNativeCopy([{ src: srcB, dest: dstB }], "Copying B…", false, function () {})
            var queuedImmediately = c.actionEngine._transferQueue.length === 1
            sc._poll(function () { return c.actionEngine._transferQueue.length === 0 && !c.actionEngine.nativeBusy }, function () {
              sc._listOnce(sc.opsDir, function (e) {
                var bothCopied = sc._has(e, "tq-a-dst.txt") && sc._has(e, "tq-b-dst.txt")
                var pass = startedA === true && startedB === true && queuedImmediately && bothCopied
                done(pass, pass ? "both queued copies landed on disk"
                                 : "startedA=" + startedA + " startedB=" + startedB + " queuedImmediately=" + queuedImmediately + " bothCopied=" + bothCopied)
              })
            })
          })
        })

        // Same queue, but crossing kinds (native copy busy -> an archive job
        // arrives): proves _transferQueue is one shared FIFO across
        // _runNative() and runActionWithProgress(), not two separate ones
        // that happen to look similar.
        sc.add("Transfer queue: an archive job issued while a native copy is running gets queued (shared queue across kinds)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var work = sc.opsDir + "/tq-arch-src.txt"
          var dst = sc.opsDir + "/tq-arch-dst.txt"
          sc._fileOp(done, function () {
            var startedCopy = c.actionEngine.runNativeCopy([{ src: work, dest: dst }], "Copying…", false, function () {})
            var archiveRan = false
            var startedArchive = c.actionEngine.runActionWithProgress("true", "Archive test…", 0, function () { archiveRan = true })
            var queuedImmediately = c.actionEngine._transferQueue.length === 1 && !c.actionEngine.archiveBusy
            sc._poll(function () { return archiveRan && c.actionEngine._transferQueue.length === 0 }, function (settled) {
              var pass = startedCopy === true && startedArchive === true && queuedImmediately && settled
              done(pass, pass ? "queued archive job ran automatically once the native copy freed up"
                               : "startedCopy=" + startedCopy + " startedArchive=" + startedArchive + " queuedImmediately=" + queuedImmediately + " settled=" + settled)
            })
          })
          Backend.FileOperations.copy(sc.note, work)
        })

        // cancelQueuedJob() (V1.1): drops a still-pending entry before it
        // ever runs -- `run` is discarded, never invoked, so B's dest must
        // never appear on disk once A (the active one) finishes.
        sc.add("Transfer queue: cancelling a pending job drops it before it runs, active job unaffected", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var srcA = sc.opsDir + "/tqc-a.txt"
          var srcB = sc.opsDir + "/tqc-b.txt"
          var dstA = sc.opsDir + "/tqc-a-dst.txt"
          var dstB = sc.opsDir + "/tqc-b-dst.txt"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.note, srcA) },
            function () { Backend.FileOperations.copy(sc.note, srcB) }
          ], done, function () {
            var startedA = c.actionEngine.runNativeCopy([{ src: srcA, dest: dstA }], "Copying A…", false, function () {})
            var startedB = c.actionEngine.runNativeCopy([{ src: srcB, dest: dstB }], "Copying B…", false, function () {})
            var queuedImmediately = c.actionEngine._transferQueue.length === 1
            c.actionEngine.cancelQueuedJob(0)
            var droppedImmediately = c.actionEngine._transferQueue.length === 0
            sc._poll(function () { return !c.actionEngine.nativeBusy && c.actionEngine._transferQueue.length === 0 }, function () {
              sc._listOnce(sc.opsDir, function (e) {
                var aCopied = sc._has(e, "tqc-a-dst.txt")
                var bNeverRan = !sc._has(e, "tqc-b-dst.txt") && sc._has(e, "tqc-b.txt")
                var pass = startedA === true && startedB === true && queuedImmediately && droppedImmediately && aCopied && bNeverRan
                done(pass, pass ? "cancelled pending job never ran, active copy completed normally"
                                 : "startedA=" + startedA + " startedB=" + startedB + " queuedImmediately=" + queuedImmediately
                                   + " droppedImmediately=" + droppedImmediately + " aCopied=" + aCopied + " bNeverRan=" + bNeverRan)
              })
            })
          })
        })

        sc.add("Backend.FileOperations move", function (done) {
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e) {
                var ok = sc._has(e, "move-dst.txt") && !sc._has(e, "move-src.txt")
                done(ok, ok ? "" : "move not reflected")
              })
            })
            Backend.FileOperations.move(sc.opsDir + "/move-src.txt", sc.opsDir + "/move-dst.txt")
          })
          Backend.FileOperations.copy(sc.note, sc.opsDir + "/move-src.txt")
        })

        sc.add("Backend.FileOperations remove", function (done) {
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e) {
                var ok = !sc._has(e, "del-me.txt")
                done(ok, ok ? "" : "file still exists")
              })
            })
            Backend.FileOperations.remove(sc.opsDir + "/del-me.txt")
          })
          Backend.FileOperations.copy(sc.note, sc.opsDir + "/del-me.txt")
        })

        sc.add("Backend.FileOperations trash + restore (net-zero)", function (done) {
          sc._fileOp(done, function () {
            sc._fileOp(done, function () {
              sc._listOnce(sc.opsDir, function (e) {
                if (sc._has(e, "to-trash.txt")) { done(false, "didn't move to trash"); return }
                sc._fileOp(done, function () {
                  sc._listOnce(sc.opsDir, function (e2) {
                    var ok = sc._has(e2, "to-trash.txt")
                    done(ok, ok ? "restored to its place" : "didn't restore")
                  })
                })
                Backend.FileOperations.restoreByOrigPath(sc.opsDir + "/to-trash.txt")
              })
            })
            Backend.FileOperations.trash(sc.opsDir + "/to-trash.txt")
          })
          Backend.FileOperations.copy(sc.note, sc.opsDir + "/to-trash.txt")
        })

        sc.add("Undo + redo rename (full cycle)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var oldFile = sc.opsDir + "/ren-old.txt"
          var newFile = sc.opsDir + "/ren-new.txt"
          sc._fileOp(done, function () {
            ConflictState.pendingRename = { oldPath: oldFile, newPath: newFile }
            c.controllers.actionEngine.runPendingRename(false)
            var timeout = Qt.createQmlObject('import QtQuick; Timer { interval: 60; repeat: false }', sc)
            timeout.triggered.connect(function () {
              sc._listOnce(sc.opsDir, function (e1) {
                var renamed = sc._has(e1, "ren-new.txt") && !sc._has(e1, "ren-old.txt")
                if (!renamed) { done(false, "rename failed"); return }
                c.undoLast()
                var timeout2 = Qt.createQmlObject('import QtQuick; Timer { interval: 60; repeat: false }', sc)
                timeout2.triggered.connect(function () {
                  sc._listOnce(sc.opsDir, function (e2) {
                    var undone = sc._has(e2, "ren-old.txt") && !sc._has(e2, "ren-new.txt")
                    if (!undone) { done(false, "undo rename failed"); return }
                    c.redoLast()
                    var timeout3 = Qt.createQmlObject('import QtQuick; Timer { interval: 60; repeat: false }', sc)
                    timeout3.triggered.connect(function () {
                      sc._listOnce(sc.opsDir, function (e3) {
                        var redone = sc._has(e3, "ren-new.txt") && !sc._has(e3, "ren-old.txt")
                        done(redone, redone ? "rename undo/redo OK" : "redo rename failed")
                      })
                    })
                    timeout3.start()
                  })
                })
                timeout2.start()
              })
            })
            timeout.start()
          })
          Backend.FileOperations.copy(sc.note, oldFile)
        })

        // Regression for the Phase 43 ControllerRegistry wiring break (P0-1,
        // forensic audit 2026-08-16): archive browsing's refresh()/enter()
        // reference `list` (the active ListView), and the owning component
        // must actually receive it from ControllerRegistry (unlike its
        // siblings SearchOps/TabOps/NavigationController at the time, which
        // all did). Every archive open threw a ReferenceError. Moved to
        // logic/ArchiveBrowser.qml (architectural audit 2026-08-17, P2.3);
        // updated to call the real archiveBrowser API and to descend via
        // enterSubdir() (the real UI path a folder click takes) instead of
        // poking ArchiveState.archiveSubPath by hand. This exercises the
        // REAL composition root (sc._content), so it fails again if the
        // ControllerRegistry wiring regresses.
        sc.add("Archive browsing: enter zip, list, navigate subfolder, exit (P0-1 regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var zipPath = sc.opsDir + "/p0archive-test.zip"
          var buildCmd = "cd " + sc._q(sc.opsDir)
            + " && rm -rf p0archive-src && mkdir -p p0archive-src/p0archive-sub"
            + " && echo root > p0archive-src/p0archive-root.txt"
            + " && echo inner > p0archive-src/p0archive-sub/p0archive-inner.txt"
            + " && (cd p0archive-src && zip -q -r " + sc._q(zipPath) + " .)"
            + " && rm -rf p0archive-src"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            c.archiveBrowser.enter(zipPath)
            sc._poll(function () {
              return sc._has(NavState.entries, "p0archive-root.txt") && sc._has(NavState.entries, "p0archive-sub")
            }, function (okRoot) {
              if (!okRoot) {
                c.archiveBrowser.exit()
                done(false, "archive root never listed correctly (inArchive=" + ArchiveState.inArchive + ")")
                return
              }
              c.archiveBrowser.enterSubdir("p0archive-sub")
              sc._poll(function () { return sc._has(NavState.entries, "p0archive-inner.txt") }, function (okSub) {
                var wasInArchive = ArchiveState.inArchive
                c.archiveBrowser.exit()
                var exitOk = ArchiveState.inArchive === false
                done(okSub && wasInArchive && exitOk,
                  "sub-listing=" + okSub + " wasInArchive=" + wasInArchive + " exitOk=" + exitOk)
              })
            })
          })
        })

        // .zst was already in FileTypeConfig.archiveExt (icon) but missing
        // from tarExt (browse/extract gate), so a .tar.zst showed an
        // archive icon that did nothing when double-clicked -- V1.1 P2
        // fix. GNU tar auto-detects zstd compression from content on read
        // (confirmed directly against a real .tar.zst, no special flag
        // needed), so the fix is just adding "zst" to
        // state/FileTypeConfig.qml's tarExt list + the matching case arm
        // in scripts/runtime/list-archive.sh (its own, separate extension
        // whitelist). This exercises both edits together via the real
        // ArchiveBrowser.enter() -> list-archive.sh path. Fixture uses an
        // explicit member name (not "tar -C dir ."), matching the
        // convention CheckIntegration.qml:56 already established --
        // "tar -C dir ." emits "./"-prefixed entries that trip a
        // DIFFERENT, already-documented list-archive.sh quirk (see
        // "empty archive" test below), unrelated to this fix.
        sc.add("Archive browsing: .tar.zst is browsable (V1.1 regression, .zst inconsistency fix)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var zstPath = sc.opsDir + "/p2zst-test.tar.zst"
          var buildCmd = "cd " + sc._q(sc.opsDir)
            + " && rm -rf p2zst-src && mkdir -p p2zst-src"
            + " && echo hello > p2zst-src/p2zst-file.txt"
            + " && tar --zstd -cf " + sc._q(zstPath) + " -C p2zst-src p2zst-file.txt"
            + " && rm -rf p2zst-src"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            c.archiveBrowser.enter(zstPath)
            sc._poll(function () { return sc._has(NavState.entries, "p2zst-file.txt") }, function (listedOk) {
              var wasInArchive = ArchiveState.inArchive
              c.archiveBrowser.exit()
              var pass = listedOk && wasInArchive
              done(pass, pass ? "tar.zst detected and listed correctly (previously not recognized as an archive)"
                               : "listed=" + listedOk + " wasInArchive=" + wasInArchive)
            })
          })
        })

        // ======================= ArchiveBrowser (P2.3 extraction) =======================

        sc.add("ArchiveBrowser: nested subdirs, up() ascends one level at a time, exit() only at root", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var zipPath = sc.opsDir + "/p23-nested.zip"
          var buildCmd = "cd " + sc._q(sc.opsDir)
            + " && rm -rf p23nsrc && mkdir -p p23nsrc/a/b"
            + " && echo c > p23nsrc/a/b/c.txt"
            + " && (cd p23nsrc && zip -q -r " + sc._q(zipPath) + " .)"
            + " && rm -rf p23nsrc"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            c.archiveBrowser.enter(zipPath)
            sc._poll(function () { return sc._has(NavState.entries, "a") }, function (okRoot) {
              if (!okRoot) { c.archiveBrowser.exit(); done(false, "archive root never listed 'a'"); return }
              c.archiveBrowser.enterSubdir("a")
              sc._poll(function () { return sc._has(NavState.entries, "b") && ArchiveState.archiveSubPath === "a" }, function (okA) {
                if (!okA) { c.archiveBrowser.exit(); done(false, "didn't descend into 'a'"); return }
                c.archiveBrowser.enterSubdir("b")
                sc._poll(function () { return sc._has(NavState.entries, "c.txt") && ArchiveState.archiveSubPath === "a/b" }, function (okB) {
                  if (!okB) { c.archiveBrowser.exit(); done(false, "didn't descend into 'a/b'"); return }
                  // up() from a/b -> a (still inArchive, NOT exited)
                  c.archiveBrowser.up()
                  sc._poll(function () { return ArchiveState.archiveSubPath === "a" && ArchiveState.inArchive }, function (okUp1) {
                    if (!okUp1) { c.archiveBrowser.exit(); done(false, "up() from a/b landed on '" + ArchiveState.archiveSubPath + "', inArchive=" + ArchiveState.inArchive); return }
                    // up() from a -> root (still inArchive, NOT exited)
                    c.archiveBrowser.up()
                    sc._poll(function () { return ArchiveState.archiveSubPath === "" && ArchiveState.inArchive }, function (okUp2) {
                      if (!okUp2) { c.archiveBrowser.exit(); done(false, "up() from 'a' landed on '" + ArchiveState.archiveSubPath + "', inArchive=" + ArchiveState.inArchive); return }
                      // up() from the archive root -> real exit
                      c.archiveBrowser.up()
                      done(!ArchiveState.inArchive, "up()-chain ascended one level at a time and only exited at the true root, inArchive=" + ArchiveState.inArchive)
                    })
                  })
                })
              })
            })
          })
        })

        sc.add("ArchiveBrowser: many entries, spaces, and Unicode filenames list correctly", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var zipPath = sc.opsDir + "/p23-many.zip"
          var manyTouch = ""
          for (var i = 0; i < 40; i++) manyTouch += "touch p23msrc/many-" + i + ".txt && "
          var buildCmd = "cd " + sc._q(sc.opsDir)
            + " && rm -rf p23msrc && mkdir -p p23msrc"
            + " && " + manyTouch
            + "touch " + sc._q("p23msrc/file with spaces.txt")
            + " && touch " + sc._q("p23msrc/café ñ 文件.txt")
            + " && (cd p23msrc && zip -q -r " + sc._q(zipPath) + " .)"
            + " && rm -rf p23msrc"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            c.archiveBrowser.enter(zipPath)
            sc._poll(function () { return NavState.entries.length >= 42 }, function (listed) {
              var hasSpaces = sc._has(NavState.entries, "file with spaces.txt")
              var hasUnicode = sc._has(NavState.entries, "café ñ 文件.txt")
              c.archiveBrowser.exit()
              done(listed && hasSpaces && hasUnicode,
                "entries=" + NavState.entries.length + " spaces=" + hasSpaces + " unicode=" + hasUnicode)
            })
          })
        })

        // NOT a test of "correct" empty-archive listing -- scripts/runtime/
        // list-archive.sh has a PRE-EXISTING bug (unrelated to this
        // extraction, not fixed here per its "ownership refactor, preserve
        // behavior exactly" scope): a truly empty tar's `tar tf` prints the
        // archive's own "./" root entry, which the script's parser turns
        // into a bogus single "." directory row instead of zero entries
        // (the zip case has an analogous issue: `unzip -Z1` prints "Empty
        // zipfile." to stdout, which gets parsed as a fake filename). This
        // test's job is only to confirm the EXTRACTION didn't change that
        // pre-existing behavior, and that entering/exiting an empty archive
        // still doesn't hang or crash -- not that the behavior is correct.
        sc.add("ArchiveBrowser: empty archive doesn't crash or hang, exit() still clean (documents pre-existing list-archive.sh quirk)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var tarPath = sc.opsDir + "/p23-empty.tar"
          var buildCmd = "rm -rf " + sc._q(sc.opsDir + "/p23esrc") + " && mkdir -p " + sc._q(sc.opsDir + "/p23esrc")
            + " && tar cf " + sc._q(tarPath) + " -C " + sc._q(sc.opsDir + "/p23esrc") + " ."
            + " && rm -rf " + sc._q(sc.opsDir + "/p23esrc")
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            c.archiveBrowser.enter(tarPath)
            var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 300; repeat: false }', sc)
            timer.triggered.connect(function () {
              var enteredOk = ArchiveState.inArchive === true
              var boundedOk = NavState.entries.length <= 1 // known quirk: 0 or the bogus "."
              c.archiveBrowser.exit()
              var exitOk = ArchiveState.inArchive === false
              done(enteredOk && boundedOk && exitOk,
                "entered=" + enteredOk + " entries=" + NavState.entries.length + " exitOk=" + exitOk)
            })
            timer.start()
          })
        })

        sc.add("ArchiveBrowser: invalid archive lists empty without crashing, exit() still clean", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var fakePath = sc.opsDir + "/p23-fake.zip"
          sc._sh(["bash", "-c", "echo 'not a real zip' > " + sc._q(fakePath)], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed"); return }
            c.archiveBrowser.enter(fakePath)
            var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 300; repeat: false }', sc)
            timer.triggered.connect(function () {
              var enteredOk = ArchiveState.inArchive === true
              var emptyOk = NavState.entries.length === 0
              c.archiveBrowser.exit()
              var exitOk = ArchiveState.inArchive === false
              done(enteredOk && emptyOk && exitOk,
                "entered=" + enteredOk + " empty=" + emptyOk + " (entries=" + NavState.entries.length + ") exitOk=" + exitOk)
            })
            timer.start()
          })
        })

        sc.add("ArchiveBrowser: real navigateTo() while inArchive force-exits silently (forceExit regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var zipPath = sc.opsDir + "/p23-forceexit.zip"
          var buildCmd = "cd " + sc._q(sc.opsDir)
            + " && rm -rf p23fsrc && mkdir p23fsrc && echo x > p23fsrc/inside.txt"
            + " && (cd p23fsrc && zip -q -r " + sc._q(zipPath) + " .)"
            + " && rm -rf p23fsrc"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            c.archiveBrowser.enter(zipPath)
            sc._poll(function () { return sc._has(NavState.entries, "inside.txt") }, function (listed) {
              if (!listed) { c.archiveBrowser.exit(); done(false, "archive never listed"); return }
              // Real navigation elsewhere (a bookmark/tab/back-forward/edit-path
              // all funnel through navController.navigateTo -> _goToPath, same
              // as this call) -- must silently leave archive mode via
              // forceExit(), WITHOUT re-listing the archive's real parent dir
              // first (that would be wasted work _goToPath immediately discards).
              c.navController.navigateTo(sc.opsDir)
              sc._poll(function () { return NavState.currentPath === sc.opsDir && sc._has(NavState.visibleEntries, "p23-forceexit.zip") }, function (okNav) {
                var exitedCleanly = ArchiveState.inArchive === false && ArchiveState.archivePath === "" && ArchiveState.archiveSubPath === ""
                NavState.currentPath = prevPath
                done(okNav && exitedCleanly,
                  "navigated=" + okNav + " archiveState cleared=" + exitedCleanly)
              })
            })
          })
        })

        sc.add("ArchiveBrowser: tab switch saves and restores archive position (TabOps regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var tabOps = c.controllers.tabOps
          var prevPath = NavState.currentPath
          var zipPath = sc.opsDir + "/p23-tabs.zip"
          var buildCmd = "cd " + sc._q(sc.opsDir)
            + " && rm -rf p23tsrc && mkdir -p p23tsrc/sub && echo x > p23tsrc/sub/deep.txt"
            + " && (cd p23tsrc && zip -q -r " + sc._q(zipPath) + " .)"
            + " && rm -rf p23tsrc"
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            c.navController.navigateTo(sc.opsDir)
            c.archiveBrowser.enter(zipPath)
            sc._poll(function () { return sc._has(NavState.entries, "sub") }, function () {
              c.archiveBrowser.enterSubdir("sub")
              sc._poll(function () { return sc._has(NavState.entries, "deep.txt") }, function (listedSub) {
                if (!listedSub) { c.archiveBrowser.exit(); NavState.currentPath = prevPath; done(false, "didn't descend into sub"); return }
                var startTabs = TabsState.tabs.length
                // openInNewTab (not newTab(), which doesn't call _goToPath and
                // so doesn't force-exit archive mode on its own -- a separate,
                // pre-existing TabOps nuance, not touched here) saves tab 0
                // (mid-archive) for real via saveActiveTab(), then creates+
                // activates tab 1 pointing at a real directory via _goToPath,
                // which force-exits archive mode for the new tab.
                tabOps.openInNewTab(sc.opsDir)
                sc._poll(function () { return TabsState.activeTabIndex === 1 && !ArchiveState.inArchive }, function (okNewTab) {
                  if (!okNewTab) { done(false, "openInNewTab() didn't land on a real (non-archive) tab 1"); return }
                  tabOps.switchToTab(0) // must restore tab 0's saved archive position
                  sc._poll(function () {
                    return ArchiveState.inArchive && ArchiveState.archivePath === zipPath && ArchiveState.archiveSubPath === "sub"
                      && sc._has(NavState.entries, "deep.txt")
                  }, function (okRestore) {
                    var restoredArchivePath = ArchiveState.archivePath
                    var restoredSubPath = ArchiveState.archiveSubPath
                    var restoredListed = sc._has(NavState.entries, "deep.txt")
                    // Cleanup via the real close path: land on tab 1, close it
                    // (closeTab() closes the ACTIVE tab), back to a single tab 0.
                    tabOps.switchToTab(1)
                    sc._poll(function () { return TabsState.activeTabIndex === 1 }, function () {
                      tabOps.closeTab()
                      sc._poll(function () { return TabsState.tabs.length === startTabs }, function () {
                        c.archiveBrowser.exit()
                        NavState.currentPath = prevPath
                        done(okRestore, "restored archivePath match=" + (restoredArchivePath === zipPath)
                          + " subPath=" + restoredSubPath + " listed=" + restoredListed)
                      })
                    })
                  })
                })
              })
            })
          })
        })

        // P2.7 (2026-08-17): actionProc.onFinished's fallback error message
        // used to be the stale "Couldn't restore from trash" for every
        // shell-based action (rename/bulk-rename/chmod/compress/extract/
        // make-link), not just restore (which no longer even goes through
        // this handler -- see the fix's own comment in ActionEngine.qml).
        // Backend.Notifier.notify() is a detached "notify-send" call with
        // no return value/signal to assert the exact string against
        // without faking notify-send via PATH injection -- deliberately
        // not done here to avoid new test infrastructure for a one-line
        // message fix. What IS verified, on the real composition root's
        // real actionEngine: a command that fails with genuinely empty
        // stderr ("false", exits 1, no output) runs the fallback branch
        // to completion (busy state resets, no exception, onSuccess never
        // fires) -- i.e. the exact branch the string lives in.
        sc.add("Action failure with empty stderr resets busy state cleanly (fallback error message regression, P2.7)", function (done) {
          var c = sc._content
          if (!c || !c.actionEngine) { done(false, "no composition root"); return }
          var successCalled = false
          var started = c.actionEngine.runAction("false", "P2.7 regression: empty-stderr failure", function () { successCalled = true })
          if (!started) { done(false, "runAction rejected (still busy from a previous test?)"); return }
          sc._poll(function () { return !ActionState.actionBusy }, function (settled) {
            done(settled && !successCalled, settled
              ? (successCalled ? "onSuccess fired for a command that exited 1" : "failure branch ran to completion, busy state reset, onSuccess correctly not called")
              : "actionBusy never cleared")
          })
        })

        // ======================= Bulk rename (P2.7, 2026-08-17) =======================
        // The P2.6 audit found bulk rename fully implemented but with zero
        // regression coverage despite its own code comment calling it out
        // as historically risky. All three below drive the REAL
        // composition root (c.actionEngine.commitBulkRename(), the exact
        // function dialogs/BulkRenamePanel.qml's "Rename" button calls),
        // real NavState/SelectionState, real fixture files -- not a
        // reimplementation of the rename logic.
        sc.add("Bulk rename: pattern applies to multiple files, with undo/redo (P2.7)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var stamp = Date.now()
          var aName = "br-a-" + stamp + ".txt"
          var bName = "br-b-" + stamp + ".txt"
          var newA = "br-a-" + stamp + "-renamed.txt"
          var newB = "br-b-" + stamp + "-renamed.txt"
          var aPath = sc.opsDir + "/" + aName
          var bPath = sc.opsDir + "/" + bName
          Backend.FileOperations.copy(sc.note, aPath)
          sc._fileOp(done, function () {
            Backend.FileOperations.copy(sc.note, bPath)
            sc._fileOp(done, function () {
              c.navController.navigateTo(sc.opsDir)
              sc._poll(function () {
                return NavState.currentPath === sc.opsDir && sc._has(NavState.visibleEntries, aName) && sc._has(NavState.visibleEntries, bName)
              }, function (listed) {
                if (!listed) { NavState.currentPath = prevPath; done(false, "fixtures never appeared"); return }
                if (!sc._selectByNames([aName, bName])) { NavState.currentPath = prevPath; done(false, "selection failed"); return }
                DialogsState.bulkRenamePattern = "{name}-renamed{ext}"
                c.actionEngine.commitBulkRename()
                sc._poll(function () {
                  return sc._has(NavState.visibleEntries, newA) && sc._has(NavState.visibleEntries, newB) && !sc._has(NavState.visibleEntries, aName)
                }, function (renamed) {
                  if (!renamed) { NavState.currentPath = prevPath; done(false, "rename didn't apply"); return }
                  c.actionEngine.undoLast()
                  sc._poll(function () {
                    return sc._has(NavState.visibleEntries, aName) && sc._has(NavState.visibleEntries, bName) && !sc._has(NavState.visibleEntries, newA)
                  }, function (undone) {
                    if (!undone) { NavState.currentPath = prevPath; done(false, "undo didn't restore original names"); return }
                    c.actionEngine.redoLast()
                    sc._poll(function () {
                      return sc._has(NavState.visibleEntries, newA) && sc._has(NavState.visibleEntries, newB)
                    }, function (redone) {
                      NavState.currentPath = prevPath
                      done(redone, redone ? "2 files renamed via {name}/{ext} pattern, undo restored originals, redo re-applied" : "redo didn't re-apply")
                    })
                  })
                })
              })
            })
          })
        })

        sc.add("Bulk rename: pattern producing an empty name renames nothing (P2.7 regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var stamp = Date.now()
          var noExtName = "br-noext-" + stamp // no "." at all -> {ext} is guaranteed empty
          var noExtPath = sc.opsDir + "/" + noExtName
          Backend.FileOperations.copy(sc.note, noExtPath)
          sc._fileOp(done, function () {
            c.navController.navigateTo(sc.opsDir)
            sc._poll(function () { return NavState.currentPath === sc.opsDir && sc._has(NavState.visibleEntries, noExtName) }, function (listed) {
              if (!listed) { NavState.currentPath = prevPath; done(false, "fixture never appeared"); return }
              if (!sc._selectByNames([noExtName])) { NavState.currentPath = prevPath; done(false, "selection failed"); return }
              DialogsState.bulkRenamePattern = "{ext}"
              c.actionEngine.commitBulkRename()
              // The fix returns synchronously before touching the
              // filesystem or ConflictState -- no async signal to wait
              // on. A short settle timer (same technique as the P0-3
              // symlink test) gives a REGRESSION (the old code, which
              // would have started a real "mv -n -- x ''" via runAction)
              // time to show up if it somehow did.
              var settle = Qt.createQmlObject('import QtQuick; Timer { interval: 300; repeat: false }', sc)
              settle.triggered.connect(function () {
                var stillThere = sc._has(NavState.visibleEntries, noExtName)
                var neverBusy = !ActionState.actionBusy
                var noConflictOpened = !ConflictState.bulkRenameConflictOpen
                NavState.currentPath = prevPath
                var ok = stillThere && neverBusy && noConflictOpened
                done(ok, ok ? "empty-name pattern renamed nothing, no filesystem call was made"
                            : "stillThere=" + stillThere + " neverBusy=" + neverBusy + " noConflictOpened=" + noConflictOpened)
              })
              settle.start()
            })
          })
        })

        sc.add("Bulk rename: internal-duplicate collision opens the conflict dialog instead of renaming (P2.7)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var stamp = Date.now()
          var aName = "br-coll-a-" + stamp + ".txt"
          var bName = "br-coll-b-" + stamp + ".txt"
          var aPath = sc.opsDir + "/" + aName
          var bPath = sc.opsDir + "/" + bName
          Backend.FileOperations.copy(sc.note, aPath)
          sc._fileOp(done, function () {
            Backend.FileOperations.copy(sc.note, bPath)
            sc._fileOp(done, function () {
              c.navController.navigateTo(sc.opsDir)
              sc._poll(function () {
                return NavState.currentPath === sc.opsDir && sc._has(NavState.visibleEntries, aName) && sc._has(NavState.visibleEntries, bName)
              }, function (listed) {
                if (!listed) { NavState.currentPath = prevPath; done(false, "fixtures never appeared"); return }
                if (!sc._selectByNames([aName, bName])) { NavState.currentPath = prevPath; done(false, "selection failed"); return }
                // Both selected files map to the exact same target name --
                // an internal duplicate, not a filesystem collision.
                DialogsState.bulkRenamePattern = "same-" + stamp + "{ext}"
                c.actionEngine.commitBulkRename()
                var opened = ConflictState.bulkRenameConflictOpen
                var stillOriginal = sc._has(NavState.visibleEntries, aName) && sc._has(NavState.visibleEntries, bName)
                c.actionEngine.cancelPendingBulkRename()
                var closedAfterCancel = !ConflictState.bulkRenameConflictOpen
                NavState.currentPath = prevPath
                var ok = opened && stillOriginal && closedAfterCancel
                done(ok, ok ? "internal-duplicate collision opened the conflict dialog, nothing renamed, cancel closed it cleanly"
                            : "opened=" + opened + " stillOriginal=" + stillOriginal + " closedAfterCancel=" + closedAfterCancel)
              })
            })
          })
        })

        // {n:W} zero-padding (V1.1) -- added to Utils.bulkRenameNames(),
        // the shared pure function commitBulkRename() and
        // BulkRenamePanel.qml's live preview both call, so this also
        // covers the preview never being able to diverge from the real
        // result (they're literally the same function call).
        sc.add("Bulk rename: {n:W} zero-pads the sequence number (V1.1)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var stamp = Date.now()
          var names = ["brp-a-" + stamp + ".txt", "brp-b-" + stamp + ".txt", "brp-c-" + stamp + ".txt"]
          var expected = ["item-001.txt", "item-002.txt", "item-003.txt"].map(function (n) { return stamp + "-" + n })
          sc._seqOps(names.map(function (n) {
            return function () { Backend.FileOperations.copy(sc.note, sc.opsDir + "/" + n) }
          }), done, function () {
            c.navController.navigateTo(sc.opsDir)
            sc._poll(function () {
              return NavState.currentPath === sc.opsDir && names.every(function (n) { return sc._has(NavState.visibleEntries, n) })
            }, function (listed) {
              if (!listed) { NavState.currentPath = prevPath; done(false, "fixtures never appeared"); return }
              if (!sc._selectByNames(names)) { NavState.currentPath = prevPath; done(false, "selection failed"); return }
              DialogsState.bulkRenamePattern = stamp + "-item-{n:3}{ext}"
              c.actionEngine.commitBulkRename()
              sc._poll(function () {
                return expected.every(function (n) { return sc._has(NavState.visibleEntries, n) })
              }, function (renamed) {
                NavState.currentPath = prevPath
                done(renamed, renamed ? "3 files zero-padded to item-001/002/003 via {n:3}" : "padded names never appeared")
              })
            })
          })
        })

        // Regex find/replace (V1.1): applied to the base name BEFORE
        // {name}/{ext}/{n} substitution, via DialogsState.bulkRenameFind/
        // bulkRenameReplace -- the exact fields dialogs/BulkRenamePanel.qml's
        // Find/Replace TextFields write to before calling commitBulkRename().
        sc.add("Bulk rename: find/replace regex substitutes before {name}/{ext} (V1.1)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var stamp = Date.now()
          var name = "brf-" + stamp + "-IMG_42.txt"
          var expected = "brf-" + stamp + "-Photo_42.txt"
          Backend.FileOperations.copy(sc.note, sc.opsDir + "/" + name)
          sc._fileOp(done, function () {
            c.navController.navigateTo(sc.opsDir)
            sc._poll(function () { return NavState.currentPath === sc.opsDir && sc._has(NavState.visibleEntries, name) }, function (listed) {
              if (!listed) { NavState.currentPath = prevPath; done(false, "fixture never appeared"); return }
              if (!sc._selectByNames([name])) { NavState.currentPath = prevPath; done(false, "selection failed"); return }
              DialogsState.bulkRenamePattern = "{name}{ext}"
              DialogsState.bulkRenameFind = "IMG_(\\d+)"
              DialogsState.bulkRenameReplace = "Photo_$1"
              c.actionEngine.commitBulkRename()
              sc._poll(function () { return sc._has(NavState.visibleEntries, expected) }, function (renamed) {
                NavState.currentPath = prevPath
                DialogsState.bulkRenameFind = ""
                DialogsState.bulkRenameReplace = ""
                done(renamed, renamed ? "IMG_42 -> Photo_42 via regex find/replace with a $1 backreference" : "regex substitution never applied")
              })
            })
          })
        })

        sc.add("Bulk rename: invalid regex in find/replace is skipped, not applied (V1.1 regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var stamp = Date.now()
          var name = "brf-bad-" + stamp + ".txt"
          Backend.FileOperations.copy(sc.note, sc.opsDir + "/" + name)
          sc._fileOp(done, function () {
            c.navController.navigateTo(sc.opsDir)
            sc._poll(function () { return NavState.currentPath === sc.opsDir && sc._has(NavState.visibleEntries, name) }, function (listed) {
              if (!listed) { NavState.currentPath = prevPath; done(false, "fixture never appeared"); return }
              if (!sc._selectByNames([name])) { NavState.currentPath = prevPath; done(false, "selection failed"); return }
              DialogsState.bulkRenamePattern = "{name}{ext}"
              // Unbalanced paren -- `new RegExp()` throws on this. Must not
              // crash commitBulkRename(); the pattern should apply as if
              // find/replace were empty (here: a no-op, {name}{ext} = itself).
              DialogsState.bulkRenameFind = "("
              DialogsState.bulkRenameReplace = "x"
              c.actionEngine.commitBulkRename()
              var settle = Qt.createQmlObject('import QtQuick; Timer { interval: 300; repeat: false }', sc)
              settle.triggered.connect(function () {
                var stillThere = sc._has(NavState.visibleEntries, name)
                var neverBusy = !ActionState.actionBusy
                NavState.currentPath = prevPath
                DialogsState.bulkRenameFind = ""
                DialogsState.bulkRenameReplace = ""
                var ok = stillThere && neverBusy
                done(ok, ok ? "invalid regex didn't crash and didn't rename (pattern applied as a no-op)"
                            : "stillThere=" + stillThere + " neverBusy=" + neverBusy)
              })
              settle.start()
            })
          })
        })

        // ======================= Drag & drop (V1.1) =======================
        // startDropInto()/runDrop() had zero dedicated coverage despite
        // going through the exact same native copy/move + undo/redo +
        // transfer-queue machinery drop/paste already share -- these three
        // drive startDropInto() directly (the real function every
        // DropArea's handleFilesDropped() calls once the DragEvent itself
        // is resolved; the DragEvent wrapper isn't constructible headlessly,
        // same reasoning as commitBulkRename()/commitChmod() being driven
        // directly instead of their dialogs' buttons).
        sc.add("Drag&drop: startDropInto() moves a file into another folder, with undo/redo (V1.1, previously untested)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var stamp = Date.now()
          var destDir = sc.opsDir + "/dnd-dest-" + stamp
          var srcName = "dnd-src-" + stamp + ".txt"
          var srcPath = sc.opsDir + "/" + srcName
          sc._seqOps([
            function () { Backend.FileOperations.mkdir(destDir) },
            function () { Backend.FileOperations.copy(sc.note, srcPath) }
          ], done, function () {
            sc._fileOp(done, function () {
              sc._listOnce(destDir, function (e) {
                var movedIn = sc._has(e, srcName)
                sc._listOnce(sc.opsDir, function (e2) {
                  var goneFromSrc = !sc._has(e2, srcName)
                  if (!movedIn || !goneFromSrc) { done(false, "drop-move didn't apply: movedIn=" + movedIn + " goneFromSrc=" + goneFromSrc); return }
                  c.actionEngine.undoLast()
                  sc._fileOp(done, function () {
                    sc._listOnce(sc.opsDir, function (e3) {
                      var undone = sc._has(e3, srcName)
                      if (!undone) { done(false, "undo didn't restore to the source folder"); return }
                      c.actionEngine.redoLast()
                      sc._fileOp(done, function () {
                        sc._listOnce(destDir, function (e4) {
                          var redone = sc._has(e4, srcName)
                          done(redone, redone ? "drop-move applied, undo restored to source, redo re-applied into dest" : "redo didn't re-apply")
                        })
                      })
                    })
                  })
                })
              })
            })
            c.actionEngine.startDropInto(destDir, [srcPath], true)
          })
        })

        sc.add("Drag&drop: dropping onto an existing name opens the conflict dialog, skip excludes only that item (V1.1, previously untested)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var stamp = Date.now()
          var destDir = sc.opsDir + "/dnd-coll-" + stamp
          var collideName = "dnd-collide-" + stamp + ".txt"
          var okName = "dnd-ok-" + stamp + ".txt"
          var collideSrcPath = sc.opsDir + "/" + collideName
          var collideDestPath = destDir + "/" + collideName
          var okSrcPath = sc.opsDir + "/" + okName
          sc._seqOps([
            function () { Backend.FileOperations.mkdir(destDir) },
            function () { Backend.FileOperations.copy(sc.note, collideSrcPath) },
            function () { Backend.FileOperations.copy(sc.note, okSrcPath) },
            function () { Backend.FileOperations.copy(sc.note, collideDestPath) }
          ], done, function () {
            c.actionEngine.startDropInto(destDir, [collideSrcPath, okSrcPath], false)
            var opened = ConflictState.dropConflictOpen
            var namesMatch = ConflictState.dropConflictNames.length === 1 && ConflictState.dropConflictNames[0] === collideName
            if (!opened || !namesMatch) {
              done(false, "conflict dialog didn't open correctly: opened=" + opened + " namesMatch=" + namesMatch)
              return
            }
            sc._fileOp(done, function () {
              sc._listOnce(destDir, function (e) {
                var okCopied = sc._has(e, okName)
                var collideUntouched = sc._has(e, collideName)
                var noLongerPending = !ConflictState.dropConflictOpen
                var pass = okCopied && collideUntouched && noLongerPending
                done(pass, pass ? "skip mode copied the non-conflicting item and left the conflicting one untouched"
                                 : "okCopied=" + okCopied + " collideUntouched=" + collideUntouched + " noLongerPending=" + noLongerPending)
              })
            })
            c.actionEngine.runDrop("skip")
          })
        })

        sc.add("Drag&drop: dropping a file onto its own containing folder is a no-op (V1.1, previously untested)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var stamp = Date.now()
          var name = "dnd-selfdrop-" + stamp + ".txt"
          var path = sc.opsDir + "/" + name
          Backend.FileOperations.copy(sc.note, path)
          sc._fileOp(done, function () {
            c.actionEngine.startDropInto(sc.opsDir, [path], false)
            var settle = Qt.createQmlObject('import QtQuick; Timer { interval: 300; repeat: false }', sc)
            settle.triggered.connect(function () {
              sc._listOnce(sc.opsDir, function (e) {
                var occurrences = e.filter(function (x) { return x.name === name }).length
                var neverBusy = !ActionState.actionBusy
                var ok = occurrences === 1 && neverBusy
                done(ok, ok ? "self-drop guard correctly no-opped, no duplicate/rename" : "occurrences=" + occurrences + " neverBusy=" + neverBusy)
              })
            })
            settle.start()
          })
        })

        // ======================= Chmod + undo (P2.7, 2026-08-17) =======================
        // The P2.6 audit found chmod's commit+undo path with zero
        // dedicated coverage beyond an ARG_MAX-scale test. Drives the
        // REAL production path: controllers.propertiesLoader.startChmod()
        // (the exact function the Properties/chmod UI calls, which reads
        // ACTUAL permissions via Backend.FileOperations.octalModes() and
        // populates ChmodState.chmodOriginalModes -- undo's source of
        // truth), then c.actionEngine.commitChmod() (the exact function
        // dialogs/ChmodPanel.qml's confirm button calls).
        sc.add("Chmod: commit changes permissions, undo restores the original mode (P2.7)", function (done) {
          var c = sc._content
          if (!c || !c.controllers || !c.controllers.propertiesLoader) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var stamp = Date.now()
          var name = "chmod-" + stamp + ".txt"
          var path = sc.opsDir + "/" + name
          Backend.FileOperations.copy(sc.note, path)
          sc._fileOp(done, function () {
            var before = Backend.FileOperations.octalModes([path])[0]
            if (!before) { done(false, "couldn't read the fixture's starting mode"); return }
            // Pick a target mode that's guaranteed different from
            // whatever umask gave the fixture (600 vs 400 covers both
            // common cases; if the fixture somehow already is 600, fall
            // back to 400).
            var target = before === "600" ? "400" : "600"
            NavState.currentPath = sc.opsDir
            c.controllers.propertiesLoader.startChmod([{ name: name, type: "file" }])
            if (ChmodState.chmodOriginalModes[name] !== before) {
              NavState.currentPath = prevPath
              done(false, "startChmod() read a different mode (" + ChmodState.chmodOriginalModes[name] + ") than expected (" + before + ")")
              return
            }
            c.actionEngine.commitChmod(target)
            sc._poll(function () { return Backend.FileOperations.octalModes([path])[0] === target }, function (changed) {
              if (!changed) { NavState.currentPath = prevPath; done(false, "chmod never applied (still " + Backend.FileOperations.octalModes([path])[0] + ")"); return }
              c.actionEngine.undoLast()
              sc._poll(function () { return Backend.FileOperations.octalModes([path])[0] === before }, function (restored) {
                NavState.currentPath = prevPath
                done(restored, restored
                  ? ("chmod " + before + " -> " + target + ", undo restored " + before)
                  : ("undo didn't restore the original mode (now " + Backend.FileOperations.octalModes([path])[0] + ", expected " + before + ")"))
              })
            })
          })
        })

        // ======================= Compress + extract (P2.7, 2026-08-17) =======================
        // The P2.6 audit found compress/extract with only narrow,
        // security-specific coverage (BUG-05's tar-dash-prefix test, the
        // P0-3 openFileInArchive symlink test) -- nothing exercising
        // ordinary successful compress/extract. Drives the real
        // c.actionEngine.compressSelected()/extractHere() (the exact
        // functions the context menu / command palette call), real zip,
        // real content comparison after the round-trip -- not just
        // "a file with this name exists."
        sc.add("Compress + extract round-trip: zip preserves content (P2.7)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var stamp = Date.now()
          var srcDir = sc.opsDir + "/cx-src-" + stamp
          var outDir = sc.opsDir + "/cx-out-" + stamp
          var fname = "payload.txt"
          var srcPath = srcDir + "/" + fname
          sc._seqOps([
            function () { Backend.FileOperations.mkdir(srcDir) },
            function () { Backend.FileOperations.mkdir(outDir) },
            function () { Backend.FileOperations.copy(sc.note, srcPath) }
          ], done, function () {
            c.navController.navigateTo(srcDir)
            sc._poll(function () { return NavState.currentPath === srcDir && sc._has(NavState.visibleEntries, fname) }, function (listed) {
              if (!listed) { NavState.currentPath = prevPath; done(false, "fixture never appeared"); return }
              if (!sc._selectByNames([fname])) { NavState.currentPath = prevPath; done(false, "selection failed"); return }
              c.actionEngine.compressSelected()
              var zipName = fname + ".zip"
              var zipPath = srcDir + "/" + zipName
              // Poll the REAL file on disk (Backend.FileOperations.totalSize,
              // a native stat) rather than NavState.visibleEntries: the
              // directory-listing model can transiently show stale/mid-
              // refresh content (this test's first version polled the
              // listing and read a 0-byte extracted file -- the listing's
              // "payload.txt" match was actually a stale echo of srcDir's
              // OWN same-named fixture, not outDir's real, not-yet-written
              // one; a native size check can't be fooled by that).
              sc._poll(function () { return Backend.FileOperations.totalSize([zipPath]) > 0 }, function (compressed) {
                if (!compressed) { NavState.currentPath = prevPath; done(false, "compress never produced " + zipName); return }
                var zipInOut = outDir + "/" + zipName
                sc._fileOp(done, function () {
                  c.navController.navigateTo(outDir)
                  sc._poll(function () { return Backend.FileOperations.totalSize([zipInOut]) > 0 }, function (copiedOut) {
                    if (!copiedOut) { NavState.currentPath = prevPath; done(false, "zip copy never appeared in outDir"); return }
                    c.actionEngine.extractHere({ name: zipName, type: "file" })
                    var extractedPath = outDir + "/" + fname
                    sc._poll(function () { return Backend.FileOperations.totalSize([extractedPath]) > 0 }, function (extracted) {
                      NavState.currentPath = prevPath
                      if (!extracted) { done(false, "extract never produced " + fname); return }
                      sc._sh(["bash", "-c", "cat -- " + sc._q(sc.note)], function (r1) {
                        sc._sh(["bash", "-c", "cat -- " + sc._q(extractedPath)], function (r2) {
                          var ok = r1.exitCode === 0 && r2.exitCode === 0 && r1.stdout === r2.stdout
                          done(ok, ok ? "compressed, copied, extracted -- content preserved byte for byte"
                                      : "content mismatch after round-trip (orig " + JSON.stringify(r1.stdout).slice(0, 40) + " vs extracted " + JSON.stringify(r2.stdout).slice(0, 40) + ")")
                        })
                      })
                    })
                  })
                })
                Backend.FileOperations.copy(zipPath, zipInOut)
              })
            })
          })
        })

        // Compress-to-other-formats (V1.1, headline #8): same round-trip
        // shape as the .zip test above, exactly parameterized by format/
        // ext, for the two new formats added to
        // ActionEngine.qml's compressSelected(format).
        function registerCompressRoundTrip(format, ext, label) {
          sc.add("Compress + extract round-trip: " + label + " preserves content (V1.1 regression)", function (done) {
            var c = sc._content
            if (!c) { done(false, "no composition root"); return }
            // Guard against a real race, caught empirically (2026-08-18,
            // this test flaked once at ~4s then passed at 64ms on
            // immediate retry): runActionWithProgress()'s busy guard
            // (actionProc.busy || nativeBusy || archiveProc.active,
            // ActionEngine.qml) can still be settling from the PREVIOUS
            // test's own compress/extract when this one starts back to
            // back -- if so it silently rejects (no return value checked
            // by extractHere()/compressSelected(), nothing retries), which
            // looks exactly like "extract never produced the file". Not a
            // real bug (reproduced the same compress/extract commands
            // directly via bash, works every time) -- a test-isolation gap
            // between two archive tests sharing the same archiveProc.
            sc._poll(function () { return !ActionState.actionBusy && !c.actionEngine.archiveBusy }, function () {
            var prevPath = NavState.currentPath
            var stamp = Date.now()
            var srcDir = sc.opsDir + "/cx-src-" + format.replace(".", "") + "-" + stamp
            var outDir = sc.opsDir + "/cx-out-" + format.replace(".", "") + "-" + stamp
            var fname = "payload.txt"
            var srcPath = srcDir + "/" + fname
            sc._seqOps([
              function () { Backend.FileOperations.mkdir(srcDir) },
              function () { Backend.FileOperations.mkdir(outDir) },
              function () { Backend.FileOperations.copy(sc.note, srcPath) }
            ], done, function () {
              c.navController.navigateTo(srcDir)
              sc._poll(function () { return NavState.currentPath === srcDir && sc._has(NavState.visibleEntries, fname) }, function (listed) {
                if (!listed) { NavState.currentPath = prevPath; done(false, "fixture never appeared"); return }
                if (!sc._selectByNames([fname])) { NavState.currentPath = prevPath; done(false, "selection failed"); return }
                c.actionEngine.compressSelected(format)
                var archName = fname + ext
                var archPath = srcDir + "/" + archName
                sc._poll(function () { return Backend.FileOperations.totalSize([archPath]) > 0 }, function (compressed) {
                  if (!compressed) { NavState.currentPath = prevPath; done(false, "compress never produced " + archName); return }
                  var archInOut = outDir + "/" + archName
                  sc._fileOp(done, function () {
                    c.navController.navigateTo(outDir)
                    sc._poll(function () { return Backend.FileOperations.totalSize([archInOut]) > 0 }, function (copiedOut) {
                      if (!copiedOut) { NavState.currentPath = prevPath; done(false, archName + " copy never appeared in outDir"); return }
                      // Real race, found via SelfCheckOut tracing (2026-08-18):
                      // the compress subprocess having already written the
                      // archive to disk (the "compressed" poll above) does
                      // NOT guarantee runActionWithProgress()'s own busy
                      // guard (archiveProc.active, checked directly) has
                      // cleared yet -- calling extractHere() too soon makes
                      // that guard silently reject the extract (no return
                      // value is checked by extractHere(), so nothing
                      // retries). A guessed fixed-duration settle (a 200ms
                      // Timer) used to bridge this instead of polling the
                      // real flag directly, and still flaked occasionally
                      // (wrong-sized guess) -- ActionEngine.archiveBusy
                      // (cleanup pass) exposes archiveProc.active itself, so
                      // this can poll the exact thing the guard checks
                      // instead of estimating how long it takes to clear.
                      sc._poll(function () { return !ActionState.actionBusy && !c.actionEngine.archiveBusy }, function () {
                        c.actionEngine.extractHere({ name: archName, type: "file" })
                        var extractedPath = outDir + "/" + fname
                        sc._poll(function () { return Backend.FileOperations.totalSize([extractedPath]) > 0 }, function (extracted) {
                          NavState.currentPath = prevPath
                          if (!extracted) { done(false, "extract never produced " + fname); return }
                          sc._sh(["bash", "-c", "cat -- " + sc._q(sc.note)], function (r1) {
                            sc._sh(["bash", "-c", "cat -- " + sc._q(extractedPath)], function (r2) {
                              var ok = r1.exitCode === 0 && r2.exitCode === 0 && r1.stdout === r2.stdout
                              done(ok, ok ? "compressed to " + ext + ", copied, extracted -- content preserved byte for byte"
                                          : "content mismatch after round-trip (orig " + JSON.stringify(r1.stdout).slice(0, 40) + " vs extracted " + JSON.stringify(r2.stdout).slice(0, 40) + ")")
                            })
                          })
                        })
                      })
                    })
                  })
                  Backend.FileOperations.copy(archPath, archInOut)
                })
              })
            })
            })
          })
        }
        registerCompressRoundTrip("tar.gz", ".tar.gz", ".tar.gz")
        registerCompressRoundTrip("7z", ".7z", ".7z")
  }
}

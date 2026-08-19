import QtQuick
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// Domain checks extracted from app/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Copy progress (byte-accurate, reaches total)", function (done) {
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
          function cleanup() { Backend.FileOperations.progress.disconnect(onProg); Backend.FileOperations.finished.disconnect(onFin); Backend.FileOperations.error.disconnect(onErr) }
          Backend.FileOperations.progress.connect(onProg)
          Backend.FileOperations.finished.connect(onFin)
          Backend.FileOperations.error.connect(onErr)
          Backend.FileOperations.copy(src, dst)
        })

        sc.add("Move cross-fs progress (best-effort)", function (done) {
          // A move that crosses disks (HOME -> /tmp) uses copyTree and emits
          // progress; if it's the same fs, it's an atomic rename (no progress). In
          // both cases it must finish fine. Cleans up /tmp at the end.
          var work = sc.opsDir + "/mvprog-src.bin"
          var xfsDst = "/tmp/omafiles-selfcheck-mvprog-" + Date.now() + ".bin"
          sc._seqOps([function () { Backend.FileOperations.copy(sc.dir + "/big.bin", work) }], done, function () {
            var count = 0, lastDone = -1, lastTotal = -1
            function onProg(op, path, d, t) { if (path !== work) return; count++; lastDone = d; lastTotal = t }
            function onFin(op, path) {
              if (path !== work) return
              cleanupSig()
              var progOk = count === 0 || (lastTotal > 0 && lastDone === lastTotal)
              // cleans up the destination in /tmp (waiting for its finished)
              function rmDone(o, p) { if (p !== xfsDst) return; Backend.FileOperations.finished.disconnect(rmDone); Backend.FileOperations.error.disconnect(rmDone); done(progOk, count > 0 ? "cross-fs progress " + count + " events" : "atomic rename (same fs)") }
              Backend.FileOperations.finished.connect(rmDone)
              Backend.FileOperations.error.connect(rmDone)
              Backend.FileOperations.remove(xfsDst, true)
            }
            function onErr(op, path, msg) { if (path !== work) return; cleanupSig(); done(false, "error: " + msg) }
            function cleanupSig() { Backend.FileOperations.progress.disconnect(onProg); Backend.FileOperations.finished.disconnect(onFin); Backend.FileOperations.error.disconnect(onErr) }
            Backend.FileOperations.progress.connect(onProg)
            Backend.FileOperations.finished.connect(onFin)
            Backend.FileOperations.error.connect(onErr)
            Backend.FileOperations.move(work, xfsDst)
          })
        })

        sc.add("Copy cancellation leaves no partial file", function (done) {
          // The backend (forceRemove) cleans up the partial copy on aborting.
          var src = sc.dir + "/big.bin"
          var dst = sc.opsDir + "/cancel-partial.bin"
          function onErr(op, path, msg) {
            if (path !== src) return
            cleanup()
            if (msg !== "cancelled") { done(false, "error: " + msg); return }
            var partial = Backend.FileOperations.existingPaths([dst])
            done(partial.length === 0, partial.length === 0 ? "no partial residue" : "partial copy left")
          }
          function onFin(op, path) { if (path !== src) return; cleanup(); done(false, "finished before cancelling") }
          function cleanup() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
          Backend.FileOperations.error.connect(onErr)
          Backend.FileOperations.finished.connect(onFin)
          Backend.FileOperations.copy(src, dst)
          Backend.FileOperations.cancel()
        })

        sc.add("Copy cancellation leaves no partial directory", function (done) {
          // Cancelling the copy of a tree (500 files) must not leave the destination
          // folder half-created: forceRemove deletes the partial tree.
          var src = sc.dir + "/bigdir"
          var dst = sc.opsDir + "/cancel-partial-dir"
          function onErr(op, path, msg) {
            if (path !== src) return
            cleanup()
            if (msg !== "cancelled") { done(false, "error: " + msg); return }
            var partial = Backend.FileOperations.existingPaths([dst])
            done(partial.length === 0, partial.length === 0 ? "partial tree cleaned up" : "partial folder left")
          }
          function onFin(op, path) { if (path !== src) return; cleanup(); done(false, "finished before cancelling") }
          function cleanup() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
          Backend.FileOperations.error.connect(onErr)
          Backend.FileOperations.finished.connect(onFin)
          Backend.FileOperations.copy(src, dst)
          Backend.FileOperations.cancel()
        })

        sc.add("Move cross-fs cancellation: source intact, no partial", function (done) {
          var work = sc.opsDir + "/mvcancel-src.bin"
          var xfsDst = "/tmp/omafiles-selfcheck-mvcancel-" + Date.now() + ".bin"
          sc._seqOps([function () { Backend.FileOperations.copy(sc.dir + "/big.bin", work) }], done, function () {
            function onErr(op, path, msg) {
              if (path !== work) return
              cleanup()
              if (msg !== "cancelled") { done(false, "error: " + msg); return }
              var srcOk = Backend.FileOperations.existingPaths([work]).length === 1
              var noPartial = Backend.FileOperations.existingPaths([xfsDst]).length === 0
              done(srcOk && noPartial, "cross-fs cancelled: src=" + srcOk + " no partial=" + noPartial)
            }
            function onFin(op, path) {
              if (path !== work) return
              cleanup()
              // atomic rename (same fs): the move completed -> cleans up /tmp.
              function rmDone(o, p) { if (p !== xfsDst) return; Backend.FileOperations.finished.disconnect(rmDone); Backend.FileOperations.error.disconnect(rmDone); done(true, "atomic rename (same fs), no partial possible") }
              Backend.FileOperations.finished.connect(rmDone)
              Backend.FileOperations.error.connect(rmDone)
              Backend.FileOperations.remove(xfsDst, true)
            }
            function cleanup() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
            Backend.FileOperations.error.connect(onErr)
            Backend.FileOperations.finished.connect(onFin)
            Backend.FileOperations.move(work, xfsDst)
            Backend.FileOperations.cancel()
          })
        })

        // V1.2 general-perf audit (docs/audits/V1_2_GENERAL_PERFORMANCE_REPORT.md):
        // FolderCountState.set() used to reassign `counts` WHOLE on every
        // single async result -- since QML tracks `counts` as one property
        // (not per-key), entering a folder with N visible subfolders fired
        // N reassignments, each invalidating EVERY visible row's
        // FileMeta.metaFor() subtitle binding, not just the one whose count
        // arrived. _flushTimer now coalesces a burst of set() calls into
        // ONE reassignment. Tested in ISOLATION -- calling set() directly
        // with synthetic paths, no real ListView/navigation/FolderCounter
        // involved -- deliberately: an earlier version of this test drove
        // it through a REAL navigation into a 60-subfolder directory (the
        // realistic path) and reliably crashed the whole selfcheck process
        // (real, reproducible SEGFAULT inside QV4::Object::insertMember,
        // confirmed via gdb). Root-caused as PRE-EXISTING and unrelated to
        // this fix -- reproduces identically with FolderCountState.qml
        // reverted to its pre-fix code, so it's some other latent issue in
        // real-ListView-plus-real-FolderCounter-under-heavy-concurrent-load
        // that no existing test happened to exercise before. Flagged
        // separately (see the report) rather than silently dropped; this
        // narrower test verifies the actual mechanism that changed without
        // going anywhere near whatever that latent issue is.
        sc.add("FolderCountState.set() coalesces a burst into one reassignment (V1.2 general-perf regression)", function (done) {
          // Snapshot + restore: FolderCountState is a singleton shared with
          // every other test: add exactly the synthetic keys used here, then
          // remove exactly them, leaving any real cached counts from other
          // tests (before and after this one) untouched.
          var savedCounts = Object.assign({}, FolderCountState.counts)
          var N = 30
          var base = "/selfcheck-synthetic-foldercount-"
          var reassigns = 0
          function onCountsChanged() { reassigns++ }
          FolderCountState.countsChanged.connect(onCountsChanged)

          for (var i = 0; i < N; i++) FolderCountState.set(base + i, i)

          // Immediately after the burst, nothing should have flushed yet
          // (proves set() defers rather than reassigning synchronously).
          var noneYet = FolderCountState.counts[base + "0"] === undefined && reassigns === 0

          sc._poll(function () {
            return FolderCountState.counts[base + (N - 1)] !== undefined
          }, function (ok) {
            FolderCountState.countsChanged.disconnect(onCountsChanged)
            var allPresent = true
            for (var j = 0; j < N; j++) {
              if (FolderCountState.counts[base + j] !== j) { allPresent = false; break }
            }
            // Cleanup: remove exactly the synthetic keys, restore the rest verbatim.
            FolderCountState.counts = savedCounts
            var pass = ok && noneYet && allPresent && reassigns > 0 && reassigns <= 3
            done(pass, "deferred=" + noneYet + " settled=" + ok + " allPresent=" + allPresent
              + " reassignments=" + reassigns + " (of " + N + " set() calls)")
          }, 60)
        })
  }
}

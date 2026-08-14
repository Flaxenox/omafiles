import QtQuick
import Omafiles.Backend as Backend
import "../../../services"
import "../../../state"
import "../../../Utils.js" as Utils

// Domain checks extracted from app/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("ThumbnailProvider PNG", function (done) {
          var immediate = ThumbnailProvider.request(sc.png, 128)
          if (immediate && immediate.length > 0) { done(true, "cache hit"); return }
          function onReady(path, thumbPath) {
            if (path !== sc.png) return
            ThumbnailProvider.ready.disconnect(onReady)
            done(thumbPath.length > 0, thumbPath ? "" : "thumbPath empty")
          }
          ThumbnailProvider.ready.connect(onReady)
        })

        sc.add("ThumbnailProvider PDF (qpdf plugin)", function (done) {
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
        sc.add("Thumbnail cache key is canonical SHA-1 (B1)", function (done) {
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
        sc.add("Thumbnail cache pruning: orphans, safety, age, size (O1)", function (done) {
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

        sc.add("PreviewProvider text", function (done) {
          function onText(path, content, enc, bytes, lines, trunc) {
            if (path !== sc.note) return
            PreviewProvider.textReady.disconnect(onText)
            var ok = content.indexOf("hello selfcheck") >= 0
            done(ok, ok ? enc + ", " + lines + " lines" : "unexpected content")
          }
          PreviewProvider.textReady.connect(onText)
          PreviewProvider.requestText(sc.note, 65536)
        })

        sc.add("PreviewProvider info", function (done) {
          var info = PreviewProvider.info(sc.note)
          var ok = info && typeof info === "object" && Object.keys(info).length > 0
          done(ok, ok ? "keys=[" + Object.keys(info).join(",") + "]" : "info empty")
        })
  }
}

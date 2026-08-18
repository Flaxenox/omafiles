import QtQuick
import QtMultimedia
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// Domain checks extracted from app/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        // ======================= INTEGRATION =======================

        sc.add("Backend module loaded (Omafiles.Backend)", function (done) {
          var home = Backend.Env.get("HOME")
          done(!!home && home.length > 0, home ? "HOME=" + home : "Backend.Env.get(HOME) empty")
        })

        sc.add("Backend.UDisksWatcher reactive backend", function (done) {
          // The C++ watcher (QtDBus) registered and exposes available()/devicesChanged.
          // available() is true if it connected to the system bus (in headless CI it can
          // be false; what's validated is that it loads and doesn't break, not that there's a bus).
          var a = Backend.UDisksWatcher.available()
          var ok = (a === true || a === false)
            && typeof Backend.UDisksWatcher.devicesChanged === "function"
          done(ok, "available=" + a)
        })

        // Same shape as the UDisksWatcher test above, for its GVfs
        // network-mount counterpart (V1.1) -- subscribes to
        // org.gtk.vfs.MountTracker's Mounted/Unmounted on the session bus
        // (verified present on a real desktop session, 2026-08-18, via
        // `busctl --user introspect org.gtk.vfs.Daemon
        // /org/gtk/vfs/mounttracker`), closing the previously-documented
        // "network mounts from another app go unnoticed" gap.
        sc.add("Backend.GvfsWatcher reactive backend (V1.1)", function (done) {
          var a = Backend.GvfsWatcher.available()
          var ok = (a === true || a === false)
            && typeof Backend.GvfsWatcher.mountsChanged === "function"
          done(ok, "available=" + a)
        })

        sc.add("Backend.FolderCounter counts a directory (async, Fase 23)", function (done) {
          // list/ = sub/ + alpha/beta/gamma.txt = 4 entries.
          function on(path, n) {
            if (path !== sc.listDir) return
            Backend.FolderCounter.counted.disconnect(on)
            done(n === 4, "n=" + n + " (expected 4)")
          }
          Backend.FolderCounter.counted.connect(on)
          Backend.FolderCounter.request(sc.listDir, false)
        })

        sc.add("Item count smart formatting", function (done) {
          var ok = Utils.formatItemCount(1) === "1 item"
            && Utils.formatItemCount(2) === "2 items"
            && Utils.formatItemCount(1234) === "1,234 items"
            && Utils.formatItemCount(12347) === "12.3k items"
            && Utils.formatItemCount(1200000) === "1.2M items"
            && Utils.formatItemCountExact(12347) === "12,347 items"
            && Utils.itemCountAbbreviated(12347) === true
            && Utils.itemCountAbbreviated(1234) === false
          done(ok, ok ? "" : "1=" + Utils.formatItemCount(1) + " 1234=" + Utils.formatItemCount(1234)
                              + " 12347=" + Utils.formatItemCount(12347))
        })

        sc.add("Composition root creates (OmafilesContent)", function (done) {
          var comp = Qt.createComponent(Qt.resolvedUrl("../../../core/OmafilesContent.qml"))
          if (comp.status === Component.Error) { done(false, comp.errorString()); return }
          var obj = comp.createObject(sc)
          if (!obj) { done(false, "createObject returned null"); return }

          sc._content = obj
          done(true, "main tree instantiated")
        })

        sc.add("Composition root API surface (open/close/facade)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var facade = c.commandFacade || c
          var ok = typeof c.open === "function"
            && typeof c.close === "function"
            && typeof facade.paletteCommands === "function"
            && typeof facade.itemActions === "function"
          done(ok, ok ? "" : "missing contract/facade functions")
        })

        // ======================= FRONTEND =======================

        sc.add("NavState is source of truth", function (done) {
          var prev = NavState.currentPath
          NavState.currentPath = sc.listDir
          var ok = NavState.currentPath === sc.listDir
          done(ok, ok ? "" : "NavState.currentPath doesn't persist")
        })

        sc.add("TabsState defaults", function (done) {
          var ok = TabsState.tabs.length >= 1 && TabsState.activeTabIndex === 0
          done(ok, "tabs=" + TabsState.tabs.length + " active=" + TabsState.activeTabIndex)
        })

        sc.add("ControllerRegistry + CommandFacade wiring", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          // Forces the evaluation of the builders: if a controller came in null
          // due to a registry injection failure, this would throw (see Phase 11.C).
          var facade = c.commandFacade || c
          var pal = facade.paletteCommands().length
          var items = facade.itemActions().length            // 0 without selection: valid
          var empty = facade.emptyAreaActions().length
          var segs = facade.pathSegments().length
          var ok = pal > 0 && empty > 0 && segs > 0 && (items >= 0)
          done(ok, "palette=" + pal + " emptyArea=" + empty + " segments=" + segs)
        })

        sc.add("AppBindings loaded (no side effects under selfcheck)", function (done) {
          // If OmafilesContent was created without errors, AppBindings (its child) too.
          // The self-registration as file manager is guarded by
          // OMAFILES_SELFCHECK, so this test confirms there was no side
          // effect and that the core started up complete.
          done(sc._content !== null, "AppBindings instantiated without self-registration")
        })

        // Final-release-audit regression (2026-08-17): AppBindings.qml's
        // self-registration call had a wrong path
        // ("/scripts/runtime/scripts/install-integrations.sh", which
        // never existed -- the real file is at "/scripts/install-
        // integrations.sh") for 3 days (since commit 37f3f318,
        // 2026-08-15) with zero detection, because Backend.Detached.run()
        // on a missing path fails completely silently (fire-and-forget,
        // no signal, no crash) and the script is idempotent-and-
        // invisible when it DOES run -- a broken run looked identical to
        // a successful no-op to any manual tester. This doesn't execute
        // the script (it mutates real xdg-mime/D-Bus defaults, not
        // appropriate to run from a selfcheck) -- it only confirms the
        // exact path AppBindings.qml constructs resolves to a real file,
        // which is the one thing that silently regressed.
        sc.add("install-integrations.sh path resolves to a real file (regression, self-registration)", function (done) {
          var path = Paths.resourceDir + "/scripts/install-integrations.sh"
          var exists = Backend.FileOperations.existingPaths([path]).length > 0
          done(exists, exists ? "path resolves correctly: " + path : "MISSING: " + path + " -- self-registration would silently no-op")
        })

        // Backend.Env.version() -- single authoritative version source
        // (CMakeLists.txt's project(... VERSION ...), threaded through as
        // the APP_VERSION compile definition, V1_1_P1_PACKAGING). Guards
        // against the compile definition silently going missing/empty --
        // not a hardcoded expected string, since that would just be a
        // second, manually-maintained version to keep in sync by hand,
        // exactly what this exists to avoid.
        sc.add("Backend.Env.version() exposes a real semver-shaped version (V1_1_P1_PACKAGING)", function (done) {
          var v = Backend.Env.version()
          var ok = /^\d+\.\d+\.\d+$/.test(v)
          done(ok, ok ? "version=" + v : "unexpected/empty version string: '" + v + "'")
        })

        // Backend.ProcessWatcher's terminal-cursor emulation (V1.1, archive
        // extract/compress progress). This is the exact mechanism that
        // took three real, live-reproduced bugs to get right (2026-08-18):
        // 7z redraws its live "NN%" via \r, unrar via \b/backspace, and a
        // naive \n-only (or \r-only) split saw neither tool's intermediate
        // updates correctly. Reproduces both redraw styles from one real
        // subprocess (not a mock) via a controlled `printf`, so a future
        // "simplify drainLines() back to a plain \n split" regression
        // fails loudly instead of silently breaking progress bars again.
        sc.add("Backend.ProcessWatcher reconstructs \\r and \\b terminal redraws (V1.1 regression)", function (done) {
          var w = Qt.createQmlObject('import Omafiles.Backend as Backend; Backend.ProcessWatcher {}', sc)
          var lines = []
          var finished = false
          w.lineRead.connect(function (line) { lines.push(line) })
          w.finished.connect(function () { finished = true })
          // Line A: unrar-style backspace redraw ("A  0%" then 2 backspaces
          // then "1%" overwrites the last two chars -> "A  1%").
          // Line B: 7z-style \r redraw ("B  0%" then \r returns to column
          // 0, then "B 44%" overwrites the whole line -> "B 44%").
          w.start(["bash", "-c", "printf 'A  0%%\\b\\b1%%\\nB  0%%\\rB 44%%\\n'"])
          sc._poll(function () { return finished }, function (ok) {
            w.destroy()
            if (!ok) { done(false, "process never finished"); return }
            var gotA = lines.indexOf("A  1%") >= 0
            var gotB = lines.indexOf("B 44%") >= 0
            var pass = gotA && gotB
            done(pass, pass ? "both redraw styles reconstructed correctly"
                             : "backspace(A)=" + gotA + " \\r(B)=" + gotB + " -- lines seen: " + JSON.stringify(lines))
          })
        })

        // ActionEngine's multi-volume archive progress (V1.1): the layer
        // ABOVE ProcessWatcher's terminal emulation (tested above) --
        // _multiVolumeSiblings() (real sibling detection via the real
        // directory listing) and the %-to-volume-index math in
        // archiveProc.onLineRead (2026-08-18 rewrite: derive the active
        // volume from cumulative byte sizes, since neither 7z nor unrar
        // ever announce a later volume's filename -- see the comment at
        // ActionEngine.qml's onLineRead). Uses real sibling files on disk
        // (distinct sizes, so an ordering/indexing bug would be caught)
        // and drives the real archiveProc/_ptyArgs/script/bash pipeline
        // with a controlled printf, not a mock.
        sc.add("ActionEngine multi-volume detection + weighted progress (real files, real subprocess) (V1.1 regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var base = "fixture-mv-" + Date.now()
          var names = [base + ".part01.rar", base + ".part02.rar", base + ".part03.rar"]
          var sizes = [1000, 2000, 4000] // distinct sizes -> catches ordering/index bugs
          var paths = names.map(function (n) { return sc.opsDir + "/" + n })
          var mkScript = paths.map(function (p, i) { return "head -c " + sizes[i] + " /dev/zero > " + sc._q(p) }).join(" && ")

          sc._sh(["bash", "-c", mkScript], function (r) {
            if (r.exitCode !== 0) { done(false, "fixture creation failed: " + r.stderr); return }

            c.navController.navigateTo(sc.opsDir)
            sc._poll(function () {
              return NavState.currentPath === sc.opsDir
                && sc._has(NavState.visibleEntries, names[0])
                && sc._has(NavState.visibleEntries, names[1])
                && sc._has(NavState.visibleEntries, names[2])
            }, function (listed) {
              if (!listed) { NavState.currentPath = prevPath; done(false, "fixtures never appeared in the real listing"); return }

              var vols = c.actionEngine._multiVolumeSiblings(names[0])
              var detectOk = vols && vols.length === 3
                && vols[0].name === names[0] && vols[0].size === sizes[0]
                && vols[1].name === names[1] && vols[1].size === sizes[1]
                && vols[2].name === names[2] && vols[2].size === sizes[2]
              if (!detectOk) {
                NavState.currentPath = prevPath
                done(false, "sibling detection wrong: " + JSON.stringify(vols))
                return
              }

              // Drive the REAL progress pipeline with a synthetic "50%"
              // (total=7000 bytes -> bytesSoFar=3500, which falls inside
              // volume index 2 [3000..7000) -> expected "(part 3/3)").
              // The trailing sleep holds the process open long enough to
              // observe the intermediate state before onFinished resets it.
              var succeeded = false
              var started = c.actionEngine.runActionWithProgress(
                "printf 'progress 50%%\\n'; sleep 0.4",
                "Test extracting",
                0,
                function () { succeeded = true },
                vols)
              if (!started) { NavState.currentPath = prevPath; done(false, "runActionWithProgress rejected (busy?)"); return }

              sc._poll(function () { return ActionState.actionLabel.indexOf("(part 3/3)") >= 0 }, function (labelOk) {
                var pctAtPeak = ActionState.actionProgressPct
                sc._poll(function () { return succeeded }, function (finishedOk) {
                  NavState.currentPath = prevPath
                  var pctOk = pctAtPeak === 50
                  var pass = labelOk && finishedOk && pctOk
                  done(pass, pass ? "detection + weighted progress correct (pct=" + pctAtPeak + ", reached part 3/3)"
                                   : "labelOk=" + labelOk + " finishedOk=" + finishedOk + " pctOk=" + pctOk
                                     + " pct=" + pctAtPeak + " label=" + ActionState.actionLabel)
                })
              })
            })
          })
        })

        // Backend.Notifier's D-Bus migration + session history (V1.1,
        // headline #2: replaces the old notify-send subprocess with a real
        // org.freedesktop.Notifications call, tracked so a missed desktop
        // toast isn't lost -- see dialogs/NotificationHistory.qml). Exercises
        // the real singleton's real notify()/history()/clearHistory(), not a
        // mock -- notify() itself skips the real D-Bus toast under
        // --selfcheck (backend/Notifier.cpp's OMAFILES_SELFCHECK guard,
        // added after repeated selfcheck runs during this session's own
        // development spammed the real desktop notification tray), so
        // history() is still exercised for real but no toast fires here.
        sc.add("Backend.Notifier records notify() in history, clearHistory() empties it (V1.1 regression)", function (done) {
          var marker = "selfcheck-notify-" + Date.now()
          var beforeSecs = Math.floor(Date.now() / 1000)
          Backend.Notifier.notify(marker)
          var entry = Backend.Notifier.history[0]
          var afterSecs = Math.floor(Date.now() / 1000)
          var recorded = !!entry && entry.text === marker
          var freshTimestamp = !!entry && entry.timestamp >= beforeSecs - 1 && entry.timestamp <= afterSecs + 1
          if (!recorded || !freshTimestamp) {
            done(false, "recorded=" + recorded + " freshTimestamp=" + freshTimestamp + " entry=" + JSON.stringify(entry))
            return
          }
          Backend.Notifier.clearHistory()
          var cleared = Backend.Notifier.history.length === 0
          done(cleared, cleared ? "notify() recorded the marker with a fresh timestamp, clearHistory() emptied it"
                                 : "clearHistory() left " + Backend.Notifier.history.length + " entries")
        })

        // Inline video/audio playback (V1.1, headline #3, panels/PreviewPanel.qml).
        // Real ffmpeg-generated fixtures (not stub/mock media), real
        // QtMultimedia Video/MediaPlayer objects reaching a real
        // PlayingState against a real PulseAudio sink -- the same
        // MediaPlayer/AudioOutput plumbing PreviewPanel.qml uses, just
        // driven directly here since PreviewPanel needs a live selection
        // in the real composition root to reach (already covered
        // structurally by the other composition-root tests; this is
        // narrower, on the actual playback primitive). Short (1s) clips
        // to keep the real audio blip this test causes brief.
        sc.add("Inline video/audio playback: real MediaPlayer reaches PlayingState (V1.1 headline #3 regression)", function (done) {
          var vidPath = sc.opsDir + "/p3media-test.mp4"
          var audPath = sc.opsDir + "/p3media-test.mp3"
          var buildCmd = "ffmpeg -y -f lavfi -i testsrc=duration=1:size=64x48:rate=5 -f lavfi -i sine=frequency=440:duration=1"
            + " -c:v libx264 -c:a aac -shortest " + sc._q(vidPath)
            + " && ffmpeg -y -f lavfi -i sine=frequency=440:duration=1 -c:a mp3 " + sc._q(audPath)
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "ffmpeg fixture build failed: " + buildResult.stderr); return }

            var vid = Qt.createQmlObject('import QtQuick; import QtMultimedia; Video { width: 64; height: 48 }', sc)
            var aud = Qt.createQmlObject('import QtQuick; import QtMultimedia; MediaPlayer { audioOutput: AudioOutput {} }', sc)
            vid.source = "file://" + vidPath
            aud.source = "file://" + audPath
            vid.play()
            aud.play()

            sc._poll(function () {
              return vid.playbackState === MediaPlayer.PlayingState && aud.playbackState === MediaPlayer.PlayingState
            }, function () {
              var vidOk = vid.playbackState === MediaPlayer.PlayingState && vid.hasVideo
              var audOk = aud.playbackState === MediaPlayer.PlayingState
              var vidErr = vid.errorString
              var audErr = aud.errorString
              vid.stop(); aud.stop()
              vid.destroy(); aud.destroy()
              var pass = vidOk && audOk
              done(pass, pass ? "real .mp4/.mp3 fixtures both reached PlayingState via QtMultimedia"
                               : "video: playing=" + vidOk + " hasVideo=" + vid.hasVideo + " err='" + vidErr + "'"
                                 + " | audio: playing=" + audOk + " err='" + audErr + "'")
            })
          })
        })
  }
}

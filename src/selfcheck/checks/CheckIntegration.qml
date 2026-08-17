import QtQuick
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// Domain checks extracted from app/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Conflict detection sees a broken symlink (BUG-01)", function (done) {
          var link = sc.opsDir + "/bug01-broken-" + Date.now()
          sc._sh(["ln", "-s", "/omafiles-no-such-target-xyz", link], function (r) {
            if (r.exitCode !== 0) { done(false, "couldn't create the broken symlink: " + r.stderr); return }
            var hit = Backend.FileOperations.existingPaths([link])
            done(hit.length === 1 && hit[0] === link,
                 hit.length === 1 ? "broken symlink detected as a conflict"
                                  : "existingPaths did NOT detect the broken symlink (n=" + hit.length + ")")
          })
        })

        // ======================= BUG-02 (Hardening-1) =======================
        // Smoke tests of the .sh scripts that are still part of the
        // UI's behavior. Goal: that a regression like the one in
        // empty-trash.sh (which passed 70/70 green) makes the harness fail.

        // ISOLATED empty-trash.sh: HOME points to a fake home inside the selfcheck's
        // tmp and a fake findmnt (via PATH) prevents real mounts from being scanned
        // -> it NEVER touches the user's real trash. It prepares a home
        // trash with an item and confirms that the script empties it. A
        // regression that doesn't discover the roots (like the trash-roots.sh one) would leave
        // the item undeleted and would make this fail.
        sc.add("Backend.FileOperations emptyTrash empties trash roots (BUG-02)", function (done) {
          function onFinished(op, path) {
            if (op !== "emptyTrash") return
            Backend.FileOperations.finished.disconnect(onFinished)
            var info = Backend.FileOperations.trashInfo()
            var ok = (info.length === 0)
            done(ok, ok ? "trash emptied cleanly: remaining=" + info.length : "items remained: " + info.length)
          }
          Backend.FileOperations.finished.connect(onFinished)
          Backend.FileOperations.emptyTrash()
        })

        // list-archive.sh over a deterministic .tar built from listDir
        // (sub/ + alpha/beta/gamma.txt). Confirms that it lists the top-level
        // elements in the NUL-delimited contract (name\0isdir\0...).
        sc.add("list-archive.sh lists a tar fixture (BUG-02)", function (done) {
          var tarPath = sc.opsDir + "/la-fixture.tar"
          var mk = "tar -cf " + sc._q(tarPath) + " -C " + sc._q(sc.listDir) + " sub alpha.txt beta.txt gamma.txt"
          sc._sh(["bash", "-c", mk], function (r0) {
            if (r0.exitCode !== 0) { done(false, "tar setup failed: " + r0.stderr); return }
            sc._sh(["bash", sc.resourceRoot + "/scripts/runtime/list-archive.sh", tarPath, ""], function (r) {
              var toks = String(r.stdout).split("\0")
              var names = []
              for (var i = 0; i < toks.length; i += 2) if (toks[i]) names.push(toks[i])
              var ok = r.exitCode === 0 && names.indexOf("sub") >= 0 && names.indexOf("alpha.txt") >= 0
              done(ok, ok ? "listed " + names.length + " top-level entries"
                          : "output=[" + names.join(",") + "] exit=" + r.exitCode)
            })
          })
        })

        // mount-iso.sh: can't mount in headless. It exercises the FAILURE
        // PATH: given a nonexistent path the script must not print a fake "Mounted…"
        // nor hang -> it exits != 0 and with no stdout. Verifies that it's invoked and that
        // its guard (set -e + loopdev check) works.
        sc.add("mount-iso.sh fails safely on a bad path (BUG-02)", function (done) {
          sc._sh(["bash", sc.resourceRoot + "/scripts/runtime/mount-iso.sh", sc.dir + "/no-such-file.iso"], function (r) {
            var ok = r.exitCode !== 0 && String(r.stdout).trim() === ""
            done(ok, "exit=" + r.exitCode + " stdout='" + String(r.stdout).trim() + "'")
          })
        })

        // MimeResolver: getting apps for a .txt file should return at least one app
        sc.add("MimeResolver.getAppsForFile returns valid list (BUG-02)", function (done) {
          var apps = Backend.MimeResolver.getAppsForFile(sc.note)
          if (!apps || apps.length === 0) {
            done(false, "No apps returned for text file")
            return
          }
          if (apps[0].id === undefined) {
            done(false, "App must have an ID")
            return
          }
          if (apps[0].name === undefined) {
            done(false, "App must have a Name")
            return
          }
          done(true, "Returned " + apps.length + " apps")
        })

        // ======================= BUG-03 (Hardening-2) =======================

        // Properties/chmod built `du -shc -- <all>` and `stat -c%a -- <all>`
        // in a single bash line -> with a huge selection it blew the length
        // limit (ARG_MAX / 128 KiB per argument) and the dialog was left without
        // size/permissions. Now they use Backend.FileOperations.totalSize/octalModes (native,
        // no command line). The test builds a list that DOES overflow that
        // line: the native path handles it; the old shell fails. It fails with the
        // previous code (octalModes didn't exist -> TypeError).
        sc.add("Properties/chmod handle a huge selection without ARG_MAX (BUG-03)", function (done) {
          // Two fixtures that exist (to assert correct sum/mode) + padding of
          // long nonexistent paths until the `stat/du -- <all>` line that
          // the old code used would overflow the per-argument limit (128 KiB).
          var reals = [sc.note, sc.png]
          var expected = Backend.FileOperations.totalSize(reals)
          var pad = new Array(160).join("x")
          var big = reals.slice()
          while (big.length < 2000) big.push(sc.opsDir + "/" + pad + big.length)
          // NATIVE: doesn't build a command line -> handles the huge list.
          var total = Backend.FileOperations.totalSize(big)      // sums only the 2 real ones
          var modes = Backend.FileOperations.octalModes(big)     // aligned with big, "" if missing
          var nativeOk = total === expected
            && modes.length === big.length && modes[0].length > 0 && modes[2] === ""
          if (!nativeOk) { done(false, "native: total=" + total + " exp=" + expected
            + " len=" + modes.length + " m0='" + modes[0] + "' m2='" + modes[2] + "'"); return }
          // OLD: the SAME `stat -c%a -- <all>` form that the old code used
          // -> the -c arg overflows the limit and exec fails (exit != 0).
          var oldCmd = "stat -c%a -- " + big.map(function (p) { return sc._q(p) }).join(" ")
          sc._sh(["bash", "-c", oldCmd], function (r) {
            done(r.exitCode !== 0,
                 "native OK (" + big.length + " paths); old shell line failed (exit=" + r.exitCode + ")")
          })
        })

        // ======================= BUG-05 (Hardening-2) =======================

        // ArchiveActions opened an archive member with `tar xf A -O <member>`
        // without "--": a member starting with "-" (e.g. "-foo") was taken by tar
        // as options and failed. The corrected pattern is `tar xf A -O -- <member>`.
        // A .tar with a member "-foo" is created and it's checked that the NEW form
        // dumps it and the OLD one fails.
        sc.add("tar extracts a member whose name starts with '-' (BUG-05)", function (done) {
          var d = sc.opsDir + "/bug05"
          var arch = d + "/a.tar"
          var setup = "mkdir -p " + sc._q(d) + " && cd " + sc._q(d)
            + " && printf 'contenido05' > ./-foo && tar cf " + sc._q(arch) + " -- -foo"
          sc._sh(["bash", "-c", setup], function (r0) {
            if (r0.exitCode !== 0) { done(false, "setup failed: " + r0.stderr); return }
            sc._sh(["bash", "-c", "tar xf " + sc._q(arch) + " -O -- " + sc._q("-foo")], function (rNew) {
              sc._sh(["bash", "-c", "tar xf " + sc._q(arch) + " -O " + sc._q("-foo") + " 2>/dev/null"], function (rOld) {
                var ok = rNew.exitCode === 0 && String(rNew.stdout) === "contenido05" && rOld.exitCode !== 0
                done(ok, "new: exit=" + rNew.exitCode + " out='" + String(rNew.stdout)
                  + "' | old exit=" + rOld.exitCode)
              })
            })
          })
        })
        // ======================= BUG-06 (Phase 43 Regression) =======================
        sc.add("Terminal resolver error path (BUG-06)", function (done) {
          var signaled = false
          var onErr = function (msg) {
            if (msg === "No supported terminal emulator found.") signaled = true
          }
          Backend.TerminalResolver.error.connect(onErr)
          var oldPath = Backend.Env.get("PATH")
          var oldTerm = Backend.Env.get("TERMINAL")
          Backend.Env.set("PATH", "/dev/null/fake")
          Backend.Env.set("TERMINAL", "omafiles-fake-terminal")
          Backend.TerminalResolver.launchTerminal("/tmp")
          Backend.Env.set("PATH", oldPath)
          Backend.Env.set("TERMINAL", oldTerm)
          Backend.TerminalResolver.error.disconnect(onErr)
          done(signaled, signaled ? "error signal emitted" : "error signal NOT emitted")
        })

        sc.add("Relative path quoting test (BUG-06)", function (done) {
          var lastCopied = ""
          var onCopied = function (text) { lastCopied = text }
          Backend.TerminalResolver.copied.connect(onCopied)
          Backend.TerminalResolver.copyPathsRelative(["/tmp/a b.txt", "/tmp/c'd.txt"], "/tmp")
          Backend.TerminalResolver.copied.disconnect(onCopied)
          var ok = (lastCopied === "'a b.txt' 'c'\\''d.txt'")
          done(ok, ok ? "paths quoted properly" : "got: " + lastCopied)
        })

        sc.add("Keyboard shortcut integration test (BUG-06)", function (done) {
          var kbdComp = Qt.createComponent("../../../logic/KeyboardShortcuts.qml")
          if (kbdComp.status !== Component.Ready) { done(false, "kbd comp not ready: " + kbdComp.errorString()); return }
          var called = {}
          var stubEngine = {
            startRename: function() { called.F2 = true },
            requestDelete: function() { called.Del = true },
            copySelected: function() { called.CtrlC = true },
            cutSelected: function() { called.CtrlX = true },
            paste: function() { called.CtrlV = true }
          }
          var kbd = kbdComp.createObject(sc, {
            "hostControllers": { "actionEngine": stubEngine, "navController": {} },
            "hostRoot": {}
          })
          var ev = function(k, mod) { return { "key": k, "modifiers": mod || Qt.NoModifier, "accepted": false } }
          kbd.handlePress(ev(Qt.Key_F2))
          kbd.handlePress(ev(Qt.Key_Delete))
          kbd.handlePress(ev(Qt.Key_C, Qt.ControlModifier))
          kbd.handlePress(ev(Qt.Key_X, Qt.ControlModifier))
          kbd.handlePress(ev(Qt.Key_V, Qt.ControlModifier))
          // P1-3 (architectural audit 2026-08-17): Shift+Return ("open
          // terminal here") calls Backend.TerminalResolver, but this file
          // only imports QtQuick and ../state -- caught here explicitly
          // (try/catch) instead of letting a ReferenceError propagate as a
          // generic "exception: ..." failure from the runner.
          var terminalShortcutError = null
          try {
            kbd.handlePress(ev(Qt.Key_Return, Qt.ShiftModifier))
          } catch (e) {
            terminalShortcutError = String(e)
          }
          kbd.destroy()

          // Also checked against the REAL production instance (nested under
          // panels/ActiveFileList.qml, reached here through
          // sc._content.actionEngine.list -- see P0-1's lesson in
          // ARCHITECTURE_EVOLUTION_AUDIT.md: QML's id-based context
          // resolution can make an isolated Qt.createComponent() repro
          // behave differently from the real nested tree, so imports are
          // verified both ways rather than trusting either alone.
          var realTreeError = null
          var c = sc._content
          if (c && c.actionEngine && c.actionEngine.list && c.actionEngine.list.keyboardShortcuts) {
            try {
              c.actionEngine.list.keyboardShortcuts.handlePress(ev(Qt.Key_Return, Qt.ShiftModifier))
            } catch (e) {
              realTreeError = String(e)
            }
          }

          var ok = called.F2 && called.Del && called.CtrlC && called.CtrlX && called.CtrlV
            && !terminalShortcutError && !realTreeError
          done(ok, ok ? "all 6 shortcuts routed correctly (isolated + real tree)"
                      : (terminalShortcutError ? "Shift+Return (isolated) threw: " + terminalShortcutError
                        : realTreeError ? "Shift+Return (real tree) threw: " + realTreeError
                        : JSON.stringify(called)))
        })

        // Regression for P1-3 (architectural audit 2026-08-17):
        // core/DialogLayer.qml's onAuthSubmitted (network "connect to
        // server" auth dialog) calls Backend.NetworkResolver.submitAuth(),
        // but the file only imported qs.Commons/qs.Ui/../dialogs/../state --
        // same missing-import bug as KeyboardShortcuts.qml above, different
        // file. Exercises the REAL composition root (sc._content) by
        // emitting the real ConnectServer dialog's authSubmitted signal, not
        // a reimplementation.
        sc.add("DialogLayer: network auth submission resolves Backend.NetworkResolver (P1-3 regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var authError = null
          try {
            c.dialogLayer.connectServer.authSubmitted("user", "pass", false)
          } catch (e) {
            authError = String(e)
          }
          done(!authError, authError ? "authSubmitted threw: " + authError : "Backend.NetworkResolver resolved correctly")
        })

        // ======================= P0-3 (forensic audit 2026-08-16) =======================
        // openFileInArchive() extracts a single archive member to
        // ~/.cache/omafiles/archive-open/<sha1(archivePath+member)>/<name> via a
        // plain shell `>` redirection. Before the fix, if an attacker could plant a
        // symlink at that fully-predictable (unsalted SHA-1, no randomness) path
        // BEFORE the victim opened the file, the redirection followed the symlink
        // and overwrote whatever it pointed to with the archive's (attacker-
        // controlled) content instead of creating a fresh file. This plants the
        // exact exploit and asserts the victim target survives untouched.
        sc.add("openFileInArchive: pre-planted symlink at the cache path is not followed (P0-3 regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var zipPath = sc.opsDir + "/p03-archive.zip"
          var victim = sc.opsDir + "/p03-victim.txt"
          var buildCmd = "cd " + sc._q(sc.opsDir)
            + " && rm -rf p03src && mkdir p03src"
            + " && echo PWNED_CONTENT > p03src/secret.txt"
            + " && (cd p03src && zip -q " + sc._q(zipPath) + " secret.txt)"
            + " && rm -rf p03src"
            + " && echo VICTIM_UNTOUCHED > " + sc._q(victim)
          sc._sh(["bash", "-c", buildCmd], function (buildResult) {
            if (buildResult.exitCode !== 0) { done(false, "fixture build failed: " + buildResult.stderr); return }
            var outDir = Paths.homeDir + "/.cache/omafiles/archive-open/"
              + Backend.ThumbnailProvider.cacheKey(zipPath + "|secret.txt")
            var out = outDir + "/secret.txt"
            var plantCmd = "rm -rf -- " + sc._q(outDir) + " && mkdir -p -- " + sc._q(outDir)
              + " && ln -s -- " + sc._q(victim) + " " + sc._q(out)
            sc._sh(["bash", "-c", plantCmd], function (plantResult) {
              if (plantResult.exitCode !== 0) { done(false, "couldn't plant symlink: " + plantResult.stderr); return }
              c.actionEngine.enterArchive(zipPath)
              c.actionEngine.openFileInArchive({ name: "secret.txt", type: "file" })
              // openFileInArchive is fire-and-forget (its own internal
              // ProcessRunner isn't exposed to the test); a tiny single-file
              // extraction settles in a few ms, 500ms is a generous margin.
              var timeout = Qt.createQmlObject('import QtQuick; Timer { interval: 500; repeat: false }', sc)
              timeout.triggered.connect(function () {
                c.actionEngine.exitArchive()
                sc._sh(["bash", "-c", "cat -- " + sc._q(victim)], function (victimResult) {
                  var victimIntact = String(victimResult.stdout).trim() === "VICTIM_UNTOUCHED"
                  done(victimIntact, victimIntact
                    ? "victim file untouched — pre-planted symlink was destroyed and replaced before extraction"
                    : "VULNERABLE: the pre-planted symlink was followed, victim file now contains: " + String(victimResult.stdout).trim())
                })
              })
              timeout.start()
            })
          })
        })
  }
}

import QtQuick
import Omafiles.Backend as Backend
import "../../../services"
import "../../../state"
import "../../../Utils.js" as Utils

// Domain checks extracted from integrations/standalone/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Conflict detection sees a broken symlink (BUG-01)", function (done) {
          var link = sc.opsDir + "/bug01-broken-" + Date.now()
          sc._sh(["ln", "-s", "/omafiles-no-such-target-xyz", link], function (r) {
            if (r.exitCode !== 0) { done(false, "couldn't create the broken symlink: " + r.stderr); return }
            var hit = FileOperations.existingPaths([link])
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
        sc.add("empty-trash.sh empties an isolated home trash (BUG-02)", function (done) {
          var fakeHome = sc.dir + "/et-home"
          var tFiles = fakeHome + "/.local/share/Trash/files"
          var tInfo = fakeHome + "/.local/share/Trash/info"
          var fakeBin = sc.dir + "/et-bin"
          var setup =
            "mkdir -p " + sc._q(tFiles) + " " + sc._q(tInfo) + " " + sc._q(fakeBin) + " && " +
            "printf x > " + sc._q(tFiles + "/victim.txt") + " && " +
            "printf '[Trash Info]\\n' > " + sc._q(tInfo + "/victim.txt.trashinfo") + " && " +
            "printf '#!/bin/sh\\n' > " + sc._q(fakeBin + "/findmnt") + " && chmod +x " + sc._q(fakeBin + "/findmnt")
          sc._sh(["bash", "-c", setup], function (r0) {
            if (r0.exitCode !== 0) { done(false, "setup failed: " + r0.stderr); return }
            var run = "env -i HOME=" + sc._q(fakeHome) + " PATH=" + sc._q(fakeBin) + ":/usr/bin:/bin bash "
              + sc._q(sc.pluginRoot + "/empty-trash.sh")
            sc._sh(["bash", "-c", run], function (r1) {
              sc._sh(["bash", "-c", "ls -A " + sc._q(tFiles) + " | wc -l"], function (r2) {
                var remaining = parseInt(String(r2.stdout).trim(), 10)
                done(r1.exitCode === 0 && remaining === 0,
                     "exit=" + r1.exitCode + " remaining items=" + remaining)
              })
            })
          })
        })

        // list-archive.sh over a deterministic .tar built from listDir
        // (sub/ + alpha/beta/gamma.txt). Confirms that it lists the top-level
        // elements in the NUL-delimited contract (name\0isdir\0...).
        sc.add("list-archive.sh lists a tar fixture (BUG-02)", function (done) {
          var tarPath = sc.opsDir + "/la-fixture.tar"
          var mk = "tar -cf " + sc._q(tarPath) + " -C " + sc._q(sc.listDir) + " sub alpha.txt beta.txt gamma.txt"
          sc._sh(["bash", "-c", mk], function (r0) {
            if (r0.exitCode !== 0) { done(false, "tar setup failed: " + r0.stderr); return }
            sc._sh(["bash", sc.pluginRoot + "/list-archive.sh", tarPath, ""], function (r) {
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
          sc._sh(["bash", sc.pluginRoot + "/mount-iso.sh", sc.dir + "/no-such-file.iso"], function (r) {
            var ok = r.exitCode !== 0 && String(r.stdout).trim() === ""
            done(ok, "exit=" + r.exitCode + " stdout='" + String(r.stdout).trim() + "'")
          })
        })

        // open-with-list.sh over a .txt: exit 0 and output with valid TSV shape
        // (empty, or each line with a TAB name<TAB>id). It doesn't fix WHICH apps there are
        // (depends on the system); it does check that it's invoked and responds in its contract.
        sc.add("open-with-list.sh returns valid TSV (BUG-02)", function (done) {
          sc._sh(["bash", sc.pluginRoot + "/open-with-list.sh", sc.note], function (r) {
            var lines = String(r.stdout).split("\n").filter(function (l) { return l.length > 0 })
            var shapeOk = lines.every(function (l) { return l.indexOf("\t") >= 0 })
            done(r.exitCode === 0 && shapeOk, "exit=" + r.exitCode + " lines=" + lines.length)
          })
        })

        // ======================= BUG-03 (Hardening-2) =======================

        // Properties/chmod built `du -shc -- <all>` and `stat -c%a -- <all>`
        // in a single bash line -> with a huge selection it blew the length
        // limit (ARG_MAX / 128 KiB per argument) and the dialog was left without
        // size/permissions. Now they use FileOperations.totalSize/octalModes (native,
        // no command line). The test builds a list that DOES overflow that
        // line: the native path handles it; the old shell fails. It fails with the
        // previous code (octalModes didn't exist -> TypeError).
        sc.add("Properties/chmod handle a huge selection without ARG_MAX (BUG-03)", function (done) {
          // Two fixtures that exist (to assert correct sum/mode) + padding of
          // long nonexistent paths until the `stat/du -- <all>` line that
          // the old code used would overflow the per-argument limit (128 KiB).
          var reals = [sc.note, sc.png]
          var expected = FileOperations.totalSize(reals)
          var pad = new Array(160).join("x")
          var big = reals.slice()
          while (big.length < 2000) big.push(sc.opsDir + "/" + pad + big.length)
          // NATIVE: doesn't build a command line -> handles the huge list.
          var total = FileOperations.totalSize(big)      // sums only the 2 real ones
          var modes = FileOperations.octalModes(big)     // aligned with big, "" if missing
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
  }
}

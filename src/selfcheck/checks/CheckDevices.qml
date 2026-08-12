import QtQuick
import Omafiles.Backend as Backend
import "../../../services"
import "../../../state"
import "../../../Utils.js" as Utils

// Domain checks extracted from integrations/standalone/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Native trash listing: trashRoots + trashInfo (Fase 16)", function (done) {
          var home = Backend.Env.get("HOME")
          var roots = FileOperations.trashRoots()
          var homeTrash = home + "/.local/share/Trash"
          var hasHome = roots.indexOf(homeTrash) >= 0
          if (!hasHome) { done(false, "trashRoots doesn't include the home trash: " + JSON.stringify(roots)); return }

          var fname = "selfcheck-trashinfo-" + Date.now() + ".txt"
          var target = sc.opsDir + "/" + fname
          FileOperations.copy(sc.note, target)
          sc._fileOp(done, function () {          // copy
            sc._fileOp(done, function () {        // trash
              // trashInfo must list the item with its original path and epoch>0.
              var info = FileOperations.trashInfo()
              var found = null
              for (var i = 0; i < info.length; i++)
                if (info[i].origPath === target) found = info[i]
              var ok = found !== null && found.epoch > 0 && found.trashRoot === homeTrash
              sc._fileOp(done, function () {      // restore (cleanup)
                done(ok, ok ? "trashRoots+trashInfo OK" : "trashInfo doesn't reflect the item")
              })
              FileOperations.restoreByOrigPath(target)
            })
            FileOperations.trash(target)
          })
        })

        // Native NetworkMounts.list() (replaces list-network-mounts.sh): without
        // active GVfs mounts in the test environment, it must return a list
        // (empty) without breaking. Smoke test: content can't be asserted without a
        // real mount, but the native path does respond with an array.
        sc.add("Native network mounts listing returns a list (Fase 16)", function (done) {
          var l = Backend.NetworkMounts.list()
          done(l !== undefined && l !== null && typeof l.length === "number",
               "NetworkMounts.list() -> " + (l ? l.length : "null") + " entries")
        })
  }
}

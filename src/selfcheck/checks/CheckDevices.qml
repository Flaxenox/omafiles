import QtQuick
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// Domain checks extracted from app/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Native trash listing: trashRoots + trashInfo", function (done) {
          // Both async since the P0 trash-freeze fix (V1_1_P0_TRASH_FREEZE) --
          // requestId filters out replies to any OTHER in-flight request on
          // this shared singleton (see FileOperations.h).
          var home = Backend.Env.get("HOME")
          var homeTrash = home + "/.local/share/Trash"
          var rootsReqId = Date.now()

          function onRoots(id, roots) {
            if (id !== rootsReqId) return
            Backend.FileOperations.trashRootsReady.disconnect(onRoots)
            var hasHome = roots.indexOf(homeTrash) >= 0
            if (!hasHome) { done(false, "trashRoots doesn't include the home trash: " + JSON.stringify(roots)); return }

            var fname = "selfcheck-trashinfo-" + Date.now() + ".txt"
            var target = sc.opsDir + "/" + fname
            Backend.FileOperations.copy(sc.note, target)
            sc._fileOp(done, function () {          // copy
              sc._fileOp(done, function () {        // trash
                var infoReqId = Date.now()
                function onInfo(iid, info) {
                  if (iid !== infoReqId) return
                  Backend.FileOperations.trashInfoReady.disconnect(onInfo)
                  // trashInfo must list the item with its original path and epoch>0.
                  var found = null
                  for (var i = 0; i < info.length; i++)
                    if (info[i].origPath === target) found = info[i]
                  var ok = found !== null && found.epoch > 0 && found.trashRoot === homeTrash
                  sc._fileOp(done, function () {      // restore (cleanup)
                    done(ok, ok ? "trashRoots+trashInfo OK" : "trashInfo doesn't reflect the item")
                  })
                  Backend.FileOperations.restoreByOrigPath(target)
                }
                Backend.FileOperations.trashInfoReady.connect(onInfo)
                Backend.FileOperations.requestTrashInfo(infoReqId)
              })
              Backend.FileOperations.trash(target)
            })
          }
          Backend.FileOperations.trashRootsReady.connect(onRoots)
          Backend.FileOperations.requestTrashRoots(rootsReqId)
        })

        // Native Backend.NetworkMounts.list() (replaces list-network-mounts.sh): without
        // active GVfs mounts in the test environment, it must return a list
        // (empty) without breaking. Smoke test: content can't be asserted without a
        // real mount, but the native path does respond with an array.
        sc.add("Native network mounts listing returns a list", function (done) {
          var l = Backend.NetworkMounts.list()
          done(l !== undefined && l !== null && typeof l.length === "number",
               "Backend.NetworkMounts.list() -> " + (l ? l.length : "null") + " entries")
        })

        // Native Backend.LocalMounts.list() (V1.2, replaces list-mounts.sh's
        // findmnt+lsblk). Every real Linux machine running this has SOME
        // root filesystem mounted at "/" -- unlike asserting a specific
        // removable drive (machine-dependent), this is a real, portable
        // assertion: the native UDisks2 path must find it, label it
        // "System (/)" exactly like the retired script did, and report a
        // real fstype.
        sc.add("Native local mounts listing (LocalMounts, V1.2) includes the root filesystem", function (done) {
          var l = Backend.LocalMounts.list()
          if (!l || typeof l.length !== "number") { done(false, "LocalMounts.list() didn't return an array"); return }
          var root = null
          for (var i = 0; i < l.length; i++) if (l[i].path === "/") root = l[i]
          var ok = !!root && root.mounted === true && root.label === "System (/)" && !!root.fstype
          done(ok, ok ? "root fs found: " + JSON.stringify(root) : (l.length + " entries, root missing/wrong: " + JSON.stringify(l)))
        })

        // GetBlockDevices()'s enumeration order (UDisks2's own internal
        // object order) has no relation to mount time -- a removable drive
        // plugged in mid-session could register its D-Bus object before
        // the system disk's, landing ABOVE "System (/)"/other fixed drives
        // in the sidebar (reproduced live: josema plugged in a USB, it
        // appeared first). LocalMounts.cpp's mountRank() sorts explicitly;
        // this asserts the invariant that fix guards -- no removable entry
        // may precede any fixed (non-removable) one. Vacuously true (and
        // still meaningful to run) on a machine/CI with no removable drive
        // attached; only a real violation of the ordering fails it.
        sc.add("LocalMounts.list() orders fixed drives before removable ones (V1.2 ordering regression)", function (done) {
          var l = Backend.LocalMounts.list()
          if (!l || typeof l.length !== "number") { done(false, "LocalMounts.list() didn't return an array"); return }
          var sawRemovable = false, ok = true, detail = ""
          for (var i = 0; i < l.length; i++) {
            if (l[i].removable) { sawRemovable = true }
            else if (sawRemovable) { ok = false; detail = "fixed entry '" + l[i].label + "' appeared after a removable one: " + JSON.stringify(l); break }
          }
          done(ok, ok ? (l.length + " entries, order OK" + (sawRemovable ? " (includes a removable drive)" : " (no removable drive attached to test against)"))
                      : detail)
        })
  }
}

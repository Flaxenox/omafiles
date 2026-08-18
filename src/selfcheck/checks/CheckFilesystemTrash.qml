import QtQuick
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// Trash & conflict detection domain checks.
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Trash removes item from source", function (done) {
          var work = sc.opsDir + "/trash-src.txt"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.note, work) },
            function () { Backend.FileOperations.trash(work) }
          ], done, function () {
            sc._listOnce(sc.opsDir, function (e) {
              var gone = !sc._has(e, "trash-src.txt")
              sc._seqOps([function () { Backend.FileOperations.restoreByOrigPath(work) }], done, function () {
                sc._listOnce(sc.opsDir, function (e2) {
                  done(gone && sc._has(e2, "trash-src.txt"),
                       gone ? "sent and restored" : "didn't leave the source")
                })
              })
            })
          })
        })

        sc.add("ActionEngine trash+restore end-to-end (frontend wiring)", function (done) {
          var aeComp = Qt.createComponent(Qt.resolvedUrl("../../../logic/ActionEngine.qml"))
          if (aeComp.status === Component.Error) { done(false, aeComp.errorString()); return }
          var stubNav = Qt.createQmlObject('import QtQuick; Item { function refresh() {} }', sc)
          var ae = aeComp.createObject(sc, { "navController": stubNav })
          if (!ae) { done(false, "couldn't create ActionEngine"); return }
          var work = sc.opsDir + "/ae-trash-" + Date.now() + ".txt"
          var wname = work.substring(work.lastIndexOf("/") + 1)
          sc._seqOps([function () { Backend.FileOperations.copy(sc.note, work) }], done, function () {
            ae.runNativeTrash([work], "", function () {
              sc._listOnce(sc.opsDir, function (e) {
                var gone = !sc._has(e, wname)
                ae.runNativeRestore([work], "", function () {
                  sc._listOnce(sc.opsDir, function (e2) {
                    var back = sc._has(e2, wname)
                    ae.destroy(); stubNav.destroy()
                    done(gone && back, gone ? (back ? "trash+restore via ActionEngine OK" : "restore didn't put the file back")
                                            : "runNativeTrash didn't take the file out of the source")
                  })
                })
              })
            })
          })
        })

        sc.add("Trash + restore directory (round-trip)", function (done) {
          var dir = sc.opsDir + "/trashdir"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.listDir, dir) },
            function () { Backend.FileOperations.trash(dir) },
            function () { Backend.FileOperations.restoreByOrigPath(dir) }
          ], done, function () {
            sc._listOnce(dir, function (e) {
              done(e.length === 4 && sc._has(e, "sub"), "tree restored: " + e.length)
            })
          })
        })

        sc.add("Trash + restore symlink (round-trip)", function (done) {
          var lnk = sc.opsDir + "/trashlink"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.dir + "/link.txt", lnk) },
            function () { Backend.FileOperations.trash(lnk) },
            function () { Backend.FileOperations.restoreByOrigPath(lnk) }
          ], done, function () {
            sc._listOnce(sc.opsDir, function (e) {
              var ok = false
              for (var i = 0; i < e.length; i++)
                if (e[i].name === "trashlink" && e[i].link && e[i].link.length > 0) ok = true
              done(ok, ok ? "symlink restored as a link" : "didn't come back as a symlink")
            })
          })
        })

        sc.add("Trash + restore Unicode name (round-trip)", function (done) {
          var uni = sc.opsDir + "/café ñ 文件.txt"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.note, uni) },
            function () { Backend.FileOperations.trash(uni) },
            function () { Backend.FileOperations.restoreByOrigPath(uni) }
          ], done, function () {
            sc._listOnce(sc.opsDir, function (e) {
              done(sc._has(e, "café ñ 文件.txt"), "unicode round-trip OK")
            })
          })
        })

        sc.add("Trash collision (restore both by orig path)", function (done) {
          var csub = sc.opsDir + "/csub"
          var a = sc.opsDir + "/coll.txt"
          var b = csub + "/coll.txt"
          sc._seqOps([
            function () { Backend.FileOperations.mkdir(csub) },
            function () { Backend.FileOperations.copy(sc.note, a) },
            function () { Backend.FileOperations.copy(sc.note, b) },
            function () { Backend.FileOperations.trash(a) },
            function () { Backend.FileOperations.trash(b) },
            function () { Backend.FileOperations.restoreByOrigPath(a) },
            function () { Backend.FileOperations.restoreByOrigPath(b) }
          ], done, function () {
            sc._listOnce(sc.opsDir, function (e) {
              var aBack = sc._has(e, "coll.txt")
              sc._listOnce(csub, function (e2) {
                var bBack = sc._has(e2, "coll.txt")
                done(aBack && bBack, aBack && bBack ? "collision resolved, both restored" : "didn't restore both")
              })
            })
          })
        })

        sc.add("Restore collision (destination exists -> error)", function (done) {
          var work = sc.opsDir + "/restcoll.txt"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.note, work) },
            function () { Backend.FileOperations.trash(work) },
            function () { Backend.FileOperations.copy(sc.note, work) }
          ], done, function () {
            function onErr(op, path, msg) {
              if (path !== work) return
              cleanup()
              sc._seqOps([
                function () { Backend.FileOperations.remove(work) },
                function () { Backend.FileOperations.restoreByOrigPath(work) }
              ], done, function () { done(true, "error if the destination exists: " + msg) })
            }
            function onFin(op, path) { if (path !== work) return; cleanup(); done(false, "should not restore over an existing destination") }
            function cleanup() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
            Backend.FileOperations.error.connect(onErr)
            Backend.FileOperations.finished.connect(onFin)
            Backend.FileOperations.restoreByOrigPath(work)
          })
        })

        sc.add("Restore recreates missing parent", function (done) {
          var psub = sc.opsDir + "/psub"
          var item = psub + "/child.txt"
          sc._seqOps([
            function () { Backend.FileOperations.mkdir(psub) },
            function () { Backend.FileOperations.copy(sc.note, item) },
            function () { Backend.FileOperations.trash(item) },
            function () { Backend.FileOperations.remove(psub) },
            function () { Backend.FileOperations.restoreByOrigPath(item) }
          ], done, function () {
            sc._listOnce(psub, function (e) {
              done(sc._has(e, "child.txt"), "parent recreated and file restored")
            })
          })
        })

        sc.add("ActionEngine native trash runner + undo (delete-to-trash path)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var work = sc.opsDir + "/runner-trash.txt"
          sc._fileOp(done, function () {
            var started = c.actionEngine.runNativeTrash([work], "", function () {
              c.actionEngine.pushUndo("delete test",
                function (onSettled) { return c.actionEngine.runNativeRestore([work], "", onSettled) },
                function (onSettled) { return c.actionEngine.runNativeTrash([work], "", onSettled) })
              sc._listOnce(sc.opsDir, function (e) {
                if (sc._has(e, "runner-trash.txt")) { done(false, "wasn't sent to trash"); return }
                sc._fileOp(done, function () {
                  sc._listOnce(sc.opsDir, function (e2) {
                    done(sc._has(e2, "runner-trash.txt"), "sent and restored by undo")
                  })
                })
                c.undoLast()
              })
            })
            if (!started) done(false, "runNativeTrash returned false")
          })
          Backend.FileOperations.copy(sc.note, work)
        })

        sc.add("Trash + restore from symlinked directory (path normalization)", function (done) {
          var realTargetDir = sc.dir + "/sym-real-dir"
          var symlinkDir = sc.dir + "/sym-link-dir"
          var symFile = symlinkDir + "/sym-target.txt"
          var realFile = realTargetDir + "/sym-target.txt"
          sc._seqOps([
            function () { Backend.FileOperations.mkdir(realTargetDir) },
            function () {
              sc._sh(["ln", "-s", realTargetDir, symlinkDir], function (r) {
                if (r.exitCode !== 0) { done(false, "symlink setup failed"); return }
                Backend.FileOperations.copy(sc.note, realFile)
              })
            }
          ], done, function () {
            Backend.FileOperations.trash(symFile)
            var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 40; repeat: false }', sc)
            timer.triggered.connect(function () {
              Backend.FileOperations.restoreByOrigPath(symFile)
              var timer2 = Qt.createQmlObject('import QtQuick; Timer { interval: 40; repeat: false }', sc)
              timer2.triggered.connect(function () {
                sc._listOnce(realTargetDir, function (entries) {
                  var restored = sc._has(entries, "sym-target.txt")
                  done(restored, restored ? "restored via symlink path OK" : "restore by symlink path failed")
                })
              })
              timer2.start()
            })
            timer.start()
          })
        })

        sc.add("Navigate to Trash via bookmark (real UI path, repeated) does not freeze", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath

          function tick(n, after) {
            var responsive = false
            var t = Qt.createQmlObject('import QtQuick; Timer { interval: 30; repeat: false }', sc)
            t.triggered.connect(function () { responsive = true })
            // Same call the sidebar bookmark row makes on click
            // (Sidebar.onBookmarkOpened -> MainLayout -> commandFacade.openBookmark),
            // not an isolated Qt.createComponent fragment.
            c.commandFacade.openBookmark({ path: Paths.trashDir, type: "dir" })
            t.start()
            sc._poll(function () { return NavState.currentPath === Paths.trashDir && responsive }, function (ok1) {
              t.destroy()
              if (!ok1) { done(false, "iteration " + n + ": didn't navigate or event loop stalled entering Trash"); return }
              var responsive2 = false
              var t2 = Qt.createQmlObject('import QtQuick; Timer { interval: 30; repeat: false }', sc)
              t2.triggered.connect(function () { responsive2 = true })
              c.commandFacade.openBookmark({ path: sc.opsDir, type: "dir" })
              t2.start()
              sc._poll(function () { return NavState.currentPath === sc.opsDir && responsive2 }, function (ok2) {
                t2.destroy()
                if (!ok2) { done(false, "iteration " + n + ": didn't navigate away or event loop stalled leaving Trash"); return }
                if (n >= 3) { after(); return }
                tick(n + 1, after)
              })
            })
          }

          function withNTrashedItems(count, cb) {
            if (count === 0) { cb(); return }
            var names = []
            for (var i = 0; i < count; i++) names.push(sc.opsDir + "/trashnav-" + Date.now() + "-" + i + ".txt")
            var i2 = 0
            function copyNext() {
              if (i2 >= names.length) { trashAll(0); return }
              Backend.FileOperations.copy(sc.note, names[i2])
              sc._fileOp(done, function () { i2++; copyNext() })
            }
            var j = 0
            function trashAll() {
              if (j >= names.length) { cb(); return }
              Backend.FileOperations.trash(names[j])
              sc._fileOp(done, function () { j++; trashAll() })
            }
            copyNext()
          }

          NavState.currentPath = sc.opsDir
          withNTrashedItems(0, function () {
            tick(1, function () {
              withNTrashedItems(2, function () {
                tick(1, function () {
                  NavState.currentPath = prevPath
                  done(true, "repeated navigation in/out of Trash (empty and populated) stayed responsive")
                })
              })
            })
          })
        })

        sc.add("Restore + permanently delete from Trash via real itemActions() (UI path)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var facade = c.commandFacade
          var prevPath = NavState.currentPath
          var work = sc.opsDir + "/ia-trash-" + Date.now() + ".txt"
          var wname = work.substring(work.lastIndexOf("/") + 1)

          function findAction(actions, label) {
            for (var i = 0; i < actions.length; i++) if (actions[i].label.indexOf(label) === 0) return actions[i]
            return null
          }
          function selectByName(name) {
            var entries = NavState.visibleEntries
            for (var i = 0; i < entries.length; i++) {
              if (entries[i].name === name) { SelectionState.selectOnly(i); return true }
            }
            return false
          }

          Backend.FileOperations.copy(sc.note, work)
          sc._fileOp(done, function () {
            Backend.FileOperations.trash(work)
            sc._fileOp(done, function () {
              facade.openBookmark({ path: Paths.trashDir, type: "dir" })
              sc._poll(function () { return NavState.currentPath === Paths.trashDir }, function () {
                sc._poll(function () { return sc._has(NavState.visibleEntries, wname) }, function (listed) {
                  if (!listed) { done(false, "trashed item never appeared in the Trash listing"); return }
                  if (!selectByName(wname)) { done(false, "couldn't select the trashed item"); return }
                  var restoreAction = findAction(facade.itemActions(), "Restore")
                  if (!restoreAction) { done(false, "no Restore action offered in Trash"); return }
                  restoreAction.action()
                  sc._fileOp(done, function () {
                    sc._listOnce(sc.opsDir, function (e) {
                      if (!sc._has(e, wname)) { done(false, "Restore didn't put the file back"); return }
                      // Trash it again to exercise permanent delete.
                      Backend.FileOperations.trash(work)
                      sc._fileOp(done, function () {
                        sc._poll(function () { return sc._has(NavState.visibleEntries, wname) }, function (listed2) {
                          if (!listed2) { done(false, "re-trashed item never re-appeared"); return }
                          if (!selectByName(wname)) { done(false, "couldn't re-select the trashed item"); return }
                          var delAction = findAction(facade.itemActions(), "Delete permanently")
                          if (!delAction) { done(false, "no 'Delete permanently' action offered in Trash"); return }
                          delAction.action() // requestDelete() -> ActionState.pendingDeleteNames, awaits ConfirmDialog
                          sc._poll(function () { return ActionState.pendingDeleteNames.length > 0 }, function (pending) {
                            if (!pending) { done(false, "requestDelete() didn't arm the confirm dialog"); return }
                            c.actionEngine.confirmDelete()
                            sc._fileOp(done, function () {
                              // trashInfo is async since the P0 trash-freeze fix
                              // (V1_1_P0_TRASH_FREEZE).
                              var reqId = Date.now()
                              function onInfo(id, info) {
                                if (id !== reqId) return
                                Backend.FileOperations.trashInfoReady.disconnect(onInfo)
                                var stillThere = false
                                for (var i = 0; i < info.length; i++) if (info[i].name === wname) stillThere = true
                                NavState.currentPath = prevPath
                                done(!stillThere, stillThere ? "permanent delete left the .trashinfo behind" : "restore + permanent delete via real itemActions() OK")
                              }
                              Backend.FileOperations.trashInfoReady.connect(onInfo)
                              Backend.FileOperations.requestTrashInfo(reqId)
                            })
                          })
                        })
                      })
                    })
                  })
                })
              })
            })
          })
        })

        sc.add("Delete confirmation: real dialog path (cancel, multi-select, trash-send, permanent, no stale names)", function (done) {
          // P2.1 follow-up (2026-08-17): pendingDeleteNames moved from an
          // untyped root.pendingDeleteNames to ActionState.pendingDeleteNames.
          // This exercises the REAL path end to end -- CommandFacade.itemActions()
          // -> ActionEngine.requestDelete() -> ActionState.pendingDeleteNames ->
          // the real DialogLayer ConfirmDialog (c.dialogLayer.deleteConfirm,
          // not a re-simulated formula) -> canceled()/confirmed() (the same
          // signals the real UI's Escape/click paths emit) ->
          // ActionEngine.confirmDelete() -- not an isolated Qt.createComponent
          // fragment.
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var facade = c.commandFacade
          var confirm = c.dialogLayer.deleteConfirm
          var prevPath = NavState.currentPath

          function findAction(actions, label) {
            for (var i = 0; i < actions.length; i++) if (actions[i].label.indexOf(label) === 0) return actions[i]
            return null
          }
          function selectByNames(names) {
            var entries = NavState.visibleEntries
            var idx = []
            for (var i = 0; i < entries.length; i++) if (names.indexOf(entries[i].name) >= 0) idx.push(i)
            if (idx.length !== names.length) return false
            SelectionState.selectedIndices = idx
            return true
          }

          var stamp = Date.now()
          var aName = "delconf-a-" + stamp + ".txt"
          var bName = "delconf-b-" + stamp + ".txt"
          var cName = "delconf-c-" + stamp + ".txt"
          var aPath = sc.opsDir + "/" + aName
          var bPath = sc.opsDir + "/" + bName
          var cPath = sc.opsDir + "/" + cName

          Backend.FileOperations.copy(sc.note, aPath)
          sc._fileOp(done, function () {
            Backend.FileOperations.copy(sc.note, bPath)
            sc._fileOp(done, function () {
              Backend.FileOperations.copy(sc.note, cPath)
              sc._fileOp(done, function () {
                c.navController.navigateTo(sc.opsDir)
                sc._poll(function () {
                  return NavState.currentPath === sc.opsDir && sc._has(NavState.visibleEntries, aName)
                    && sc._has(NavState.visibleEntries, bName) && sc._has(NavState.visibleEntries, cName)
                }, function (listed) {
                  if (!listed) { done(false, "fixture files never appeared in the listing"); return }

                  // ---- 1) multi-select + cancel: no delete happens, dialog closes, names cleared ----
                  if (!selectByNames([aName, bName])) { done(false, "couldn't select a+b"); return }
                  var delAction1 = findAction(facade.itemActions(), "Delete")
                  if (!delAction1) { done(false, "no Delete action offered"); return }
                  delAction1.action()
                  if (!confirm.opened) { done(false, "requestDelete() didn't open the real ConfirmDialog"); return }
                  if (ActionState.pendingDeleteNames.length !== 2
                      || ActionState.pendingDeleteNames.indexOf(aName) < 0 || ActionState.pendingDeleteNames.indexOf(bName) < 0) {
                    done(false, "pendingDeleteNames wrong for multi-select: " + JSON.stringify(ActionState.pendingDeleteNames)); return
                  }
                  if (confirm.message.indexOf("2 items") < 0 || confirm.message.indexOf("PERMANENTLY") >= 0) {
                    done(false, "dialog message wrong for a non-Trash multi delete: " + confirm.message); return
                  }
                  confirm.canceled() // same signal the real Escape/Cancel-button path emits
                  if (confirm.opened || ActionState.pendingDeleteNames.length !== 0) {
                    done(false, "cancel didn't close the dialog / clear pendingDeleteNames"); return
                  }
                  sc._listOnce(sc.opsDir, function (eAfterCancel) {
                    if (!sc._has(eAfterCancel, aName) || !sc._has(eAfterCancel, bName)) {
                      done(false, "cancel must not have deleted anything, but a file is gone"); return
                    }

                    // ---- 2) single delete (send to trash), confirmed for real ----
                    if (!selectByNames([aName])) { done(false, "couldn't select a alone"); return }
                    var delAction2 = findAction(facade.itemActions(), "Delete")
                    delAction2.action()
                    if (ActionState.pendingDeleteNames.length !== 1 || ActionState.pendingDeleteNames[0] !== aName) {
                      done(false, "pendingDeleteNames wrong for single delete: " + JSON.stringify(ActionState.pendingDeleteNames)); return
                    }
                    if (confirm.message.indexOf(aName) < 0 || confirm.message.indexOf("trash?") < 0) {
                      done(false, "dialog message wrong for a single non-Trash delete: " + confirm.message); return
                    }
                    confirm.confirmed() // same signal the real click/Enter path emits -> actionEngine.confirmDelete()
                    sc._fileOp(done, function () {
                      sc._listOnce(sc.opsDir, function (eAfterSend) {
                        if (sc._has(eAfterSend, aName)) { done(false, "confirmed delete didn't send the file to trash"); return }
                        if (ActionState.pendingDeleteNames.length !== 0) { done(false, "pendingDeleteNames not cleared after confirm"); return }

                        // ---- 3) permanent delete from inside Trash ----
                        c.navController.navigateTo(Paths.trashDir)
                        sc._poll(function () { return NavState.currentPath === Paths.trashDir && sc._has(NavState.visibleEntries, aName) }, function (listedInTrash) {
                          if (!listedInTrash) { done(false, "trashed file never appeared in Trash listing"); return }
                          if (!selectByNames([aName])) { done(false, "couldn't select the trashed item"); return }
                          var delAction3 = findAction(facade.itemActions(), "Delete permanently")
                          if (!delAction3) { done(false, "no 'Delete permanently' action in Trash"); return }
                          delAction3.action()
                          if (confirm.message.indexOf(aName) < 0 || confirm.message.indexOf("PERMANENTLY") < 0) {
                            done(false, "dialog message wrong for permanent delete: " + confirm.message); return
                          }
                          confirm.confirmed()
                          sc._fileOp(done, function () {
                            // trashInfo is async since the P0 trash-freeze fix
                            // (V1_1_P0_TRASH_FREEZE).
                            var reqId = Date.now()
                            function onInfo(id, info) {
                              if (id !== reqId) return
                              Backend.FileOperations.trashInfoReady.disconnect(onInfo)
                              var stillThere = false
                              for (var i = 0; i < info.length; i++) if (info[i].name === aName) stillThere = true
                              if (stillThere) { done(false, "permanent delete left the .trashinfo behind"); return }

                              // ---- 4) no stale names from the previous (permanent-delete) operation ----
                              c.navController.navigateTo(sc.opsDir)
                              _afterTrashInfoCheck()
                            }
                            Backend.FileOperations.trashInfoReady.connect(onInfo)
                            Backend.FileOperations.requestTrashInfo(reqId)
                          })
                          function _afterTrashInfoCheck() {
                            sc._poll(function () { return NavState.currentPath === sc.opsDir && sc._has(NavState.visibleEntries, cName) }, function (listedC) {
                              if (!listedC) { done(false, "third fixture file never appeared"); return }
                              if (!selectByNames([cName])) { done(false, "couldn't select the third file"); return }
                              var delAction4 = findAction(facade.itemActions(), "Delete")
                              delAction4.action()
                              var stale = ActionState.pendingDeleteNames.length !== 1 || ActionState.pendingDeleteNames[0] !== cName
                                || confirm.message.indexOf(aName) >= 0 || confirm.message.indexOf(bName) >= 0
                              confirm.canceled()
                              NavState.currentPath = prevPath
                              done(!stale, stale ? "stale names/message leaked from a previous delete: " + JSON.stringify(ActionState.pendingDeleteNames) + " / " + confirm.message
                                                  : "cancel + multi-select + trash-send + permanent-delete, no stale state, all via the real ConfirmDialog")
                            })
                          }
                        })
                      })
                    })
                  })
                })
              })
            })
          })
        })

        sc.add("Large Trash (50 items) navigates via real UI path without stalling", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var names = []
          for (var i = 0; i < 50; i++) names.push(sc.opsDir + "/bulk-trash-" + Date.now() + "-" + i + ".txt")

          var i2 = 0
          function copyNext() {
            if (i2 >= names.length) { trashAll(); return }
            Backend.FileOperations.copy(sc.note, names[i2])
            sc._fileOp(done, function () { i2++; copyNext() })
          }
          var j = 0
          function trashAll() {
            if (j >= names.length) { navigate(); return }
            Backend.FileOperations.trash(names[j])
            sc._fileOp(done, function () { j++; trashAll() })
          }
          function navigate() {
            var responsive = false
            var t = Qt.createQmlObject('import QtQuick; Timer { interval: 30; repeat: false }', sc)
            t.triggered.connect(function () { responsive = true })
            var startedAt = Date.now()
            c.commandFacade.openBookmark({ path: Paths.trashDir, type: "dir" })
            t.start()
            sc._poll(function () { return NavState.currentPath === Paths.trashDir && responsive }, function (ok) {
              t.destroy()
              var ms = Date.now() - startedAt
              NavState.currentPath = prevPath
              done(ok, ok ? ("navigated into a 50-item Trash in " + ms + "ms, event loop stayed responsive")
                          : "event loop appears blocked navigating a large Trash")
            })
          }
          copyNext()
        })

        // V1_1_P0_TRASH_FREEZE regression: the three tests above (real UI
        // path, repeated navigation, 50-item Trash) all passed BEFORE this
        // fix, because the dev/CI machine's mounts are all fast -- the bug
        // only manifests when discoverTrashRoots()'s per-mount stat() is
        // slow (a spun-down disk, a stalled network/FUSE mount), which none
        // of them simulate. This one does, via the OMAFILES_SELFCHECK_SLOW_
        // TRASH_MOUNT_MS hook in FileOpsPrivate.h::discoverTrashRoots() --
        // against the OLD synchronous trashRoots()/trashInfo() this made
        // the whole UI thread block for the delay (event loop dead, this
        // test's own 30ms timer never ticks, exactly the freeze reproduced
        // live via a real sidebar click + gdb-held breakpoint, see
        // docs/audits/V1_1_P0_TRASH_FREEZE_REPORT.md); against the fixed,
        // async requestTrashRoots()/requestTrashInfo() the delay only holds
        // a QThreadPool worker, and the event loop keeps ticking throughout.
        sc.add("Trash navigation stays responsive when a mount's stat() is slow (V1_1_P0_TRASH_FREEZE regression)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var SLOW_MS = 2500

          function cleanupEnv() { Backend.Env.set("OMAFILES_SELFCHECK_SLOW_TRASH_MOUNT_MS", "0") }

          Backend.Env.set("OMAFILES_SELFCHECK_SLOW_TRASH_MOUNT_MS", String(SLOW_MS))

          var ticks = 0
          var t = Qt.createQmlObject('import QtQuick; Timer { interval: 30; repeat: true }', sc)
          t.triggered.connect(function () { ticks++ })
          var startedAt = Date.now()
          t.start()
          // Same real click the sidebar bookmark row makes (CommandFacade.openBookmark).
          c.commandFacade.openBookmark({ path: Paths.trashDir, type: "dir" })

          // Wait out the simulated-slow-mount window by WALL CLOCK, not by
          // app state: NavState.currentPath flips to Paths.trashDir almost
          // immediately (NavigationController._goToPath sets it before the
          // now-async listing even starts), so polling on it alone would
          // resolve long before the delay we're actually trying to observe
          // has elapsed. If the UI thread is blocked (the pre-fix bug),
          // BOTH this poll's own timer and the ticks timer stall together
          // and only resume once whatever is blocking the thread releases
          // it -- so this still terminates either way, it just reports few
          // or no ticks when the bug is present.
          sc._poll(function () { return Date.now() - startedAt >= SLOW_MS + 250 }, function () {
            t.stop()
            t.destroy()
            var ms = Date.now() - startedAt
            var arrived = (NavState.currentPath === Paths.trashDir)
            NavState.currentPath = prevPath
            cleanupEnv()
            // A responsive event loop ticks ~(SLOW_MS/30) times while
            // waiting; a blocked one ticks 0 (or a couple, right as it
            // unblocks) -- 5 is a conservative floor, robust to jitter.
            var ok = arrived && ticks >= 5
            done(ok, ok
                ? ("event loop kept ticking (" + ticks + " ticks) during a " + SLOW_MS + "ms simulated slow mount, " + ms + "ms elapsed")
                : ("event loop appears to have blocked: only " + ticks + " ticks in " + ms + "ms (arrived=" + arrived + ")"))
          })
        })

        // Post-P0 sanity-audit finding: TrashState.trashInfo is populated
        // asynchronously now (requestTrashInfo), and NavState.currentPath
        // flips to trashDir synchronously, ahead of it -- so there's a real
        // window (e.g. rapidly re-entering Trash) where "are we in Trash"
        // is already true but TrashState.trashInfo hasn't caught up yet for
        // some or all items. restoreFromTrash()/confirmDelete() used to
        // build their native call from TrashState.trashInfo[name] with no
        // guard beyond "if missing, silently drop this name" -- with a
        // missing entry that meant a silent no-op, no error, no feedback.
        // Reproduces the missing-entry condition DETERMINISTICALLY (strip
        // one real entry out of the shared map) rather than racing real
        // async timing, and asserts the fixed behavior: no crash, and
        // critically no effect -- the trashed file is still exactly where
        // it was, proving the guard actually prevented the native call
        // rather than merely swallowing an exception from a bad path.
        sc.add("Restore/permanent-delete no-op safely when TrashState.trashInfo lacks the entry (post-P0 sanity audit)", function (done) {
          var c = sc._content
          if (!c || !c.actionEngine) { done(false, "no composition root"); return }
          var prevPath = NavState.currentPath
          var work = sc.opsDir + "/gap-race-" + Date.now() + ".txt"
          var wname = work.substring(work.lastIndexOf("/") + 1)

          Backend.FileOperations.copy(sc.note, work)
          sc._fileOp(done, function () {
            Backend.FileOperations.trash(work)
            sc._fileOp(done, function () {
              c.commandFacade.openBookmark({ path: Paths.trashDir, type: "dir" })
              sc._poll(function () { return sc._has(NavState.visibleEntries, wname) && TrashState.trashInfo[wname] !== undefined },
                function (ready) {
                  if (!ready) { done(false, "trashed item never fully listed with its info"); return }

                  var entries = NavState.visibleEntries
                  var idx = -1
                  for (var i = 0; i < entries.length; i++) if (entries[i].name === wname) idx = i
                  if (idx < 0) { done(false, "couldn't find the item to select"); return }
                  SelectionState.selectOnly(idx)

                  var origInfo = TrashState.trashInfo[wname]
                  var trashedFilePath = origInfo.trashRoot + "/files/" + wname
                  var savedInfo = TrashState.trashInfo
                  var stripped = {}
                  for (var k in savedInfo) if (k !== wname) stripped[k] = savedInfo[k]
                  TrashState.trashInfo = stripped // deterministically reproduce the missing-entry condition

                  var threw = false
                  try {
                    c.actionEngine.restoreFromTrash()
                    ActionState.pendingDeleteNames = [wname]
                    c.actionEngine.confirmDelete()
                  } catch (e) { threw = true }
                  ActionState.pendingDeleteNames = []

                  var untouched = Backend.FileOperations.existingPaths([trashedFilePath]).length === 1
                  TrashState.trashInfo = savedInfo // restore for cleanup below
                  NavState.currentPath = prevPath

                  var ok = !threw && untouched
                  done(ok, ok
                      ? "guarded no-op: no exception, trashed file untouched"
                      : "threw=" + threw + " untouched=" + untouched + " (guard failed to prevent acting on missing info)")
                })
            })
          })
        })

        sc.add("Conflict detection: existingPaths (file/dir/symlink)", function (done) {
          var f = sc.opsDir + "/cd-file.txt"
          var d = sc.opsDir + "/cd-dir"
          var l = sc.opsDir + "/cd-link"
          var missing = sc.opsDir + "/cd-missing-" + Date.now()
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.note, f) },
            function () { Backend.FileOperations.copy(sc.listDir, d) },
            function () { Backend.FileOperations.copy(sc.dir + "/link.txt", l) }
          ], done, function () {
            var res = Backend.FileOperations.existingPaths([f, d, l, missing])
            var ok = res.length === 3 && res.indexOf(f) >= 0 && res.indexOf(d) >= 0 &&
                     res.indexOf(l) >= 0 && res.indexOf(missing) < 0
            done(ok, "detected " + res.length + "/3 (without the nonexistent one)")
          })
        })

        sc.add("Copy conflict overwrite (directory replaces)", function (done) {
          var src = sc.opsDir + "/ccd-src"
          var dst = sc.opsDir + "/ccd-dst"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.listDir, src) },
            function () { Backend.FileOperations.mkdir(dst) },
            function () { Backend.FileOperations.copy(src, dst, true) }
          ], done, function () {
            sc._listOnce(dst, function (e) {
              done(e.length === 4 && sc._has(e, "sub"), "dir replaced: " + e.length + " entries")
            })
          })
        })

        sc.add("Copy conflict without overwrite errors (skip semantics)", function (done) {
          var dst = sc.opsDir + "/ccs.txt"
          sc._seqOps([function () { Backend.FileOperations.copy(sc.note, dst) }], done, function () {
            function onErr(op, path, msg) { cleanup(); done(msg.indexOf("exists") >= 0, "error: " + msg) }
            function onFin(op, path) { cleanup(); done(false, "should not copy over existing without overwrite") }
            function cleanup() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
            Backend.FileOperations.error.connect(onErr)
            Backend.FileOperations.finished.connect(onFin)
            Backend.FileOperations.copy(sc.note, dst)
          })
        })

        sc.add("Move conflict without overwrite errors (skip semantics)", function (done) {
          var work = sc.opsDir + "/mcs-work.txt"
          var dst = sc.opsDir + "/mcs-dst.txt"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.note, work) },
            function () { Backend.FileOperations.copy(sc.note, dst) }
          ], done, function () {
            function onErr(op, path, msg) { cleanup(); done(msg.indexOf("exists") >= 0, "error: " + msg) }
            function onFin(op, path) { cleanup(); done(false, "should not move over existing without overwrite") }
            function cleanup() { Backend.FileOperations.error.disconnect(onErr); Backend.FileOperations.finished.disconnect(onFin) }
            Backend.FileOperations.error.connect(onErr)
            Backend.FileOperations.finished.connect(onFin)
            Backend.FileOperations.move(work, dst)
          })
        })

        sc.add("Conflict overwrite replaces symlink dest", function (done) {
          var l = sc.opsDir + "/cos-link"
          sc._seqOps([
            function () { Backend.FileOperations.copy(sc.dir + "/link.txt", l) },
            function () { Backend.FileOperations.copy(sc.note, l, true) }
          ], done, function () {
            sc._listOnce(sc.opsDir, function (e) {
              var isFileNow = false
              for (var i = 0; i < e.length; i++)
                if (e[i].name === "cos-link") isFileNow = (!e[i].link || e[i].link.length === 0)
              done(isFileNow, isFileNow ? "symlink replaced by file" : "still a symlink")
            })
          })
        })
  }
}

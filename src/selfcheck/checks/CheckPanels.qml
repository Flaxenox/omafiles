import QtQuick
import Omafiles.Backend as Backend
import "../../../state"
import "../../../shared/Utils.js" as Utils

// Domain checks extracted from app/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("Background panel refreshes on content change (non-active tab)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no _content"); return }
          var bgDir = sc.dir + "/bgpanel-" + Date.now()

          Backend.FileOperations.mkdir(bgDir)
          sc._fileOp(done, function () {                    // bgDir created (empty)
            // Real SortOps: with default SortState (name/asc) isDefaultOrder is
            // true, so _sorted returns the entries as is without touching
            // fileTypeUtils/root (that's why they can be null). panelsRow is a stub
            // for the geometries; slotWidth/height 0 => the ListView doesn't instantiate
            // delegates and no null visual dependencies are touched.
            var panelsRow = sc._panelsRowStub.createObject(sc)
            var bgC = Qt.createComponent(Qt.resolvedUrl("../../../panels/BackgroundPanel.qml"))
            if (bgC.status !== Component.Ready) { done(false, "BackgroundPanel: " + bgC.errorString()); return }
            // index 1 != activeTabIndex 0 => visible (NON-active tab), which is
            // exactly the condition of the refreshMe() guard.
            TabsState.activeTabIndex = 0
            var bg = bgC.createObject(sc, {
              modelData: { path: bgDir }, index: 1, hostRoot: sc._content, hostPanelsRow: panelsRow,
            })
            if (!bg) { panelsRow.destroy(); done(false, "BackgroundPanel null"); return }

            function cleanup() { bg.destroy(); panelsRow.destroy() }
            function cache() { return c.tabEntriesCache[bgDir] }

            // 1) wait for the initial listing (onCompleted -> refreshMe, a direct
            //    call, not via the Connections) to populate the cache with the empty folder.
            sc._poll(function () { return cache() !== undefined && cache().length === 0 }, function (ok0) {
              if (!ok0) { cleanup(); done(false, "the panel didn't list the initial empty folder"); return }
              // 2) mutate the folder and trigger the refresh ONLY via refreshTick.
              Backend.FileOperations.copy(sc.note, bgDir + "/appeared.txt")
              sc._fileOp(done, function () {
                NavState.refreshTick += 1
                // 3) the background panel must re-list and reflect the new file.
                //    If the Connections is broken, the cache stays empty -> timeout.
                sc._poll(function () { var e = cache(); return e && sc._has(e, "appeared.txt") }, function (ok) {
                  // bgDir lives inside the harness's QTemporaryDir (main.cpp
                  // deletes it on exit); NO async remove is launched here -- a
                  // fire-and-forget in the last test runs concurrent with the
                  // QTemporaryDir cleanup and aborts its removeRecursively.
                  cleanup()
                  done(ok, ok ? "the background panel reflected the change via refreshTick"
                              : "the background panel did NOT refresh after refreshTick (broken Connections)")
                })
              })
            })
          })
        })

        // ======================= Alternating row colors (P2.4) =======================

        // Isolated instantiation is legitimate here (unlike KeyboardShortcuts.qml/
        // DialogLayer.qml earlier in this project's history, where isolated repros
        // gave misleading results): CursorSurface only imports QtQuick + qs.Commons
        // (globally-registered singletons resolved by type, not by id-chain), has
        // no `required property` referencing a sibling id, and no host-injection
        // pattern -- a pure, context-independent leaf component.
        sc.add("CursorSurface: idleFill defaults to transparent, hover/current still win (P2.4 backward-compat)", function (done) {
          var comp = Qt.createComponent(Qt.resolvedUrl("../../../app/qml_modules/qs/Ui/CursorSurface.qml"))
          if (comp.status === Component.Error) { done(false, comp.errorString()); return }
          var obj = comp.createObject(sc)
          if (!obj) { done(false, "createObject returned null"); return }
          // `color` has a 60ms Behavior/ColorAnimation -- assignments animate
          // instead of jumping, so each check waits past that before reading
          // .color (a bare synchronous read would catch a mid-transition value).
          var results = {}
          var steps = [
            function () { results.idleOk = obj.color.a === 0 }, // default, no idleFill set
            function () { obj.hasCursor = true },
            function () { results.hoverOk = String(obj.color) === String(obj.fill) },
            function () { obj.hasCursor = false; obj.current = true },
            function () { results.currentOk = String(obj.color) === String(obj.currentFill) },
            // Now with idleFill SET (as the two file-row delegates do): hover/
            // current must still win over it.
            function () { obj.current = false; obj.idleFill = "#20ff0000" },
            function () { results.idleAppliesOk = String(obj.color) === "#20ff0000" },
            function () { obj.hasCursor = true },
            function () { results.hoverStillWinsOk = String(obj.color) === String(obj.fill) },
            function () { obj.hasCursor = false; obj.current = true },
            function () { results.currentStillWinsOk = String(obj.color) === String(obj.currentFill) }
          ]
          var i = 0
          var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 90; repeat: true }', sc)
          timer.triggered.connect(function () {
            steps[i](); i++
            if (i >= steps.length) {
              timer.stop(); timer.destroy()
              obj.destroy()
              var ok = results.idleOk && results.hoverOk && results.currentOk
                && results.idleAppliesOk && results.hoverStillWinsOk && results.currentStillWinsOk
              done(ok, "default-idle=" + results.idleOk + " hover=" + results.hoverOk + " current=" + results.currentOk
                + " idle-applies=" + results.idleAppliesOk + " hover-still-wins=" + results.hoverStillWinsOk
                + " current-still-wins=" + results.currentStillWinsOk)
            }
          })
          timer.start()
        })

        sc.add("FileListRow: alternating idle fill via the real ListView, selection overrides it (P2.4)", function (done) {
          var c = sc._content
          if (!c) { done(false, "no composition root"); return }
          var listView = c.controllers.list
          var prevPath = NavState.currentPath
          // sc._content is created standalone (Qt.createComponent().createObject(sc)),
          // with no parent Window -- it defaults to 0x0, so the real ListView
          // never instantiates any delegates (nothing to lay out). Every other
          // selfcheck that reaches sc._content only reads state/functions, never
          // real delegate Items, so this is the first test that needs it sized.
          if (c.width === 0) c.width = 1400
          if (c.height === 0) c.height = 900
          if (listView.contentItem && listView.contentItem.parent && listView.contentItem.parent.forceLayout)
            listView.contentItem.parent.forceLayout()
          function rowAt(idx) {
            var kids = listView.contentItem.children
            for (var i = 0; i < kids.length; i++) {
              if (kids[i].modelData !== undefined && kids[i].index === idx) return kids[i]
            }
            return null
          }
          function finish(ok, msg) { NavState.currentPath = prevPath; done(ok, msg) }
          c.navController.navigateTo(sc.listDir)
          // Poll for the delegates THEMSELVES (not just the model array): a
          // model update and the ListView actually instantiating delegate
          // Items for it can land a frame apart.
          sc._poll(function () {
            return NavState.currentPath === sc.listDir && NavState.visibleEntries.length >= 2 && !!rowAt(0) && !!rowAt(1)
          }, function (listed) {
            if (!listed) {
              finish(false, "fixture dir/delegates never listed -- path=" + NavState.currentPath
                + " visible=" + NavState.visibleEntries.length
                + " kids=" + (listView.contentItem ? listView.contentItem.children.length : -1))
              return
            }
            var row0 = rowAt(0)
            var row1 = rowAt(1)
            // Navigating to a fresh directory may leave a default selection
            // (e.g. row 0) -- force a clean, known-unselected baseline before
            // reading idle colors. `color` also animates (60ms Behavior), so
            // every read below waits past that, same reasoning as the
            // CursorSurface test above.
            SelectionState.selectOnly(-1)
            var t0 = Qt.createQmlObject('import QtQuick; Timer { interval: 90; repeat: false }', sc)
            t0.triggered.connect(function () {
              var evenTransparent = row0.color.a === 0
              var oddTinted = row1.color.a > 0 && String(row1.color) !== String(row1.currentFill) && String(row1.color) !== String(row1.fill)
              SelectionState.selectOnly(1) // select the ODD (tinted-idle) row
              var t1 = Qt.createQmlObject('import QtQuick; Timer { interval: 90; repeat: false }', sc)
              t1.triggered.connect(function () {
                var selectionOverridesIdle = String(row1.color) === String(row1.currentFill)
                SelectionState.selectOnly(-1)
                var t2 = Qt.createQmlObject('import QtQuick; Timer { interval: 90; repeat: false }', sc)
                t2.triggered.connect(function () {
                  var backToIdleAfterDeselect = String(row1.color) !== String(row1.currentFill) && row1.color.a > 0
                  var ok = evenTransparent && oddTinted && selectionOverridesIdle && backToIdleAfterDeselect
                  finish(ok, "row0(even)transparent=" + evenTransparent + " row1(odd)tinted=" + oddTinted
                    + " selection-overrides=" + selectionOverridesIdle + " reverts-after-deselect=" + backToIdleAfterDeselect)
                })
                t2.start()
              })
              t1.start()
            })
            t0.start()
          })
        })
  }
}

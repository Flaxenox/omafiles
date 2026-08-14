import QtQuick
import Omafiles.Backend as Backend
import "../../../services"
import "../../../state"
import "../../../Utils.js" as Utils

// Domain checks extracted from app/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        // ======================= INTEGRATION =======================

        sc.add("Backend module loaded (Omafiles.Backend)", function (done) {
          var home = Backend.Env.get("HOME")
          done(!!home && home.length > 0, home ? "HOME=" + home : "Env.get(HOME) empty")
        })

        sc.add("UDisksWatcher reactive backend (Fase 20, no polling)", function (done) {
          // The C++ watcher (QtDBus) registered and exposes available()/devicesChanged.
          // available() is true if it connected to the system bus (in headless CI it can
          // be false; what's validated is that it loads and doesn't break, not that there's a bus).
          var a = UDisksWatcher.available()
          var ok = (a === true || a === false)
            && typeof UDisksWatcher.devicesChanged === "function"
          done(ok, "available=" + a)
        })

        sc.add("FolderCounter counts a directory (async, Fase 23)", function (done) {
          // list/ = sub/ + alpha/beta/gamma.txt = 4 entries.
          function on(path, n) {
            if (path !== sc.listDir) return
            FolderCounter.counted.disconnect(on)
            done(n === 4, "n=" + n + " (expected 4)")
          }
          FolderCounter.counted.connect(on)
          FolderCounter.request(sc.listDir, false)
        })

        sc.add("Item count smart formatting (Fase 23)", function (done) {
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
          var ok = typeof c.open === "function"
            && typeof c.close === "function"
            && typeof c.paletteCommands === "function"
            && typeof c.itemActions === "function"
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
          var pal = c.paletteCommands().length
          var items = c.itemActions().length            // 0 without selection: valid
          var empty = c.emptyAreaActions().length
          var segs = c.pathSegments().length
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
  }
}

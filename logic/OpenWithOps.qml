import "../Utils.js" as Utils
import QtQuick
import "../state"
import "../services"

// "Open with..." dialog -- twenty-first component extracted from
// core.
Item {
  property Item root: null
  property Item bookmarkOps: null

  function showOpenWith(entry) {
    if (!entry || entry.type === "dir") return
    PreviewState.openWithEntry = entry
    PreviewState.openWithApps = []
    openWithProc.start([Paths.resourceDir + "/open-with-list.sh", Utils.entryPath(NavState.currentPath, entry)])
    PreviewState.openWithOpen = true
  }

  function launchWith(desktopId) {
    if (PreviewState.openWithEntry) {
      var openPath = Utils.entryPath(NavState.currentPath, PreviewState.openWithEntry)
      Detached.run(["gtk-launch", desktopId, openPath])
      bookmarkOps.addRecent(openPath, PreviewState.openWithEntry.name)
    }
    PreviewState.openWithOpen = false
    PreviewState.openWithEntry = null
  }

  function parseOpenWithApps(text) {
    var lines = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
    return lines.map(function (l) {
      var parts = l.split("\t")
      return { name: parts[0], id: parts[1] }
    })
  }

  ProcessRunner {
    id: openWithProc
    onFinished: function (result) { PreviewState.openWithApps = parseOpenWithApps(result.stdout) }
  }
}

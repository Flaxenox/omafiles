import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Diálogo "Abrir con..." -- vigésimo primer componente extraído de
// Omafiles.qml.
Item {
  property Item root: null

  function showOpenWith(entry) {
    if (!entry || entry.type === "dir") return
    root.openWithEntry = entry
    root.openWithApps = []
    openWithProc.command = [root.pluginDir + "/open-with-list.sh", root.joinPath(root.currentPath, entry.name)]
    openWithProc.running = true
    root.openWithOpen = true
  }

  function launchWith(desktopId) {
    if (root.openWithEntry) {
      var openPath = root.joinPath(root.currentPath, root.openWithEntry.name)
      Quickshell.execDetached(["gtk-launch", desktopId, openPath])
      root.addRecent(openPath, root.openWithEntry.name)
    }
    root.openWithOpen = false
    root.openWithEntry = null
  }

  function parseOpenWithApps(text) {
    var lines = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
    return lines.map(function (l) {
      var parts = l.split("\t")
      return { name: parts[0], id: parts[1] }
    })
  }

  Process {
    id: openWithProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.openWithApps = parseOpenWithApps(text)
    }
  }
}

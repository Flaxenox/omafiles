import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../state"

// Diálogo "Abrir con..." -- vigésimo primer componente extraído de
// Omafiles.qml.
Item {
  property Item root: null
  property Item bookmarkOps: null

  function showOpenWith(entry) {
    if (!entry || entry.type === "dir") return
    PreviewState.openWithEntry = entry
    PreviewState.openWithApps = []
    openWithProc.command = [root.pluginDir + "/open-with-list.sh", root.joinPath(root.currentPath, entry.name)]
    openWithProc.running = true
    PreviewState.openWithOpen = true
  }

  function launchWith(desktopId) {
    if (PreviewState.openWithEntry) {
      var openPath = root.joinPath(root.currentPath, PreviewState.openWithEntry.name)
      Quickshell.execDetached(["gtk-launch", desktopId, openPath])
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

  Process {
    id: openWithProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: PreviewState.openWithApps = parseOpenWithApps(text)
    }
  }
}

import "../Utils.js" as Utils
import QtQuick
import "../state"
import Omafiles.Backend as Backend

// "Open with..." dialog
Item {
  property Item root: null
  property Item bookmarkOps: null

  function showOpenWith(entry) {
    if (!entry || entry.type === "dir") return
    PreviewState.openWithEntry = entry
    
    var openPath = Utils.entryPath(NavState.currentPath, entry)
    PreviewState.openWithApps = Backend.MimeResolver.getAppsForFile(openPath)
    PreviewState.openWithOpen = true
  }

  function launchWith(desktopId) {
    if (PreviewState.openWithEntry) {
      var openPath = Utils.entryPath(NavState.currentPath, PreviewState.openWithEntry)
      Backend.MimeResolver.launchApp(desktopId, openPath)
      bookmarkOps.addRecent(openPath, PreviewState.openWithEntry.name)
    }
    PreviewState.openWithOpen = false
    PreviewState.openWithEntry = null
  }
}

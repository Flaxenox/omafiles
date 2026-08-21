import QtQuick
import "../state"
import Omafiles.Backend as Backend

// Resolves + polls git status for the CURRENT folder only (active panel,
// v1 scope cut). Two sequential `git` subprocess calls per folder via
// Backend.ProcessRunner -- already this codebase's established way to
// shell out (logic/MountActions.qml, logic/ArchiveBrowser.qml,
// logic/SearchBackend.qml, logic/VideoThumbnails.qml all do the same):
// rev-parse to resolve the repo root (cached, including negative "not a
// repo" results), then status --porcelain once per repo root.
// GitStatusState is a passive cache (never calls back into this file) --
// same split as FolderCountState/FolderCounter.
Item {
  id: root

  // FIFO of {folder, force} jobs still waiting on a rev-parse --
  // ProcessRunner only runs one thing at a time, and normal navigation
  // is not fast enough for this to ever grow past 1-2 entries in practice.
  property var _queue: []
  property string _stage: "" // "" | "toplevel" | "status"
  property string _pendingFolder: ""
  property string _pendingRepoRoot: ""
  property bool _pendingForce: false

  function ensureRequested(folderPath) {
    if (!GitStatusState.needsRepoLookup(folderPath)) return
    GitStatusState.markRepoPending(folderPath)
    _queue.push({ folder: folderPath, force: false })
    _drain()
  }

  // Forces a fresh status check for the CURRENT folder's already-known
  // repo (refreshTick fired -- content may have changed). Re-running the
  // (cheap, sub-ms) rev-parse too is simpler than threading the force
  // flag any deeper for what is a rare, non-hot path.
  function refreshCurrent() {
    _queue.push({ folder: NavState.currentPath, force: true })
    _drain()
  }

  function _drain() {
    if (proc.busy || _queue.length === 0) return
    var job = _queue.shift()
    _pendingFolder = job.folder
    _pendingForce = job.force
    _stage = "toplevel"
    proc.start(["git", "-C", _pendingFolder, "rev-parse", "--show-toplevel"])
  }

  function _parsePorcelain(raw) {
    var map = {}
    var parts = raw.split("\u0000")
    for (var i = 0; i < parts.length; i++) {
      var entry = parts[i]
      if (entry.length < 4) continue
      var xy = entry.slice(0, 2)
      var rel = entry.slice(3)
      // Renames ("R  new\0old\0") carry an extra -z field for the old
      // name right after -- skip it so it isn't misparsed as its own entry.
      if (xy.charAt(0) === "R" || xy.charAt(0) === "C") i++
      map[rel] = xy
    }
    return map
  }

  Backend.ProcessRunner {
    id: proc
    onFinished: function (result) {
      if (root._stage === "toplevel") {
        if (result.cancelled || result.exitCode !== 0) {
          GitStatusState.setRepoRoot(root._pendingFolder, "")
          root._stage = ""
          root._drain()
          return
        }
        var repoRoot = String(result.stdout || "").trim()
        GitStatusState.setRepoRoot(root._pendingFolder, repoRoot)
        if (GitStatusState.statusByRepo[repoRoot] !== undefined && !root._pendingForce) {
          root._stage = ""
          root._drain()
          return
        }
        root._pendingRepoRoot = repoRoot
        root._stage = "status"
        proc.start(["git", "-C", repoRoot, "status", "--porcelain=v1", "-z", "--untracked-files=all"])
        return
      }
      if (root._stage === "status") {
        if (!result.cancelled && result.exitCode === 0) {
          GitStatusState.setStatus(root._pendingRepoRoot, root._parsePorcelain(String(result.stdout || "")))
        }
        root._stage = ""
        root._drain()
      }
    }
  }

  Timer {
    id: refreshDebounce
    interval: 400
    repeat: false
    onTriggered: root.refreshCurrent()
  }

  Connections {
    target: NavState
    function onCurrentPathChanged() { root.ensureRequested(NavState.currentPath) }
    function onRefreshTickChanged() { refreshDebounce.restart() }
  }

  Component.onCompleted: root.ensureRequested(NavState.currentPath)
}

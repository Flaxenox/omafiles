pragma Singleton
import QtQuick

// Cache of git status per repo, keyed by repo root -- fed by the async
// path logic/GitStatusBackend.qml (which shells out to `git` via
// Backend.ProcessRunner); read by FileRowVisual/FileGridCell's git-status
// badge via statusFor()/statusForFolder(). Same "passive cache, logic/
// does the triggering" split as FolderCountState/FolderCounter -- this
// singleton never calls into ProcessRunner or GitStatusBackend itself.
//
// v1 scope cut: active panel only, one repo root resolved per visible
// folder (a nested repo/submodule inside a tracked folder doesn't get
// its own separate resolution). Known, accepted staleness: like
// FolderCountState, status is only re-checked on navigation/refreshTick
// of the CURRENT folder -- an edit made elsewhere in the same repo while
// browsing a different subfolder can go stale until the next refresh (no
// deep recursive fs-watching exists anywhere in this app today).
QtObject {
  id: root

  // folder path -> repo root ("" = confirmed NOT a repo), undefined = unknown
  property var repoRootByFolder: ({})
  // repo root -> { relPath: "XY" } (raw 2-char porcelain codes)
  property var statusByRepo: ({})
  property var _pendingFolders: ({})

  readonly property int _maxRepos: 32
  readonly property int _maxFolders: 128

  function needsRepoLookup(folderPath) {
    return repoRootByFolder[folderPath] === undefined && _pendingFolders[folderPath] !== true
  }
  function markRepoPending(folderPath) { _pendingFolders[folderPath] = true }

  function setRepoRoot(folderPath, repoRoot) {
    var m = Object.assign({}, repoRootByFolder)
    m[folderPath] = repoRoot
    delete _pendingFolders[folderPath]
    var keys = Object.keys(m)
    while (keys.length > _maxFolders) { delete m[keys[0]]; keys.shift() }
    repoRootByFolder = m
  }

  function setStatus(repoRoot, map) {
    var s = Object.assign({}, statusByRepo)
    s[repoRoot] = map
    var keys = Object.keys(s)
    while (keys.length > _maxRepos) { delete s[keys[0]]; keys.shift() }
    statusByRepo = s
  }

  // Collapses a raw 2-char porcelain XY code to one badge letter.
  // Priority when both columns disagree: conflict > added > deleted > modified.
  function codeFor(xy) {
    if (xy === "??") return "?"
    if (xy.indexOf("U") >= 0 || xy === "AA" || xy === "DD") return "U"
    if (xy.indexOf("A") >= 0) return "A"
    if (xy.indexOf("D") >= 0) return "D"
    if (xy.indexOf("M") >= 0 || xy.indexOf("R") >= 0 || xy.indexOf("C") >= 0) return "M"
    return ""
  }

  // Walks up from `fullPath` looking for the nearest ancestor with a
  // known repo-root resolution -- normally a single dictionary hit
  // (the row's own folder, NavState.currentPath, is always the one
  // actually requested/cached), not a real walk.
  function _repoRootFor(fullPath) {
    var p = fullPath
    while (true) {
      var r = repoRootByFolder[p]
      if (r !== undefined) return r || ""
      var slash = p.lastIndexOf("/")
      if (slash <= 0) return ""
      p = p.slice(0, slash)
    }
  }

  // Status of a single FILE (absolute path). "" = clean or no repo.
  function statusFor(fullPath) {
    var repoRoot = _repoRootFor(fullPath)
    if (!repoRoot) return ""
    var map = statusByRepo[repoRoot]
    if (!map) return ""
    var rel = fullPath === repoRoot ? "" : fullPath.slice(repoRoot.length + 1)
    var xy = map[rel]
    return xy ? codeFor(xy) : ""
  }

  // Aggregate ("worst") status under a FOLDER (absolute path) -- reduces
  // every cached entry whose relative path starts with this folder's
  // prefix. Same cost class as FolderCounter's existing per-visible-row work.
  function statusForFolder(fullPath) {
    var repoRoot = _repoRootFor(fullPath)
    if (!repoRoot) return ""
    var map = statusByRepo[repoRoot]
    if (!map) return ""
    var prefix = fullPath === repoRoot ? "" : fullPath.slice(repoRoot.length + 1) + "/"
    var priority = { "U": 4, "A": 3, "D": 2, "M": 1, "?": 0 }
    var best = ""
    var bestP = -1
    for (var rel in map) {
      if (prefix !== "" && rel.indexOf(prefix) !== 0) continue
      var code = codeFor(map[rel])
      var p = priority[code]
      if (p !== undefined && p > bestP) { bestP = p; best = code }
    }
    return best
  }
}

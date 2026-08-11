.pragma library

// Pure functions pulled out of Omafiles.qml (without references to "root" --
// a Qt6 .js module with ".pragma library" doesn't see the scope of the
// component that imports it, unlike Qt.include(), which in this
// engine simply fails). thumbKeyFor/videoThumbPath no longer accept
// optional basePath/cacheDir with implicit fallback to
// root.currentPath/root.thumbCacheDir -- the caller has to pass them
// always.

function formatSize(bytes) {
  if (bytes < 1024) return bytes + " B"
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " K"
  if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " M"
  return (bytes / 1024 / 1024 / 1024).toFixed(1) + " G"
}

// Thousands separator: 1234 -> "1,234".
function _withThousands(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

// Smart formatting of the per-folder item counter (Phase 23, josema):
//   <10k -> exact with thousands separator (1 item / 2 items / 1,234 items)
//   <1M  -> abbreviated 12.3k items
//   >=1M -> abbreviated 1.2M items
function formatItemCount(n) {
  if (typeof n !== "number" || n < 0) return ""
  if (n < 10000) return _withThousands(n) + (n === 1 ? " item" : " items")
  if (n < 1000000) return (n / 1000).toFixed(1).replace(/\.0$/, "") + "k items"
  return (n / 1000000).toFixed(1).replace(/\.0$/, "") + "M items"
}

// EXACT value (with thousands separator) for the tooltip when the counter is
// shown abbreviated: 12,347 items.
function formatItemCountExact(n) {
  if (typeof n !== "number" || n < 0) return ""
  return _withThousands(n) + (n === 1 ? " item" : " items")
}

// Is the displayed format abbreviated (k/M) and therefore worth a tooltip
// with the exact value?
function itemCountAbbreviated(n) {
  return typeof n === "number" && n >= 10000
}

function relativeTime(epochSeconds) {
  if (!epochSeconds) return ""
  var diff = Math.floor(Date.now() / 1000) - epochSeconds
  if (diff < 60) return "just now"
  if (diff < 3600) return Math.floor(diff / 60) + " min ago"
  if (diff < 86400) return Math.floor(diff / 3600) + " h ago"
  if (diff < 86400 * 30) return Math.floor(diff / 86400) + " d ago"
  if (diff < 86400 * 365) return Math.floor(diff / (86400 * 30)) + " mo ago"
  return Math.floor(diff / (86400 * 365)) + " yr ago"
}

// Compares numbers as numbers, not letter by letter -- without this
// "file2.txt" came after "file10.txt" (pure lexicographic: "1" <
// "2"), and the same with numbered dates/chapters/versions. A compact
// well-known algorithm (splits with a regex, compares chunk by chunk).
function naturalCompare(a, b) {
  var ax = [], bx = []
  a.replace(/(\d+)|(\D+)/g, function (_, d, s) { ax.push([d || Infinity, s || ""]) })
  b.replace(/(\d+)|(\D+)/g, function (_, d, s) { bx.push([d || Infinity, s || ""]) })
  while (ax.length && bx.length) {
    var an = ax.shift(), bn = bx.shift()
    var nn = (an[0] - bn[0]) || an[1].localeCompare(bn[1])
    if (nn) return nn
  }
  return ax.length - bx.length
}

// The on-disk cache-key hash lives in the C++ backend
// (ThumbnailProvider.cacheKey, SHA-1) and is the ONLY scheme in the project
// (Phase B1). Before there was a JS simpleHash here that coexisted with that SHA-1
// (two file-name formats for the same cache folder); it was
// removed. The cache paths are composed in QML by calling
// ThumbnailProvider.cacheKey (see VideoThumbnails.qml and ArchiveActions.qml).

// Joins a base directory and a name into an absolute path, treating "/"
// as a special case (avoids "//name"). Pure function; it was a wrapper of
// OmafilesContent (root.joinPath) that 45 sites called via the composition
// root's facade despite it not being its own (Phase 14.D): now it lives here, next to
// the rest of the pure utilities, and logic/ no longer depends on the root for this.
function joinPath(base, name) {
  return base === "/" ? "/" + name : base + "/" + name
}

// Absolute path of an ENTRY, resolve where it may. In a normal
// listing (or in the recursive fallback search) the entry only carries `name`
// relative to `base`, so it's joined with joinPath -- behavior identical to
// the usual. In the indexed GLOBAL search the entry already carries an absolute `path`
// (name is only the basename, it may come from any other folder): then
// that path is used as is. A single site so as not to couple the rest of the code
// to which backend produced the entry (see services/SearchBackend.qml).
function entryPath(base, entry) {
  return entry && entry.path ? entry.path : joinPath(base, entry.name)
}

// IN-MEMORY key of the VideoThumbState.videoThumbReady dict (path|mtime) --
// it's not a file hash, only a unique identifier per (video, mtime)
// to deduplicate requests and read the result. The on-disk cache file
// name is given by ThumbnailProvider.cacheKey (SHA-1), see
// VideoThumbnails.qml.
function thumbKeyFor(entry, basePath) {
  return joinPath(basePath, entry.name) + "|" + entry.mtime
}

// Compares two entry lists by CONTENT, cheap (O(n), without
// allocations). Phase 10.A: replaces JSON.stringify(a) !== JSON.stringify(b)
// -- which serialized ~330 KB per comparison and was done 4 times per refresh
// (measured at 74 ms over /usr/bin). Here only the fields that the
// UI can show and that would decide a relayout are traversed.
function entriesEqual(a, b) {
  if (a === b) return true
  if (!a || !b || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    var x = a[i], y = b[i]
    if (x.name !== y.name || x.type !== y.type || x.size !== y.size
        || x.mtime !== y.mtime || x.link !== y.link) return false
  }
  return true
}

// parseMounts is still alive: list-mounts.sh (device enumeration via
// lsblk/findmnt) is a "system adapter" that is NOT migrated (see BACKEND_DESIGN.md).
// The TSV it produces is parsed here. The NETWORK mounts, on the other hand, moved to a
// native backend (NetworkMounts) in Phase 16, so parseNetworkMounts was
// removed (there was no longer a consumer).
// Decodes a device label (Phase 20, josema). findmnt -r (raw
// mode, which list-mounts.sh uses to split fields by tab
// reliably) escapes spaces and UTF-8 as \xNN; some providers use %NN.
// The \xNN are converted to %NN and everything is decoded at once with
// decodeURIComponent, which is UTF-8-aware (equivalent to QUrl::fromPercentEncoding),
// so "Mafia\x20The\x20Old" -> "Mafia The Old" and "caf\xc3\xa9" -> "café".
function decodeDeviceLabel(s) {
  var raw = String(s || "")
  var pct = raw.replace(/\\x([0-9A-Fa-f]{2})/g, "%$1")
  try {
    return decodeURIComponent(pct)
  } catch (e) {
    // A loose % invalid for decodeURIComponent: decode only the \xNN.
    return raw.replace(/\\x([0-9A-Fa-f]{2})/g, function (_, h) {
      return String.fromCharCode(parseInt(h, 16))
    })
  }
}

function parseMounts(text) {
  var lines = String(text || "").split("\n").filter(function (l) { return l.length > 0 })
  return lines.map(function (l) {
    var parts = l.split("\t")
    // path also decoded: findmnt -r escapes the spaces of the mount
    // point (/run/media/.../Mafia\x20The\x20Old); without decoding, navigating to
    // the drive would fail (the real directory has spaces, not \x20).
    return { label: decodeDeviceLabel(parts[0]), path: decodeDeviceLabel(parts[1]), device: parts[2] || "", removable: parts[3] === "1", mounted: parts[4] !== "0", fstype: parts[5] || "" }
  })
}

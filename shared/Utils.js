.pragma library

// Common pure utility functions.

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

// Smart formatting of the per-folder item counter:
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

// Compares numbers as numbers, not letter by letter.
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

// Joins a base directory and a name into an absolute path, treating "/"
// as a special case (avoids "//name").
function joinPath(base, name) {
  return base === "/" ? "/" + name : base + "/" + name
}

// Absolute path of an entry. In a normal listing (or recursive search)
// the entry carries `name` relative to `base`. In indexed global search
// the entry carries an absolute `path`.
function entryPath(base, entry) {
  return entry && entry.path ? entry.path : joinPath(base, entry.name)
}

// In-memory key of the VideoThumbState.videoThumbReady dict (path|mtime).
function thumbKeyFor(entry, basePath) {
  return joinPath(basePath, entry.name) + "|" + entry.mtime
}

// Compares two entry lists by content, O(n) without allocations.
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

// File type extension lists and glyph/type helpers
var IMAGE_EXTS = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
var VIDEO_EXTS = ["mp4", "mkv", "webm", "avi", "mov", "flv", "m4v"]
var AUDIO_EXTS = ["mp3", "flac", "wav", "ogg", "m4a", "opus"]
var ARCHIVE_EXTS = ["zip", "tar", "gz", "xz", "rar", "7z", "bz2", "zst"]
var CODE_EXTS = ["js", "ts", "py", "lua", "sh", "c", "cpp", "h", "rs", "go", "html", "css", "json", "qml", "md", "yml", "yaml", "toml"]

function extOf(name) {
  var idx = (name || "").lastIndexOf(".")
  return idx > 0 ? name.substring(idx + 1).toLowerCase() : ""
}

function iconFor(entry) {
  if (!entry) return "󰈤"
  var ext = extOf(entry.name)
  if (ext === "iso") return "󰗮"
  // md-magnet, verified against the icon font's real cmap (rendered +
  // visually checked before use) -- the standard "torrent" association
  // (magnet links are the direct alternative to .torrent files for the
  // same protocol), and closer to what other file managers use for this
  // extension than a generic file glyph.
  if (ext === "torrent") return "\u{F0347}"
  if (IMAGE_EXTS.indexOf(ext) >= 0) return "󰺰"
  if (VIDEO_EXTS.indexOf(ext) >= 0) return "󰸬"
  if (AUDIO_EXTS.indexOf(ext) >= 0) return "󰸪"
  if (ARCHIVE_EXTS.indexOf(ext) >= 0) return "󰗄"
  if (ext === "pdf") return "󰈦"
  if (CODE_EXTS.indexOf(ext) >= 0) return "󱀫"
  return "󰈤"
}

function isImage(entry) {
  return !!entry && entry.type === "file" && IMAGE_EXTS.indexOf(extOf(entry.name)) >= 0
}

function isVideo(entry) {
  return !!entry && entry.type === "file" && VIDEO_EXTS.indexOf(extOf(entry.name)) >= 0
}

function isAudio(entry) {
  return !!entry && entry.type === "file" && AUDIO_EXTS.indexOf(extOf(entry.name)) >= 0
}

function isPdf(entry) {
  return !!entry && entry.type === "file" && extOf(entry.name) === "pdf"
}

// Pure name transformation shared by the real bulk-rename execution
// (logic/ActionEngine.qml, commitBulkRename) and its live preview
// (dialogs/BulkRenamePanel.qml) -- single source of truth so the preview
// can never show something different from what actually happens.
// entries: [{name, type}]. Returns [{oldName, newName}], same order/length
// as entries -- index i backs {n}. {n:W} zero-pads the sequence number to
// W digits (e.g. {n:3} -> "001", "002"...); bare {n} is unpadded, unchanged
// from before this was added.
// findRe/replace (V1.1, optional): a JS regex (as a string) applied to the
// base name -- ALL matches (the "g" flag is always added), before {name}/
// {ext}/{n} substitution -- so {n} still numbers by original selection
// order, not by anything the replace could have changed. `replace` supports
// the normal JS replacement syntax ($1, $&, ...). An invalid regex (typing
// in progress, e.g. an unbalanced paren) is treated the same as no find/
// replace at all -- silently skipped, never throws, so the live preview
// stays usable while the user is still typing it.
function bulkRenameNames(entries, pattern, findRe, replace) {
  var re = null
  if (findRe) {
    try { re = new RegExp(findRe, "g") } catch (e) { re = null }
  }
  return (entries || []).map(function (e, i) {
    var ext = e.type === "dir" ? "" : (extOf(e.name) ? "." + extOf(e.name) : "")
    var base = ext ? e.name.slice(0, -ext.length) : e.name
    if (re) {
      try { base = base.replace(re, replace || "") } catch (e2) { /* leave base as-is */ }
    }
    var newName = String(pattern || "")
      .replace(/\{name\}/g, base)
      .replace(/\{ext\}/g, ext)
      .replace(/\{n(?::(\d+))?\}/g, function (_, width) {
        var num = String(i + 1)
        return width ? num.padStart(parseInt(width, 10), "0") : num
      })
      .trim()
    return { oldName: e.name, newName: newName }
  })
}

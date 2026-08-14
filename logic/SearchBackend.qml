import QtQuick
import Omafiles.Backend as Backend

// GLOBAL search service. Abstracts three backends behind a SINGLE contract
// (search / cancel / results signal), identical to SearchWorker's, so the
// UI never knows which one responded:
//
//   1. System index -- scripts/search-index.sh (tracker3 -> plocate ->
//      locate). Fast, does NOT walk disk, returns ABSOLUTE paths.
//   2. Recursive SearchWorker (C++), ONLY if the script exits with code 2
//      (no index installed): walks from `fallbackRoot`, paths
//      RELATIVE to that folder. It is the degraded mode -- same result as
//      before this phase.
//
// The indexed entries carry {type,name(basename),path,parent,...} with an
// absolute path; the fallback ones keep {type,name(relative),...}. Utils
// .entryPath() unifies both for the rest of the code (thumbnails, open...).
//
// The relevance order is applied here by _rank() (not the script nor sortOps):
// exact > prefix > substring > path-only; on ties, shorter path and
// then alphabetical. It is what Nautilus/Spotlight expects: the "closest" to
// the term, on top.
Item {
  id: backend

  // Absolute path to the NAME index script. The caller sets it (logic/,
  // which does know Paths) so as not to couple services/ to state/.
  property string indexScript: ""
  // CONTENT search script (ripgrep). Fourth backend, triggered with
  // the `content:` prefix in the query (Phase 26 / Beta 3).
  property string contentScript: ""

  signal results(var entries, bool truncated)

  readonly property int maxResults: 200

  property string _query: ""
  property string _root: ""
  property bool _hidden: false
  // "name" (index/recursive) or "content" (ripgrep) -- fixes the parsing and whether there is
  // a recursive fallback (only in name).
  property string _mode: "name"

  // Coalescing of the IN-FLIGHT query. ProcessRunner.start() refuses if there is already
  // a live process (returns false), so typing fast would lose the
  // intermediate searches while the plocate of the first prefix (hundreds of
  // `stat` in bash, ~200ms) keeps running. Instead of queueing, we keep ONLY
  // the most recent query and cancel the current one; on its death (onFinished) the
  // pending one is relaunched. Result: fluid "search as you type", without accumulating
  // processes nor blocking -- it is what the assignment asked for ("cancel previous
  // searches, without blocking the UI").
  property bool _pending: false
  property string _pendingQuery: ""
  property string _pendingRoot: ""
  property bool _pendingHidden: false

  function search(query, showHidden, fallbackRoot) {
    if (indexProc.busy) {
      _pending = true
      _pendingQuery = query
      _pendingRoot = fallbackRoot
      _pendingHidden = showHidden
      indexProc.cancel() // the relaunch happens in onFinished(cancelled)
      recursive.cancel()
      return
    }
    _startNow(query, showHidden, fallbackRoot)
  }

  function _startNow(query, showHidden, fallbackRoot) {
    recursive.cancel() // cuts any recursive fallback still in progress
    _query = query
    _root = fallbackRoot
    _hidden = showHidden
    // CONTENT mode: `content:` prefix. The term goes after, without enclosing
    // quotes (`content:"foo bar"` -> foo bar). Searches INSIDE the files
    // of the fallbackRoot tree (the current folder), like `rg` in its cwd.
    if (query.indexOf("content:") === 0) {
      _mode = "content"
      var term = query.substring(8)
      if ((term.charAt(0) === '"' && term.charAt(term.length - 1) === '"')
          || (term.charAt(0) === "'" && term.charAt(term.length - 1) === "'"))
        term = term.substring(1, term.length - 1)
      if (term.length < 2) { // term too short: nothing to search yet
        backend.results([], false)
        return
      }
      indexProc.start([contentScript, term, fallbackRoot, String(maxResults + 1)])
      return
    }
    // NAME mode (system index). We request maxResults+1 to mark
    // truncated exactly (the script over-requests to compensate for the filtering).
    _mode = "name"
    indexProc.start([indexScript, query, String(maxResults + 1), showHidden ? "1" : "0"])
  }

  function cancel() {
    _pending = false
    indexProc.cancel()
    recursive.cancel()
  }

  Backend.ProcessRunner {
    id: indexProc
    onFinished: function (result) {
      if (backend._pending) {
        // It was cancelled to relaunch with the most recent query (coalescing).
        backend._pending = false
        backend._startNow(backend._pendingQuery, backend._pendingHidden, backend._pendingRoot)
        return
      }
      if (result.cancelled)
        return
      if (result.exitCode === 2) {
        // No backend available. In NAME: recursive from the current folder.
        // In CONTENT: ripgrep not installed, no fallback -> empty.
        if (backend._mode === "content")
          backend.results([], false)
        else
          recursive.search(backend._root, backend._query, backend._hidden)
        return
      }
      var parsed = backend._mode === "content"
        ? backend._parseContent(String(result.stdout || ""))
        : backend._rank(String(result.stdout || ""), backend._query)
      backend.results(parsed.entries, parsed.truncated)
    }
  }

  Backend.SearchWorker {
    id: recursive
    // Degraded mode: it is re-emitted as is (relative paths, without re-sorting).
    onResults: function (entries, truncated) {
      backend.results(entries, truncated)
    }
  }

  // Parses the TSV of content-search.sh ("PATH\tLINE\tSNIPPET" per line). The
  // order is given by ripgrep (tree walk); it is not re-sorted. Each line is an
  // independent result (the same file appears once per match,
  // with its line) -> jump to that specific line. It carries {line, snippet} extra.
  function _parseContent(stdout) {
    var lines = stdout.split("\n")
    var out = []
    for (var i = 0; i < lines.length && out.length < maxResults; i++) {
      var line = lines[i]
      if (line === "")
        continue
      var t1 = line.indexOf("\t")
      if (t1 < 0)
        continue
      var t2 = line.indexOf("\t", t1 + 1)
      if (t2 < 0)
        continue
      var path = line.substring(0, t1)
      var lineNo = parseInt(line.substring(t1 + 1, t2), 10) || 0
      var snippet = line.substring(t2 + 1)
      var slash = path.lastIndexOf("/")
      out.push({
        "type": "file",
        "name": slash >= 0 ? path.substring(slash + 1) : path,
        "path": path,
        "parent": slash > 0 ? path.substring(0, slash) : "/",
        "size": 0,
        "mtime": 0,
        "link": false,
        "line": lineNo,
        "snippet": snippet
      })
    }
    var truncated = out.length >= maxResults
    return { "entries": out, "truncated": truncated }
  }

  // Parses the script's TSV ("type\tABSOLUTE_PATH" per line) and sorts it by
  // relevance. Returns {entries, truncated}.
  function _rank(stdout, query) {
    var q = query.toLowerCase()
    var lines = stdout.split("\n")
    var scored = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line === "")
        continue
      var tab = line.indexOf("\t")
      if (tab < 0)
        continue
      var type = line.substring(0, tab)
      var path = line.substring(tab + 1)
      var slash = path.lastIndexOf("/")
      var name = slash >= 0 ? path.substring(slash + 1) : path
      var parent = slash > 0 ? path.substring(0, slash) : "/"
      var lname = name.toLowerCase()
      var score = 3
      if (lname === q)
        score = 0
      else if (lname.indexOf(q) === 0)
        score = 1
      else if (lname.indexOf(q) >= 0)
        score = 2
      scored.push({
        "type": type,
        "name": name,
        "path": path,
        "parent": parent,
        "size": 0,
        "mtime": 0,
        "link": false,
        "_score": score,
        "_len": path.length
      })
    }
    scored.sort(function (a, b) {
      if (a._score !== b._score)
        return a._score - b._score
      if (a._len !== b._len)
        return a._len - b._len
      return a.name.localeCompare(b.name)
    })
    var truncated = scored.length > backend.maxResults
    return {
      "entries": scored.slice(0, backend.maxResults),
      "truncated": truncated
    }
  }
}

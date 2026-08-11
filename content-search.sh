#!/usr/bin/env bash
# CONTENT search for the Omafiles magnifier (Phase 26 / Beta 3): searches a
# text INSIDE the files of the given tree with ripgrep, instead of by
# name. It's the fourth SearchBackend backend (content:), the one that removes the
# #1 reason to open the terminal to run `rg`.
#
# Usage:  content-search.sh <term> <root> [limit]
#   <root>  = folder to search from (recursive, like `rg` in a cwd).
#   <limit> = result cap (default 201).
#
# Output (stdout): one line per match, "PATH\tLINE\tSNIPPET".
#   PATH absolute, LINE number, SNIPPET the line's text trimmed.
# `rg --json` is used (robust against paths/texts with ':' or odd characters) and
# parsed with python3. ripgrep already respects .gitignore and skips .git/hidden, so
# node_modules and other noise are left out without extra filtering.
#
# Exit codes: 0 = ok (with or without results) · 2 = ripgrep not installed
# (sentinel: the QML side warns; there is NO native fallback for content).

set -uo pipefail

term=${1:-}
root=${2:-.}
limit=${3:-201}

[[ -z $term ]] && exit 0
command -v rg >/dev/null 2>&1 || { echo "backend=none" >&2; exit 2; }
echo "backend=ripgrep" >&2

# -F  fixed-string (literal, no regex: `content:main.cpp` searches that text as
#     is, not "main<anything>cpp"). -S smart-case. --max-columns avoids dumping
#     giant lines (minified). No --hidden: respect rg's default.
rg --json -F -S --max-columns 300 -- "$term" "$root" 2>/dev/null | python3 -c '
import json, sys
limit = int(sys.argv[1])
n = 0
for line in sys.stdin:
    if n >= limit:
        break
    try:
        o = json.loads(line)
    except Exception:
        continue
    if o.get("type") != "match":
        continue
    d = o["data"]
    path = d.get("path", {}).get("text")
    if not path:
        continue  # non-UTF8 (bytes) paths are ignored
    ln = d.get("line_number", 0)
    snippet = d.get("lines", {}).get("text", "")
    # a single line, without tabs (they break the TSV) nor newlines, trimmed
    snippet = snippet.replace("\t", " ").replace("\n", " ").replace("\r", " ").strip()
    if len(snippet) > 200:
        snippet = snippet[:200]
    sys.stdout.write("%s\t%d\t%s\n" % (path, ln, snippet))
    n += 1
' "$limit"
exit 0

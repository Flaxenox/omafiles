#!/usr/bin/env bash
# Indexed GLOBAL search for the Omafiles magnifier: queries the index that the
# system already maintains (doesn't walk the disk) and returns absolute paths.
#
# Backends, in order of preference (Priority 1/2 of the assignment):
#   1. Tracker (tracker3 / TinySPARQL)  -- the same engine as Nautilus.
#   2. plocate / locate                  -- lightweight path index.
# If there is NONE, it exits with code 2 (sentinel): the QML side then falls back to
# the recursive SearchWorker (Priority 3). NO index nor daemon of its own is created.
#
# Usage:  search-index.sh <query> [limit] [showHidden:0|1]
# Output (stdout): one line per result, "type\tABSOLUTE_PATH"
#   type = "dir" | "file"  (resolved with test -d, skipping phantom paths
#   from the index that no longer exist on disk). The relevance ordering is done by the
#   QML side (SearchBackend); here only the matches are listed.
# stderr: "backend=<name>" for diagnosis (which engine responded).

set -uo pipefail

query=${1:-}
limit=${2:-201}
show_hidden=${3:-0}

[[ -z $query ]] && exit 0

# Noise + hidden filtering.
#   - Noise ALWAYS out (even with showHidden): caches and huge dependency
#     trees that clutter any global search (node_modules,
#     .cache, .git, .pnpm). Tracker already excludes them from its index; with plocate
#     (which indexes EVERYTHING) they have to be filtered here so the useful results
#     don't get buried under thousands of cache paths.
#   - Hidden (without showHidden): filtered ONLY by the basename (the hidden
#     file/folder itself, e.g. ~/.bashrc), NOT by hidden parent folders
#     -- many apps live under ~/.local/share, ~/.config, etc. and should
#     be found anyway (Steam, Discord...).
filter_noise() {
  grep -vaE '/(node_modules|\.cache|\.git|\.pnpm|\.cargo|\.rustup)(/|$)'
}
filter_hidden() {
  if [[ $show_hidden == 1 ]]; then cat
  else awk -F/ '$NF !~ /^\./'; fi
}

# Converts a file:// URI (what Tracker emits) into a decoded local path.
uri_to_path() {
  sed -e 's|^file://||' | python3 -c 'import sys,urllib.parse
for line in sys.stdin:
    line=line.strip()
    if line: print(urllib.parse.unquote(line))' 2>/dev/null
}

emit_types() {
  # Reads paths from stdin and emits "type\tpath" for those that exist. `[ -d ]` is
  # a builtin (no fork), so 200 checks are cheap.
  local p
  while IFS= read -r p; do
    [[ -z $p ]] && continue
    if [[ -d $p ]]; then printf 'dir\t%s\n' "$p"
    elif [[ -e $p ]]; then printf 'file\t%s\n' "$p"
    fi
  done
}

# The index is over-fetched because the noise/hidden filtering and the
# phantom-path discard reduce the count; so the QML side has a
# wide pool to order by relevance and keep the best 200.
fetch=$(( limit * 4 ))
(( fetch > 1200 )) && fetch=1200

if command -v tracker3 >/dev/null 2>&1; then
  echo "backend=tracker3" >&2
  # `tracker3 search` prints headers + file:// URIs; we keep those.
  # Tracker already excludes caches from its index, but we pass the filters anyway.
  tracker3 search --limit "$fetch" -- "$query" 2>/dev/null \
    | grep -oE 'file://[^ ]+' | uri_to_path | filter_noise | filter_hidden | emit_types
  exit 0
fi

if command -v plocate >/dev/null 2>&1; then
  echo "backend=plocate" >&2
  plocate -i -l "$fetch" -- "$query" 2>/dev/null | filter_noise | filter_hidden | emit_types
  exit 0
fi

if command -v locate >/dev/null 2>&1; then
  echo "backend=locate" >&2
  locate -i -l "$fetch" -- "$query" 2>/dev/null | filter_noise | filter_hidden | emit_types
  exit 0
fi

# No indexed backend: the caller (SearchBackend.qml) uses SearchWorker.
echo "backend=none" >&2
exit 2

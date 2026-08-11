#!/bin/bash
# Lists the apps registered to open a file. TSV: name<TAB>.desktop id
# Language-independent: instead of parsing the "gio mime" headers
# (which change text depending on the locale), the tokens
# ending in .desktop are extracted directly from the whole output.

file="$1"
mimetype=$(xdg-mime query filetype "$file" 2>/dev/null)
[[ -n "$mimetype" ]] || exit 0

ids=$(gio mime "$mimetype" 2>/dev/null | grep -o '[A-Za-z0-9._-]*\.desktop' | sort -u)
[[ -n "$ids" ]] || exit 0

while IFS= read -r id; do
  desktop_file=""
  for dir in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
    [[ -f "$dir/$id" ]] && { desktop_file="$dir/$id"; break; }
  done
  [[ -n "$desktop_file" ]] || continue
  name=$(grep -m1 '^Name=' "$desktop_file" | cut -d= -f2-)
  [[ -n "$name" ]] || name="$id"
  printf '%s\t%s\n' "$name" "$id"
done <<<"$ids"

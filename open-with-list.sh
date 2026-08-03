#!/bin/bash
# Lista las apps registradas para abrir un fichero. TSV: nombre<TAB>id .desktop
# Independiente del idioma: en vez de parsear las cabeceras de "gio mime"
# (que cambian de texto según el locale), se extraen directamente los
# tokens que terminan en .desktop de toda la salida.

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

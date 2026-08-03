#!/bin/bash
# Lista el contenido de una carpeta como TSV: tipo<TAB>nombre<TAB>tamaño<TAB>mtime
# Carpetas primero, luego ficheros, cada grupo en orden alfabético -- el
# orden final que pida el usuario (nombre/tamaño/fecha/tipo) se aplica en
# QML, que ya tiene la lista completa en memoria y no necesita relanzar esto.
# $2 = "1" para incluir dotfiles (por defecto ocultos).

dir="$1"
show_hidden="${2:-0}"

# Códigos de salida distintos para que QML pueda avisar de verdad en vez de
# enseñar "0 items" tanto si la carpeta está vacía como si no se puede leer
# -- antes cd fallaba en silencio (2>/dev/null) y las dos situaciones eran
# indistinguibles para quien mira la lista.
[[ -e "$dir" ]] || exit 3
[[ -d "$dir" ]] || exit 4
[[ -r "$dir" && -x "$dir" ]] || exit 2
cd "$dir" 2>/dev/null || exit 1

shopt -s nullglob
[[ "$show_hidden" == "1" ]] && shopt -s dotglob

dirs=()
files=()
for entry in *; do
  [[ "$entry" == "." || "$entry" == ".." ]] && continue
  if [ -d "$entry" ]; then
    dirs+=("$entry")
  else
    files+=("$entry")
  fi
done

for d in "${dirs[@]}"; do
  mtime=$(stat -c%Y -- "$d" 2>/dev/null || echo 0)
  printf 'dir\t%s\t0\t%s\n' "$d" "$mtime"
done | sort -f -t $'\t' -k2,2

for f in "${files[@]}"; do
  read -r size mtime < <(stat -c '%s %Y' -- "$f" 2>/dev/null || echo "0 0")
  printf 'file\t%s\t%s\t%s\n' "$f" "$size" "$mtime"
done | sort -f -t $'\t' -k2,2

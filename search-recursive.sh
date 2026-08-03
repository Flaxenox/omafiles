#!/bin/bash
# Búsqueda recursiva bajo $1, filtrando por $2 (subcadena, insensible a
# mayúsculas) en el nombre de archivo/carpeta. Mismo formato TSV que
# list-dir.sh (tipo/nombre/tamaño/mtime) pero "nombre" aquí es la ruta
# relativa a $1, para que el resto del código (unir con currentPath,
# renombrar, borrar, abrir...) funcione sin cambios. Tope de 200
# resultados, ignora ocultos.

root="$1"
query="$2"
show_hidden="${3:-0}"
cd "$root" 2>/dev/null || exit 1
[[ -n "$query" ]] || exit 0

find_args=(-iname "*${query}*")
[[ "$show_hidden" != "1" ]] && find_args=(-not -path './.*' -not -path '*/.*' "${find_args[@]}")

find . "${find_args[@]}" 2>/dev/null | head -200 | while read -r p; do
  rel="${p#./}"
  [[ -z "$rel" ]] && continue
  if [ -d "$p" ]; then
    mtime=$(stat -c%Y -- "$p" 2>/dev/null || echo 0)
    printf 'dir\t%s\t0\t%s\n' "$rel" "$mtime"
  else
    read -r size mtime < <(stat -c '%s %Y' -- "$p" 2>/dev/null || echo "0 0")
    printf 'file\t%s\t%s\t%s\n' "$rel" "$size" "$mtime"
  fi
done

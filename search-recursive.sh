#!/bin/bash
# Búsqueda recursiva bajo $1, filtrando por $2 (subcadena, insensible a
# mayúsculas) en el nombre de archivo/carpeta. Mismo protocolo que
# list-dir.sh: 5 campos por entrada (tipo/nombre/tamaño/mtime/enlace,
# "enlace" siempre vacío aquí) separados por NUL, sin newline de por medio
# -- "nombre" aquí es la ruta relativa a $1, para que el resto del código
# (unir con currentPath, renombrar, borrar, abrir...) funcione sin cambios.
# find/head/read también van en modo NUL (-print0/-z/-d '') para que una
# ruta con un salto de línea dentro no se parta en dos entradas por el
# camino. Tope de 200 resultados, ignora ocultos. Se piden 201 a propósito
# (ver head más abajo): el lado QML usa ese resultado 201 solo para saber
# si hubo más de 200 y avisar de que la lista está incompleta, luego lo
# descarta.

root="$1"
query="$2"
show_hidden="${3:-0}"
cd "$root" 2>/dev/null || exit 1
[[ -n "$query" ]] || exit 0

find_args=(-iname "*${query}*")
[[ "$show_hidden" != "1" ]] && find_args=(-not -path './.*' -not -path '*/.*' "${find_args[@]}")

find . "${find_args[@]}" -print0 2>/dev/null | head -z -n 201 | while IFS= read -r -d '' p; do
  rel="${p#./}"
  [[ -z "$rel" ]] && continue
  if [ -d "$p" ]; then
    mtime=$(stat -c%Y -- "$p" 2>/dev/null || echo 0)
    printf 'dir\0%s\0%s\0%s\0%s\0' "$rel" "0" "$mtime" ""
  else
    read -r size mtime < <(stat -c '%s %Y' -- "$p" 2>/dev/null || echo "0 0")
    printf 'file\0%s\0%s\0%s\0%s\0' "$rel" "$size" "$mtime" ""
  fi
done

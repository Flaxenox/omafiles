#!/bin/bash
# Lista el contenido de una carpeta como TSV:
# tipo<TAB>nombre<TAB>tamaño<TAB>mtime<TAB>enlace
# Carpetas primero, luego ficheros, cada grupo en orden alfabético -- el
# orden final que pida el usuario (nombre/tamaño/fecha/tipo) se aplica en
# QML, que ya tiene la lista completa en memoria y no necesita relanzar esto.
# $2 = "1" para incluir dotfiles (por defecto ocultos).
# `enlace` = "broken" si es un symlink cuyo destino no existe, "valid" si es
# un symlink que sí resuelve, o vacío si no es un symlink -- ni -d/-f/stat
# distinguen esto (siguen el enlace, y con uno roto simplemente fallan en
# silencio), así que antes un symlink roto se veía como un fichero normal
# de 0 bytes fechado en 1970, sin ningún indicio real del problema.

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

link_state_of() {
  if [[ -L "$1" ]]; then
    [[ -e "$1" ]] && echo "valid" || echo "broken"
  fi
}

# Un `stat` por fichero (fork+exec cada vez) es lento en carpetas grandes --
# confirmado con /usr/bin (4197 entradas): más de 5 segundos reales. Un solo
# `stat` con TODOS los nombres a la vez es igual de correcto y ordenes de
# magnitud más rápido; los que fallan (symlinks rotos, con -L) simplemente
# no salen en su salida, así que solo hace falta el fallback individual de
# antes para esos pocos casos sueltos en vez de para todos.
declare -A dir_mtime
if ((${#dirs[@]})); then
  while IFS=$'\t' read -r mtime name; do
    dir_mtime["$name"]="$mtime"
  done < <(stat -Lc $'%Y\t%n' -- "${dirs[@]}" 2>/dev/null)
fi
for d in "${dirs[@]}"; do
  [[ -v dir_mtime["$d"] ]] && continue
  dir_mtime["$d"]=$(stat -c%Y -- "$d" 2>/dev/null || echo 0)
done

declare -A file_size file_mtime
if ((${#files[@]})); then
  while IFS=$'\t' read -r size mtime name; do
    file_size["$name"]="$size"
    file_mtime["$name"]="$mtime"
  done < <(stat -Lc $'%s\t%Y\t%n' -- "${files[@]}" 2>/dev/null)
fi
for f in "${files[@]}"; do
  [[ -v file_size["$f"] ]] && continue
  read -r size mtime < <(stat -c '%s %Y' -- "$f" 2>/dev/null || echo "0 0")
  file_size["$f"]="$size"
  file_mtime["$f"]="$mtime"
done

for d in "${dirs[@]}"; do
  printf 'dir\t%s\t0\t%s\t%s\n' "$d" "${dir_mtime[$d]}" "$(link_state_of "$d")"
done | sort -f -t $'\t' -k2,2

for f in "${files[@]}"; do
  printf 'file\t%s\t%s\t%s\t%s\n' "$f" "${file_size[$f]}" "${file_mtime[$f]}" "$(link_state_of "$f")"
done | sort -f -t $'\t' -k2,2

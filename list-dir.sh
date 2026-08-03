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

for d in "${dirs[@]}"; do
  # -L primero: para un symlink válido da la fecha de la carpeta real a la
  # que apunta (lo útil), no la del propio enlace. Solo cae al -c sin -L
  # (el enlace en sí) cuando el destino no existe -- un symlink roto no
  # tiene "carpeta real" de la que sacar fecha.
  mtime=$(stat -Lc%Y -- "$d" 2>/dev/null || stat -c%Y -- "$d" 2>/dev/null || echo 0)
  printf 'dir\t%s\t0\t%s\t%s\n' "$d" "$mtime" "$(link_state_of "$d")"
done | sort -f -t $'\t' -k2,2

for f in "${files[@]}"; do
  read -r size mtime < <(stat -Lc '%s %Y' -- "$f" 2>/dev/null || stat -c '%s %Y' -- "$f" 2>/dev/null || echo "0 0")
  printf 'file\t%s\t%s\t%s\t%s\n' "$f" "$size" "$mtime" "$(link_state_of "$f")"
done | sort -f -t $'\t' -k2,2

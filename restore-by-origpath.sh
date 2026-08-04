#!/bin/bash
# Restaura un ítem de papelera IDENTIFICADO POR SU RUTA ORIGINAL, no por
# nombre de fichero dentro de <raíz>/files (que puede llevar un sufijo
# si hubo colisión de nombres al borrar). Usado por el deshacer de
# "borrar a la papelera": justo después de un "gio trash" con éxito se
# sabe la ruta original exacta, pero no en qué papelera física acabó
# (casa vs. la .Trash-$UID de otro disco) ni con qué nombre si hubo
# colisión -- por eso se busca en TODAS las papeleras activas
# (trash-roots.sh) el .trashinfo cuyo Path= coincide exactamente,
# usando el más reciente si hay varios (mismo fichero borrado más de
# una vez).
#
# $1 = ruta original absoluta a restaurar

target="$1"
[[ -n "$target" ]] || exit 1
dir="$(dirname -- "$(readlink -f -- "$0")")"

best_info=""
best_mtime=-1
while IFS= read -r trash_root; do
  info_dir="$trash_root/info"
  [[ -d "$info_dir" ]] || continue
  shopt -s nullglob
  for f in "$info_dir"/*.trashinfo; do
    path_enc="$(sed -n 's/^Path=//p' -- "$f")"
    decoded="${path_enc//+/ }"
    decoded="$(printf '%b' "${decoded//%/\\x}" 2>/dev/null)"
    # Mismo matiz que trash-info.sh: Path= es relativo al punto de
    # montaje para cualquier papelera que no sea la de casa.
    [[ "$decoded" != /* ]] && decoded="$(dirname -- "$trash_root")/$decoded"
    [[ "$decoded" == "$target" ]] || continue
    mtime="$(stat -c%Y -- "$f" 2>/dev/null || echo 0)"
    if (( mtime > best_mtime )); then
      best_mtime="$mtime"
      best_info="$f"
    fi
  done
done < <(bash "$dir/trash-roots.sh")

if [[ -z "$best_info" ]]; then
  echo "No matching trashed item found for: $target" >&2
  exit 1
fi

name="$(basename -- "$best_info" .trashinfo)"
trash_root="$(dirname -- "$(dirname -- "$best_info")")"
src="$trash_root/files/$name"

if [[ ! -e "$src" && ! -L "$src" ]]; then
  echo "Trash file missing: $src" >&2
  exit 1
fi
if [[ -e "$target" || -L "$target" ]]; then
  echo "Destination already exists: $target" >&2
  exit 1
fi

mkdir -p -- "$(dirname -- "$target")" && mv -- "$src" "$target" && rm -f -- "$best_info"

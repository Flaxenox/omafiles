#!/bin/bash
# Lee ~/.local/share/Trash/info/*.trashinfo y emite, para cada uno, 3
# campos separados por NUL (mismo protocolo que list-dir.sh/
# search-recursive.sh): nombre del ítem (mismo stem que el fichero en
# Trash/files) / ruta original decodificada / fecha de borrado en epoch.
# Sin esto, la papelera de Omafiles era "una carpeta más" -- mostraba el
# mtime propio del fichero (el de antes de borrarlo) como si fuera la
# fecha de borrado, y no había forma de saber de dónde venía cada cosa
# sin mirar el .trashinfo a mano.
#
# $1 = directorio Trash/info (p.ej. ~/.local/share/Trash/info)

info_dir="$1"
[[ -d "$info_dir" ]] || exit 0

shopt -s nullglob
for f in "$info_dir"/*.trashinfo; do
  name="$(basename -- "$f" .trashinfo)"

  path_enc=""
  date_str=""
  while IFS= read -r line; do
    case "$line" in
      Path=*) path_enc="${line#Path=}" ;;
      DeletionDate=*) date_str="${line#DeletionDate=}" ;;
    esac
  done < "$f"

  # Path= va percent-encoded como una URI (RFC 3986) -- mismo decodificado
  # en bash puro que ya usa scripts/open-path.sh para file://.
  decoded="${path_enc//+/ }"
  decoded="$(printf '%b' "${decoded//%/\\x}" 2>/dev/null)"

  epoch="$(date -d "$date_str" +%s 2>/dev/null)"
  [[ -z "$epoch" ]] && epoch=0

  printf '%s\0%s\0%s\0' "$name" "$decoded" "$epoch"
done

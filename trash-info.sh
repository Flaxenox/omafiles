#!/bin/bash
# Lee */info/*.trashinfo de TODAS las papeleras activas (ver
# trash-roots.sh) y emite, para cada uno, 4 campos separados por NUL
# (mismo protocolo que list-dir.sh/search-recursive.sh): nombre (mismo
# stem que el fichero en <raíz>/files) / ruta original decodificada /
# fecha de borrado en epoch / raíz física de esa papelera concreta (la
# que contiene files/ e info/ -- p.ej. ~/.local/share/Trash o
# /mnt/Almacen/.Trash-1000). Ese 4º campo es lo que permite restaurar/
# borrar definitivamente apuntando a la papelera FÍSICA correcta en vez
# de asumir siempre la de casa, ahora que puede haber varias a la vez.
# Sin esto, la papelera de Omafiles era "una carpeta más" -- mostraba
# solo la de casa, y cualquier cosa borrada desde otro disco
# desaparecía de la vista aunque "gio trash" la hubiera movido bien a
# SU propia papelera (spec de XDG Trash).

dir="$(dirname -- "$(readlink -f -- "$0")")"

while IFS= read -r trash_root; do
  info_dir="$trash_root/info"
  [[ -d "$info_dir" ]] || continue

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

    # Path= va percent-encoded como una URI (RFC 3986) -- mismo
    # decodificado en bash puro que ya usa scripts/open-path.sh para
    # file://.
    decoded="${path_enc//+/ }"
    decoded="$(printf '%b' "${decoded//%/\\x}" 2>/dev/null)"

    # La papelera de casa guarda Path= ABSOLUTO, pero la de cualquier
    # otro punto de montaje (spec de XDG Trash, "$topdir/.Trash-$uid")
    # lo guarda RELATIVO a ESE punto de montaje, no a casa -- sin esto
    # "Descargas/x.zip" se mostraría/restauraría tal cual en vez de
    # resolverse contra /mnt/Almacen.
    if [[ "$decoded" != /* ]]; then
      decoded="$(dirname -- "$trash_root")/$decoded"
    fi

    epoch="$(date -d "$date_str" +%s 2>/dev/null)"
    [[ -z "$epoch" ]] && epoch=0

    printf '%s\0%s\0%s\0%s\0' "$name" "$decoded" "$epoch" "$trash_root"
  done
done < <(bash "$dir/trash-roots.sh")

exit 0

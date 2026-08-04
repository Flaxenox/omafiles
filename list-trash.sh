#!/bin/bash
# Listado agregado de TODAS las papeleras activas (ver trash-roots.sh):
# para cada raíz encontrada, reusa list-dir.sh tal cual sobre su
# "files/" -- mismo formato de 5 campos NUL-delimitados, simplemente
# concatenado. Omafiles.qml no distingue si esto vino de una sola
# carpeta o de varias, así que no hace falta tocar parseEntries() para
# esto.
#
# $1 = "1" para incluir dotfiles (se pasa tal cual a cada list-dir.sh)

show_hidden="${1:-0}"
dir="$(dirname -- "$(readlink -f -- "$0")")"

while IFS= read -r root; do
  [[ -d "$root/files" ]] && bash "$dir/list-dir.sh" "$root/files" "$show_hidden"
done < <(bash "$dir/trash-roots.sh")

exit 0

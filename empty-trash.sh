#!/bin/bash
# Vacía TODAS las papeleras activas (ver trash-roots.sh), no solo la de
# casa -- ahora que la vista de Papelera de Omafiles agrega varias, el
# botón de vaciar tiene que cubrir las mismas o dejaría cosas huérfanas
# que la app afirma haber vaciado.

dir="$(dirname -- "$(readlink -f -- "$0")")"
st=0
shopt -s nullglob dotglob
while IFS= read -r trash_root; do
  for f in "$trash_root/files"/* "$trash_root/info"/*.trashinfo; do
    [[ "$f" == */. || "$f" == */.. ]] && continue
    [[ -e "$f" || -L "$f" ]] || continue
    rm -rf -- "$f" || st=1
  done
done < <(bash "$dir/trash-roots.sh")
exit $st

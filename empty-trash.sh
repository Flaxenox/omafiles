#!/bin/bash
# Vacía TODAS las papeleras activas: la de casa (~/.local/share/Trash) más la
# .Trash-$UID de cualquier punto de montaje que la tenga (spec XDG Trash: un
# fichero borrado desde un disco que no es el de $HOME va a la papelera de ESE
# disco). Autocontenido: la Fase 16 migró el DESCUBRIMIENTO de raíces a
# FileOperations.trashRoots() (nativo) y borró trash-roots.sh, pero este script
# -- que hace el borrado EN BLOQUE con `rm -rf`, más simple que N remove
# nativos -- lo seguía llamando por dentro, así que no obtenía ninguna raíz y
# NO vaciaba nada (saliendo con éxito). Ahora descubre las raíces él mismo.

uid=$(id -u)
st=0
shopt -s nullglob dotglob

empty_root() {
  local trash_root="$1"
  for f in "$trash_root/files"/* "$trash_root/info"/*.trashinfo; do
    [[ "$f" == */. || "$f" == */.. ]] && continue
    [[ -e "$f" || -L "$f" ]] || continue
    rm -rf -- "$f" || st=1
  done
}

home_trash="$HOME/.local/share/Trash"
[[ -d "$home_trash" ]] && empty_root "$home_trash"

# .Trash-$UID de cada punto de montaje que no sea "/" ni antepasado de $HOME
# (esos ya son "el mismo disco que casa", cubiertos arriba).
while IFS= read -r mp; do
  [[ "$mp" == "/" ]] && continue
  [[ "$HOME" == "$mp"* ]] && continue
  cand="$mp/.Trash-$uid"
  [[ -d "$cand" ]] && empty_root "$cand"
done < <(findmnt -rn -o TARGET 2>/dev/null)

exit $st

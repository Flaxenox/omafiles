#!/bin/bash
# Imprime, un directorio por línea, cada raíz de papelera activa ahora
# mismo: la de casa (~/.local/share/Trash) siempre primero, más la
# .Trash-$UID de cualquier punto de montaje que la tenga. Spec de XDG
# Trash: un fichero borrado desde un disco que no es el de $HOME va a
# la papelera de ESE disco (evita copiar entre discos solo para
# borrar), no a la de casa -- Omafiles antes solo miraba la de casa,
# así que cualquier cosa borrada desde /mnt/lo-que-sea (o cualquier
# otro punto de montaje) desaparecía de la vista sin más, aunque
# "gio trash" la hubiera movido correctamente a SU papelera.
# Compartido por trash-info.sh y empty-trash.sh (el listado de la vista
# Papelera). Restaurar/enviar ya son nativos (FileOperations). Una sola
# raíces mirar".

uid=$(id -u)
home_trash="$HOME/.local/share/Trash"
[[ -d "$home_trash" ]] && printf '%s\n' "$home_trash"

findmnt -rn -o TARGET 2>/dev/null | while read -r mp; do
  [[ "$mp" == "/" ]] && continue
  # Cualquier punto de montaje que sea antepasado de $HOME es "el mismo
  # disco que casa" a efectos de papelera -- ya cubierto arriba.
  [[ "$HOME" == "$mp"* ]] && continue
  cand="$mp/.Trash-$uid"
  [[ -d "$cand" ]] && printf '%s\n' "$cand"
done
exit 0

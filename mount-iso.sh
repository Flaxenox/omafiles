#!/bin/bash
# Monta un .iso vía loop device (udisksctl loop-setup) y expone la ruta de
# montaje resultante. Imprime "Mounted X at Y." -- mismo formato que ya usa
# "udisksctl mount -b" a secas al montar una unidad normal, así
# Omafiles.qml parsea la ruta con la misma regex que ya tenía para
# mountProc, sin necesitar un formato de salida nuevo.
#
# $1 = ruta al .iso
set -e
iso="$1"
loopdev=$(udisksctl loop-setup --file="$iso" --no-user-interaction | sed -n 's/.* as \(\/dev\/loop[0-9]*\)\..*/\1/p')
[[ -n "$loopdev" ]] || exit 1

# Este sistema automonta el loop device en cuanto se crea (política de
# udisks2/gvfs de la sesión), pero es una carrera -- puede que ya esté
# montado para cuando se llega aquí, o que el automontaje lo monte justo
# mientras se ejecuta el "udisksctl mount" de abajo. En vez de comprobar
# antes (y dejar la misma carrera igual), se intenta montar y solo si
# falla se mira si fue justamente porque ya estaba montado.
if ! out=$(udisksctl mount -b "$loopdev" --no-user-interaction 2>&1); then
  if [[ "$out" == *AlreadyMounted* ]]; then
    mountpoint=$(findmnt -n -o TARGET "$loopdev" 2>/dev/null)
    [[ -n "$mountpoint" ]] || exit 1
    printf 'Mounted %s at %s.\n' "$loopdev" "$mountpoint"
  else
    printf '%s\n' "$out" >&2
    exit 1
  fi
else
  printf '%s\n' "$out"
fi

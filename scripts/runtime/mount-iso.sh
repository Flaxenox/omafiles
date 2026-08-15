#!/bin/bash
# Mounts a .iso via a loop device (udisksctl loop-setup) and exposes the resulting
# mount path. Prints "Mounted X at Y." -- same format that
# plain "udisksctl mount -b" already uses when mounting a normal drive, so
# Omafiles.qml parses the path with the same regex it already had for
# mountProc, without needing a new output format.
#
# $1 = path to the .iso
set -e
iso="$1"
loopdev=$(udisksctl loop-setup --file="$iso" --no-user-interaction | sed -n 's/.* as \(\/dev\/loop[0-9]*\)\..*/\1/p')
[[ -n "$loopdev" ]] || exit 1

# This system automounts the loop device as soon as it's created (session
# udisks2/gvfs policy), but it's a race -- it may already be
# mounted by the time we get here, or the automount may mount it just
# while the "udisksctl mount" below is running. Instead of checking
# beforehand (and leaving the same race anyway), we try to mount and only if it
# fails do we check whether it was precisely because it was already mounted.
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

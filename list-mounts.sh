#!/bin/bash
# Lists the drives relevant to the Omafiles sidebar. TSV:
# label<TAB>path<TAB>device<TAB>ejectable(0/1)<TAB>mounted(0/1)<TAB>fstype
# fstype serves to distinguish the optical-disc/ISO icon (iso9660) from the rest.
#
# Two sources:
#  1) findmnt: what is already mounted and makes sense to show as a drive --
#     the system root, anything under /mnt and the udisks2 automounts
#     under /run/media/$USER. The internal btrfs subvolumes
#     (/home, /srv, /var/log...) are excluded on purpose -- they're the
#     same disk as "/", showing them separately would only confuse. Only
#     /run/media/$USER (typically removable) is marked as ejectable --
#     "/" and /mnt/* stay always mounted.
#  2) lsblk: removable partitions/disks with a file system that
#     are NOT mounted yet, to be able to offer "Mount" from the UI.
#     Empty path and mounted=0; the device is the one that receives
#     `udisksctl mount -b`.

findmnt -A -r -n -o TARGET,SOURCE,FSTYPE 2>/dev/null | while read -r target source fstype; do
  removable=0
  case "$target" in
    /) label="System (/)" ;;
    /mnt/*)
      [[ "$target" == "/mnt" ]] && continue
      label=$(basename "$target")
      ;;
    /run/media/*/*)
      label=$(basename "$target")
      removable=1
      ;;
    *) continue ;;
  esac
  printf '%s\t%s\t%s\t%s\t1\t%s\n' "$label" "$target" "$source" "$removable" "$fstype"
done

mounted_devices=$(findmnt -A -r -n -o SOURCE 2>/dev/null)

# KNAME (not PATH) so as not to clobber the script's own PATH environment
# variable when reading with `read`; the device is reconstructed as /dev/$kname.
lsblk -rno KNAME,RM,TYPE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null | while read -r kname rm type fstype mountpoint label; do
  [[ "$rm" == "1" ]] || continue
  [[ -n "$fstype" ]] || continue
  [[ "$type" == "part" || "$type" == "disk" ]] || continue
  [[ -n "$mountpoint" ]] && continue
  dev="/dev/$kname"
  grep -qxF "$dev" <<< "$mounted_devices" && continue
  printf '%s\t\t%s\t1\t0\t%s\n' "${label:-$kname}" "$dev" "$fstype"
done

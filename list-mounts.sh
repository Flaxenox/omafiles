#!/bin/bash
# Lista las unidades relevantes para la barra lateral de Omafiles. TSV:
# etiqueta<TAB>ruta<TAB>dispositivo<TAB>expulsable(0/1)<TAB>montado(0/1)<TAB>fstype
# fstype sirve para distinguir icono de disco óptico/ISO (iso9660) del resto.
#
# Dos fuentes:
#  1) findmnt: lo que ya está montado y tiene sentido mostrar como unidad --
#     la raíz del sistema, cualquier cosa bajo /mnt y los automontajes de
#     udisks2 bajo /run/media/$USER. Se excluyen a propósito los
#     subvolúmenes btrfs internos (/home, /srv, /var/log...) -- son el
#     mismo disco que "/", mostrarlos por separado solo confundiría. Solo
#     /run/media/$USER (típicamente extraíble) se marca como expulsable --
#     "/" y /mnt/* se quedan siempre montados.
#  2) lsblk: particiones/discos removibles con sistema de ficheros que
#     todavía NO están montados, para poder ofrecer "Montar" desde la UI.
#     Ruta vacía y montado=0; el dispositivo es el que recibe
#     `udisksctl mount -b`.

findmnt -A -r -n -o TARGET,SOURCE,FSTYPE 2>/dev/null | while read -r target source fstype; do
  removable=0
  case "$target" in
    /) label="Sistema (/)" ;;
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

# KNAME (no PATH) para no pisar la variable de entorno PATH del propio
# script al leer con `read`; el dispositivo se reconstruye como /dev/$kname.
lsblk -rno KNAME,RM,TYPE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null | while read -r kname rm type fstype mountpoint label; do
  [[ "$rm" == "1" ]] || continue
  [[ -n "$fstype" ]] || continue
  [[ "$type" == "part" || "$type" == "disk" ]] || continue
  [[ -n "$mountpoint" ]] && continue
  dev="/dev/$kname"
  grep -qxF "$dev" <<< "$mounted_devices" && continue
  printf '%s\t\t%s\t1\t0\t%s\n' "${label:-$kname}" "$dev" "$fstype"
done

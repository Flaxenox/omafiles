#!/bin/bash
# Lista las ubicaciones de red montadas vía GVfs (SFTP/SMB/WebDAV/FTP...)
# para la barra lateral. Cada mount activo aparece como un subdirectorio
# real y navegable bajo $XDG_RUNTIME_DIR/gvfs/ (gvfsd-fuse lo expone ahí),
# así que list-dir.sh ya sabe listarlo sin ningún cambio -- lo único que
# hace falta aquí es descubrir cuáles hay activos y sacar una etiqueta
# legible del nombre interno del mount, que tiene forma
# "esquema:clave=valor,clave=valor,...".
#
# NUL-delimitado, 3 campos por entrada: etiqueta / ruta / esquema (mismo
# protocolo que list-dir.sh/search-recursive.sh/trash-info.sh).

gvfs_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs"
[[ -d "$gvfs_dir" ]] || exit 0

shopt -s nullglob
for d in "$gvfs_dir"/*/; do
  name="${d%/}"
  name="$(basename -- "$name")"
  scheme="${name%%:*}"
  rest="${name#*:}"

  host=""
  share=""
  user=""
  IFS=',' read -ra pairs <<< "$rest"
  for pair in "${pairs[@]}"; do
    case "$pair" in
      host=*) host="${pair#host=}" ;;
      server=*) host="${pair#server=}" ;;
      share=*) share="${pair#share=}" ;;
      user=*) user="${pair#user=}" ;;
    esac
  done

  case "$scheme" in
    sftp) proto="SFTP" ;;
    ftp|ftps) proto="FTP" ;;
    dav|davs) proto="WebDAV" ;;
    smb-share|smb) proto="SMB" ;;
    *) proto="$scheme" ;;
  esac

  label="$proto: ${host:-$name}"
  [[ -n "$share" ]] && label="$label/$share"
  [[ -n "$user" ]] && label="$label ($user)"

  printf '%s\0%s\0%s\0' "$label" "${d%/}" "$scheme"
done

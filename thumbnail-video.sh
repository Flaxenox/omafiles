#!/bin/bash
# Genera (si no existe ya) una miniatura JPEG de un vídeo con
# ffmpegthumbnailer. $1 = vídeo origen, $2 = ruta destino del .jpg. El
# nombre de destino ya incluye el mtime del origen (lo decide quien llama),
# así que si el fichero cambia se pide una miniatura nueva sin necesidad de
# invalidar nada aquí.

src="$1"
dest="$2"
[[ -n "$src" && -n "$dest" ]] || exit 1
[[ -f "$dest" ]] && exit 0

mkdir -p -- "$(dirname -- "$dest")"
ffmpegthumbnailer -i "$src" -o "$dest" -s 160 -q 6 2>/dev/null

#!/bin/bash
# Lista UN nivel de profundidad dentro de un archivo comprimido (zip/7z/
# rar/tar-family) sin extraerlo -- para poder "entrar" en un .zip como si
# fuera una carpeta más (ver inArchive/archivePath/archiveSubPath en
# Omafiles.qml). NUL-delimitado, 2 campos por entrada: nombre / es-carpeta
# (0|1). Sin tamaño: cada herramienta lo expone en un formato de columnas
# distinto y parsear los 4 de forma robusta no compensaba frente a la
# complejidad -- se puede añadir más adelante si hace falta de verdad.
#
# $1 = ruta real al archivo en disco, $2 = subruta dentro del archivo
# ("" = raíz del archivo)

archive="$1"
sub="$2"
ext="${archive##*.}"
ext="${ext,,}"

list_raw() {
  case "$ext" in
    zip) unzip -Z1 -- "$archive" 2>/dev/null ;;
    7z) 7z l -ba -slt -- "$archive" 2>/dev/null | grep '^Path = ' | sed 's/^Path = //' ;;
    rar) unrar lb -- "$archive" 2>/dev/null ;;
    # Sin "--" a propósito: con "tf" (forma corta agrupada de -t -f), tar
    # toma el token SIGUIENTE como argumento directo de -f -- un "--" ahí
    # se interpreta como el propio nombre de fichero a abrir, no como fin
    # de opciones, y tar falla con "--: No such file or directory". No
    # hace falta como protección igualmente: $archive siempre es una ruta
    # absoluta construida por el propio Omafiles, nunca texto suelto del
    # usuario que pudiera empezar por "-".
    tar|gz|tgz|bz2|tbz2|xz|txz) tar tf "$archive" 2>/dev/null ;;
    *) exit 1 ;;
  esac
}

prefix=""
[[ -n "$sub" ]] && prefix="${sub%/}/"

# Dos pasadas en vez de una -- necesario porque el orden en el que list_raw
# saca las entradas no está garantizado (algunas herramientas listan la
# entrada de directorio explícita ANTES de sus hijos, otras después, y 7z
# no marca directorios con "/" al final en absoluto). Con una sola pasada,
# si la entrada de carpeta "a" (sin hijos vistos todavía) se procesaba
# antes que "a/dentro.txt", se marcaba como fichero y ese resultado ya no
# se podía corregir después por el "seen" -- 7z reproducía justo este bug
# (una carpeta de primer nivel salía como fichero). Ahora se recopila todo
# en is_dir_of[] y solo se imprime al final, así que da igual el orden.
declare -A is_dir_of
order=()

while IFS= read -r rawpath; do
  explicit_dir=0
  [[ "$rawpath" == */ ]] && explicit_dir=1
  path="${rawpath%/}"
  [[ -z "$path" ]] && continue

  if [[ -n "$prefix" ]]; then
    [[ "$path" == "$prefix"* ]] || continue
    rel="${path#"$prefix"}"
  else
    rel="$path"
  fi
  [[ -z "$rel" ]] && continue

  first="${rel%%/*}"
  if [[ -z "${is_dir_of[$first]+x}" ]]; then
    order+=("$first")
    is_dir_of[$first]=0
  fi
  # Carpeta si: hay más tramos por debajo (siempre cierto pase lo que
  # pase con el flag "/"), o la propia entrada de primer nivel venía
  # marcada como directorio explícito.
  if [[ "$first" != "$rel" || "$explicit_dir" == "1" ]]; then
    is_dir_of[$first]=1
  fi
done < <(list_raw)

for name in "${order[@]}"; do
  printf '%s\0%s\0' "$name" "${is_dir_of[$name]}"
done

#!/usr/bin/env bash
# Búsqueda GLOBAL indexada para la lupa de Omafiles: consulta el índice que ya
# mantiene el sistema (no recorre el disco) y devuelve rutas absolutas.
#
# Backends, en orden de preferencia (Prioridad 1/2 del encargo):
#   1. Tracker (tracker3 / TinySPARQL)  -- el mismo motor que Nautilus.
#   2. plocate / locate                  -- índice ligero de rutas.
# Si no hay NINGUNO, sale con código 2 (sentinel): el lado QML cae entonces al
# SearchWorker recursivo (Prioridad 3). NO se crea índice ni daemon propios.
#
# Uso:  search-index.sh <query> [limit] [showHidden:0|1]
# Salida (stdout): una línea por resultado, "tipo\tRUTA_ABSOLUTA"
#   tipo = "dir" | "file"  (se resuelve con test -d, saltando rutas fantasma
#   del índice que ya no existen en disco). El orden de relevancia lo hace el
#   lado QML (SearchBackend); aquí solo se listan las coincidencias.
# stderr: "backend=<nombre>" para diagnóstico (qué motor respondió).

set -uo pipefail

query=${1:-}
limit=${2:-201}
show_hidden=${3:-0}

[[ -z $query ]] && exit 0

# Filtrado de ruido + ocultos.
#   - Ruido SIEMPRE fuera (aunque showHidden): cachés y árboles enormes de
#     dependencias que ensucian cualquier búsqueda global (node_modules,
#     .cache, .git, .pnpm). Tracker ya los excluye de su índice; con plocate
#     (que indexa TODO) hay que filtrarlos aquí para que los resultados útiles
#     no queden sepultados bajo miles de rutas de caché.
#   - Ocultos (sin showHidden): se filtra SOLO por el basename (el propio
#     fichero/carpeta oculto, p.ej. ~/.bashrc), NO por carpetas padre ocultas
#     -- muchas apps viven bajo ~/.local/share, ~/.config, etc. y deben
#     encontrarse igual (Steam, Discord...).
filter_noise() {
  grep -vaE '/(node_modules|\.cache|\.git|\.pnpm|\.cargo|\.rustup)(/|$)'
}
filter_hidden() {
  if [[ $show_hidden == 1 ]]; then cat
  else awk -F/ '$NF !~ /^\./'; fi
}

# Convierte una URI file:// (lo que emite Tracker) en ruta local decodificada.
uri_to_path() {
  sed -e 's|^file://||' | python3 -c 'import sys,urllib.parse
for line in sys.stdin:
    line=line.strip()
    if line: print(urllib.parse.unquote(line))' 2>/dev/null
}

emit_types() {
  # Lee rutas por stdin y emite "tipo\truta" para las que existen. `[ -d ]` es
  # builtin (sin fork), así que 200 comprobaciones son baratas.
  local p
  while IFS= read -r p; do
    [[ -z $p ]] && continue
    if [[ -d $p ]]; then printf 'dir\t%s\n' "$p"
    elif [[ -e $p ]]; then printf 'file\t%s\n' "$p"
    fi
  done
}

# Se sobre-pide al índice (fetch) porque el filtrado de ruido/ocultos y el
# descarte de rutas fantasma reducen el conteo; así el lado QML tiene un pool
# amplio del que ordenar por relevancia y quedarse con los 200 mejores.
fetch=$(( limit * 4 ))
(( fetch > 1200 )) && fetch=1200

if command -v tracker3 >/dev/null 2>&1; then
  echo "backend=tracker3" >&2
  # `tracker3 search` imprime cabeceras + URIs file://; nos quedamos con esas.
  # Tracker ya excluye cachés de su índice, pero pasamos los filtros igual.
  tracker3 search --limit "$fetch" -- "$query" 2>/dev/null \
    | grep -oE 'file://[^ ]+' | uri_to_path | filter_noise | filter_hidden | emit_types
  exit 0
fi

if command -v plocate >/dev/null 2>&1; then
  echo "backend=plocate" >&2
  plocate -i -l "$fetch" -- "$query" 2>/dev/null | filter_noise | filter_hidden | emit_types
  exit 0
fi

if command -v locate >/dev/null 2>&1; then
  echo "backend=locate" >&2
  locate -i -l "$fetch" -- "$query" 2>/dev/null | filter_noise | filter_hidden | emit_types
  exit 0
fi

# Ningún backend indexado: el llamador (SearchBackend.qml) usa SearchWorker.
echo "backend=none" >&2
exit 2

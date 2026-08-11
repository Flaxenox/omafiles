#!/usr/bin/env bash
# Búsqueda por CONTENIDO para la lupa de Omafiles (Fase 26 / Beta 3): busca un
# texto DENTRO de los ficheros del árbol indicado con ripgrep, en vez de por
# nombre. Es el cuarto backend de SearchBackend (content:), el que elimina el
# motivo #1 para abrir la terminal a hacer `rg`.
#
# Uso:  content-search.sh <term> <root> [limit]
#   <root>  = carpeta desde la que buscar (recursivo, como `rg` en un cwd).
#   <limit> = tope de resultados (por defecto 201).
#
# Salida (stdout): una línea por coincidencia, "RUTA\tLINEA\tSNIPPET".
#   RUTA absoluta, LINEA número, SNIPPET el texto de la línea recortado.
# Se usa `rg --json` (robusto ante rutas/textos con ':' o caracteres raros) y se
# parsea con python3. ripgrep ya respeta .gitignore y salta .git/ocultos, así
# que node_modules y demás ruido quedan fuera sin filtrado extra.
#
# Códigos de salida: 0 = ok (con o sin resultados) · 2 = ripgrep no instalado
# (sentinel: el lado QML avisa; NO hay fallback nativo para contenido).

set -uo pipefail

term=${1:-}
root=${2:-.}
limit=${3:-201}

[[ -z $term ]] && exit 0
command -v rg >/dev/null 2>&1 || { echo "backend=none" >&2; exit 2; }
echo "backend=ripgrep" >&2

# -F  fixed-string (literal, no regex: `content:main.cpp` busca ese texto tal
#     cual, no "main<cualquier>cpp"). -S smart-case. --max-columns evita volcar
#     líneas gigantes (minificados). Sin --hidden: respetar el default de rg.
rg --json -F -S --max-columns 300 -- "$term" "$root" 2>/dev/null | python3 -c '
import json, sys
limit = int(sys.argv[1])
n = 0
for line in sys.stdin:
    if n >= limit:
        break
    try:
        o = json.loads(line)
    except Exception:
        continue
    if o.get("type") != "match":
        continue
    d = o["data"]
    path = d.get("path", {}).get("text")
    if not path:
        continue  # rutas no-UTF8 (bytes) se ignoran
    ln = d.get("line_number", 0)
    snippet = d.get("lines", {}).get("text", "")
    # una sola línea, sin tabs (rompen el TSV) ni saltos, recortada
    snippet = snippet.replace("\t", " ").replace("\n", " ").replace("\r", " ").strip()
    if len(snippet) > 200:
        snippet = snippet[:200]
    sys.stdout.write("%s\t%d\t%s\n" % (path, ln, snippet))
    n += 1
' "$limit"
exit 0

#!/bin/bash
# Resalta sintaxis para la previsualización de texto (tecla Espacio) --
# Pygments con estilos EN LÍNEA (noclasses=True), no clases CSS: el
# Text.RichText de QML solo entiende HTML básico con atributos style=
# inline, no hojas de estilo externas. Solo se resaltan los primeros
# $2 bytes, igual que ya hacía la previsualización de texto plano sin
# resaltar -- no tiene sentido colorear un fichero entero de varios MB
# solo para enseñar un fragmento.
#
# $1 = ruta al fichero, $2 = bytes a leer, $3 = extensión (ya la conoce
# Omafiles.qml vía extOf(), evita adivinar el lenguaje por contenido)

path="$1"
bytes="${2:-4000}"
ext="${3,,}"

# Pygments no reconoce estos dos alias tal cual -- se mapean a su lexer
# real. Cualquier otra extensión de codeExt (ver Omafiles.qml) coincide
# con un alias válido de Pygments directamente.
case "$ext" in
  h) lexer=c ;;
  yml) lexer=yaml ;;
  *) lexer="$ext" ;;
esac

html="$(head -c "$bytes" -- "$path" | pygmentize -l "$lexer" -f html -O "noclasses=True,style=gruvbox-dark" 2>/dev/null)"
[[ -z "$html" ]] && exit 1

# Se conserva el <pre> a propósito (no nowrap): es lo que hace que
# Text.RichText de QML respete los saltos de línea de verdad -- fuera de
# un <pre>, HTML colapsa el texto en una sola línea igual que en un
# navegador normal. Solo se quita el <div> exterior (trae su propio
# fondo, que no queremos -- el fondo lo pone Color.menu.background) y los
# atributos propios del <pre> (line-height fijo de Pygments, que no
# queremos -- eso lo controla Style.font.* como el resto del fichero).
printf '%s' "$html" | sed -e 's#^<div[^>]*>##' -e 's#<pre[^>]*>#<pre>#' -e 's#</pre></div>$#</pre>#'

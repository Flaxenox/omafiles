#!/bin/bash
# Abre Omafiles en una ruta concreta. Lo invoca el .desktop (MimeType=
# inode/directory, %u) cuando otra app o xdg-open piden abrir una carpeta.
# $1 = ruta absoluta o URI file:// (lo que mande el manejador de mimetype);
# vacío para el lanzamiento normal desde el menú de aplicaciones.

arg="$1"
path=""

if [[ -n "$arg" ]]; then
  if [[ "$arg" == file://* ]]; then
    encoded="${arg#file://}"
    # Descarta un posible componente de host (file://host/path) -- mismo
    # criterio que urlparse() en dbus-filemanager1.py. No se ha visto
    # ningún caso real que lo genere en este sistema, pero es gratis
    # cubrirlo ya que estamos aquí.
    if [[ "$encoded" != /* ]]; then
      encoded="/${encoded#*/}"
    fi
    # Solo percent-decoding -- bug real: la sustitución "+"->espacio que
    # había aquí antes es el convenio de application/x-www-form-urlencoded,
    # NO el de un URI file:// (RFC 3986), donde un "+" literal en un
    # nombre real ("C++", "backup+2024") nunca se codifica como espacio.
    # Convertía "C++ notes.txt" en "C   notes.txt" (que no existe), así
    # que abrir cualquier fichero/carpeta con "+" en el nombre desde otra
    # app (xdg-open, "Open with Omafiles"...) aterrizaba en ningún sitio,
    # en silencio.
    path="$(printf '%b' "${encoded//%/\\x}")"
  else
    path="$arg"
  fi

  [[ -f "$path" ]] && path="$(dirname -- "$path")"
  [[ -d "$path" ]] || path=""
fi

# summon (no toggle): si Omafiles ya está abierto, queremos que navegue a
# la ruta en una pestaña nueva, no que se cierre.
exec omarchy-shell shell summon io.github.percius04.omafiles "$path"

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
    path="${encoded//+/ }"
    path="$(printf '%b' "${path//%/\\x}")"
  else
    path="$arg"
  fi

  [[ -f "$path" ]] && path="$(dirname -- "$path")"
  [[ -d "$path" ]] || path=""
fi

# summon (no toggle): si Omafiles ya está abierto, queremos que navegue a
# la ruta en una pestaña nueva, no que se cierre.
exec omarchy-shell shell summon io.github.percius04.omafiles "$path"

#!/bin/bash
# Autoregistra Omafiles como gestor de archivos del sistema: .desktop con
# MimeType=inode/directory (xdg-open/"Open folder") + servicio D-Bus
# org.freedesktop.FileManager1 ("Show in file manager" de Firefox/GTK/Qt).
# Lo lanza la app al arrancar (core/AppBindings.qml) desde
# <resourceDir>/scripts/, así que nadie tiene que ejecutarlo a mano.
#
# Idempotente y versionado: no repite el trabajo en cada arranque del shell,
# solo la primera vez o cuando INTEGRATION_VERSION suba (si en el futuro
# cambia la plantilla). Si el usuario revierte el default a mano después,
# no lo pisamos otra vez hasta que subamos la versión.

set -euo pipefail

# Bug real (auditoría 2026-08-05): con "set -e", cualquier paso que
# fallara a mitad abortaba el script en silencio -- STATE_FILE nunca se
# llegaba a escribir, así que el siguiente arranque del shell reintentaba
# el mismo paso fallido para siempre, sin ningún aviso visible (stderr de
# xdg-mime/dbus-send ya iba a /dev/null a propósito). Este trap asegura
# que al menos se vea UNA notificación de que algo falló, en vez de un
# fallo mudo repitiéndose cada arranque sin que nadie se entere.
on_error() {
  command -v notify-send >/dev/null 2>&1 && notify-send \
    "Omafiles" "Failed to set up default-file-manager integrations. Will retry on next launch." >/dev/null 2>&1
}
trap on_error ERR

# v4 (Fase 29): las rutas Exec del .desktop y los servicios D-Bus pasan de
# apuntar al repo a la ubicacion XDG estable ($XDG_DATA_HOME/omafiles), para que
# la integracion sobreviva al borrado del repositorio. Subir la version fuerza
# la reescritura en instalaciones anteriores.
INTEGRATION_VERSION=4

# RES_DIR: raiz ESTABLE de recursos instalados (Fase 29). Los Exec apuntan aqui,
# no al repo, asi que borrar el repositorio no rompe abrir carpetas ni "show in
# file manager". Requiere `cmake --install` (que copia scripts/ y assets/ aqui).
RES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omafiles"
# SELF_RES: la raiz de recursos donde vive ESTE script (para leer el icono sin
# depender de que el install haya corrido ya). En una instalacion == RES_DIR.
SELF_RES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omafiles"
STATE_FILE="$STATE_DIR/integrations-version"

# Fase 29: migración idempotente de la config heredada. actions.toml pasó de
# ~/.config/omarchy/omafiles/ a la config XDG propia (~/.config/omafiles/). Va
# ANTES del early-exit por versión, para que corra aunque las integraciones ya
# estén al día. Solo copia si la antigua existe y la nueva todavía no, y NO
# borra la antigua (por si el usuario aún corre una versión vieja en paralelo).
LEGACY_ACTIONS="$HOME/.config/omarchy/omafiles/actions.toml"
NEW_ACTIONS="${XDG_CONFIG_HOME:-$HOME/.config}/omafiles/actions.toml"
if [[ -f "$LEGACY_ACTIONS" && ! -e "$NEW_ACTIONS" ]]; then
  mkdir -p "$(dirname "$NEW_ACTIONS")"
  cp "$LEGACY_ACTIONS" "$NEW_ACTIONS" 2>/dev/null || true
fi

mkdir -p "$STATE_DIR"
if [[ -f $STATE_FILE ]] && [[ "$(cat "$STATE_FILE" 2>/dev/null)" == "$INTEGRATION_VERSION" ]]; then
  exit 0
fi

XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS_DIR="$XDG_DATA/applications"
DBUS_SERVICES_DIR="$XDG_DATA/dbus-1/services"
ICON_DIR="$XDG_DATA/icons/hicolor/scalable/apps"
mkdir -p "$APPS_DIR" "$DBUS_SERVICES_DIR" "$ICON_DIR"

# Bug real: el .desktop de abajo referencia Icon=omafiles, pero nada
# instalaba nunca el SVG en sí -- estaba puesto a mano en este equipo
# concreto, así que una máquina nueva (o un ~/.local/share/icons
# reconstruido) se quedaría con el icono genérico de "gestor de
# archivos" sin ningún aviso. Ahora el SVG vive en el propio repo
# (assets/omafiles.svg) y este script lo instala como cualquier otra
# integración.
[[ -f "$SELF_RES/assets/omafiles.svg" ]] && cp -f "$SELF_RES/assets/omafiles.svg" "$ICON_DIR/omafiles.svg"

# ID reverse-DNS: obligatorio para la activación D-Bus del .desktop (un nombre
# de bus válido necesita puntos; "omafiles" a secas no vale).
APP_ID=io.github.percius04.omafiles

# .desktop DBusActivatable (v3). Firefox/Zen "abrir carpeta contenedora" NO usa
# xdg-mime ni org.freedesktop.FileManager1: activa el gestor por defecto vía
# org.freedesktop.Application.Open, y solo lo hace con gestores DBusActivatable
# (Nautilus lo es por ser GApplication). Sin esto, Zen resolvía el default
# (omafiles) pero no podía activarlo por D-Bus y caía a Nautilus. Sustituye al
# antiguo omafiles.desktop (no activable).
rm -f "$APPS_DIR/omafiles.desktop"
cat >"$APPS_DIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Omafiles
GenericName=File manager
Comment=Custom file manager for Omarchy
Exec=$RES_DIR/scripts/open-path.sh %u
Icon=omafiles
Terminal=false
Categories=System;FileManager;
MimeType=inode/directory;
DBusActivatable=true
EOF

# Servicio D-Bus de org.freedesktop.Application (la interfaz que activa el
# .desktop DBusActivatable). El Name DEBE ser el mismo id del .desktop.
cat >"$DBUS_SERVICES_DIR/$APP_ID.service" <<EOF
[D-BUS Service]
Name=$APP_ID
Exec=$RES_DIR/scripts/dbus-app-open.py
EOF

# Servicio D-Bus org.freedesktop.FileManager1 ("Show in file manager" de apps
# GTK/Qt que sí usan esta interfaz).
cat >"$DBUS_SERVICES_DIR/org.freedesktop.FileManager1.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=$RES_DIR/scripts/dbus-filemanager1.py
EOF

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" >/dev/null 2>&1
command -v xdg-mime >/dev/null 2>&1 && xdg-mime default "$APP_ID.desktop" inode/directory >/dev/null 2>&1

# Si algo (típicamente Nautilus) ya se activó y cogió el nombre de bus antes
# de que existiera nuestro .service, forzamos un rescan para que el próximo
# ShowItems/ShowFolders ya nos llegue a nosotros sin esperar al próximo login.
command -v dbus-send >/dev/null 2>&1 && dbus-send --session --type=method_call \
  --dest=org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1

echo -n "$INTEGRATION_VERSION" >"$STATE_FILE"

# notify-send estándar (freedesktop), independiente de Omarchy. El icono es el
# propio de la app (Icon=omafiles ya instalado en hicolor).
command -v notify-send >/dev/null 2>&1 && notify-send -i omafiles \
  "Omafiles" "Set as the default file manager (folders, xdg-open, and \"show in file manager\")." >/dev/null 2>&1

exit 0

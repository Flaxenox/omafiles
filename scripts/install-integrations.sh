#!/bin/bash
# Autoregistra Omafiles como gestor de archivos del sistema: .desktop con
# MimeType=inode/directory (xdg-open/"Open folder") + servicio D-Bus
# org.freedesktop.FileManager1 ("Show in file manager" de Firefox/GTK/Qt).
# Se llama desde Omafiles.qml (Component.onCompleted) al cargar el plugin --
# nadie tiene que ejecutar esto a mano tras un `omarchy plugin add`.
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
  command -v omarchy-notification-send >/dev/null 2>&1 && omarchy-notification-send \
    "Omafiles" "Failed to set up default-file-manager integrations (see ~/.config/omarchy/plugins/omafiles/scripts/install-integrations.sh). Will retry on next shell restart." >/dev/null 2>&1
}
trap on_error ERR

INTEGRATION_VERSION=2
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$HOME/.local/state/omafiles"
STATE_FILE="$STATE_DIR/integrations-version"

mkdir -p "$STATE_DIR"
if [[ -f $STATE_FILE ]] && [[ "$(cat "$STATE_FILE" 2>/dev/null)" == "$INTEGRATION_VERSION" ]]; then
  exit 0
fi

APPS_DIR="$HOME/.local/share/applications"
DBUS_SERVICES_DIR="$HOME/.local/share/dbus-1/services"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$APPS_DIR" "$DBUS_SERVICES_DIR" "$ICON_DIR"

# Bug real: el .desktop de abajo referencia Icon=omafiles, pero nada
# instalaba nunca el SVG en sí -- estaba puesto a mano en este equipo
# concreto, así que una máquina nueva (o un ~/.local/share/icons
# reconstruido) se quedaría con el icono genérico de "gestor de
# archivos" sin ningún aviso. Ahora el SVG vive en el propio repo
# (assets/omafiles.svg) y este script lo instala como cualquier otra
# integración.
cp -f "$PLUGIN_DIR/assets/omafiles.svg" "$ICON_DIR/omafiles.svg"

cat >"$APPS_DIR/omafiles.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Omafiles
GenericName=File manager
Comment=Custom file manager for Omarchy
Exec=$PLUGIN_DIR/scripts/open-path.sh %u
Icon=omafiles
Terminal=false
Categories=System;FileManager;
MimeType=inode/directory;
EOF

cat >"$DBUS_SERVICES_DIR/org.freedesktop.FileManager1.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec=$PLUGIN_DIR/scripts/dbus-filemanager1.py
EOF

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" >/dev/null 2>&1
command -v xdg-mime >/dev/null 2>&1 && xdg-mime default omafiles.desktop inode/directory >/dev/null 2>&1

# Si algo (típicamente Nautilus) ya se activó y cogió el nombre de bus antes
# de que existiera nuestro .service, forzamos un rescan para que el próximo
# ShowItems/ShowFolders ya nos llegue a nosotros sin esperar al próximo login.
command -v dbus-send >/dev/null 2>&1 && dbus-send --session --type=method_call \
  --dest=org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1

echo -n "$INTEGRATION_VERSION" >"$STATE_FILE"

# md-folder, matches the Nerd Font glyph used in Omafiles.qml -- built
# from the codepoint at runtime, never pasted literally, to avoid an
# editor silently swapping in a different invisible private-use char.
folder_glyph=$(printf '\U000F024B')
command -v omarchy-notification-send >/dev/null 2>&1 && omarchy-notification-send -g "$folder_glyph" \
  "Omafiles" "Set as the default file manager (folders, xdg-open, and \"show in file manager\")." >/dev/null 2>&1

exit 0

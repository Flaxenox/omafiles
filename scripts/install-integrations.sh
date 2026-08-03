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

INTEGRATION_VERSION=1
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$HOME/.local/state/omafiles"
STATE_FILE="$STATE_DIR/integrations-version"

mkdir -p "$STATE_DIR"
if [[ -f $STATE_FILE ]] && [[ "$(cat "$STATE_FILE" 2>/dev/null)" == "$INTEGRATION_VERSION" ]]; then
  exit 0
fi

APPS_DIR="$HOME/.local/share/applications"
DBUS_SERVICES_DIR="$HOME/.local/share/dbus-1/services"
mkdir -p "$APPS_DIR" "$DBUS_SERVICES_DIR"

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

#!/usr/bin/env python3
# Implementa org.freedesktop.Application para Omafiles, de modo que sea un
# gestor de archivos ACTIVABLE POR D-BUS.
#
# Por qué hace falta: Firefox/Zen "abrir carpeta contenedora" no usa xdg-mime
# ni org.freedesktop.FileManager1 -- activa el .desktop por defecto de
# inode/directory vía org.freedesktop.Application.Open, y solo funciona si ese
# gestor expone esta interfaz (Nautilus la tiene por ser GApplication; omafiles
# no). Sin ella, Zen resuelve el default (omafiles) pero, al no poder activarlo
# por D-Bus, cae al primer gestor DBusActivatable que encuentra (Nautilus).
#
# El nombre de bus (io.github.percius04.omafiles) DEBE coincidir con el basename
# del .desktop DBusActivatable (io.github.percius04.omafiles.desktop) y el
# object path con su forma en /. Reenvía a `omafiles <payload>` (instancia
# única), con el mismo formato de payload que core/OmafilesContent.open():
# "carpeta" o "carpeta\nnombre1\x1fnombre2" (revelar/seleccionar).

import sys
import urllib.parse
from pathlib import Path

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS_NAME = "io.github.percius04.omafiles"
OBJECT_PATH = "/io/github/percius04/omafiles"
OMAFILES_BIN = str(Path.home() / ".local" / "bin" / "omafiles")

INTROSPECTION_XML = """
<node>
  <interface name="org.freedesktop.Application">
    <method name="Activate">
      <arg type="a{sv}" name="platform_data" direction="in"/>
    </method>
    <method name="Open">
      <arg type="as" name="uris" direction="in"/>
      <arg type="a{sv}" name="platform_data" direction="in"/>
    </method>
    <method name="ActivateAction">
      <arg type="s" name="action_name" direction="in"/>
      <arg type="av" name="parameter" direction="in"/>
      <arg type="a{sv}" name="platform_data" direction="in"/>
    </method>
  </interface>
</node>
"""

loop = GLib.MainLoop()


def uri_to_path(uri):
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme not in ("file", ""):
        return None
    return urllib.parse.unquote(parsed.path)


def launch(payload):
    try:
        Gio.Subprocess.new([OMAFILES_BIN, payload], Gio.SubprocessFlags.NONE)
    except GLib.Error as e:
        print("omafiles Application.Open: fallo al lanzar omafiles:", e, file=sys.stderr)


def open_uris(uris):
    # Agrupa por carpeta contenedora: un fichero -> abre su carpeta y lo
    # selecciona (revelar); una carpeta -> la abre. Un único launch por carpeta.
    groups = {}
    order = []
    for uri in uris:
        path = uri_to_path(uri)
        if not path:
            continue
        p = Path(path)
        if p.is_dir():
            folder, name = str(p), None
        else:
            folder, name = str(p.parent), p.name
        if folder not in groups:
            groups[folder] = []
            order.append(folder)
        if name:
            groups[folder].append(name)
    for folder in order:
        names = groups[folder]
        payload = folder if not names else folder + "\n" + "\x1f".join(names)
        launch(payload)


def on_method_call(connection, sender, object_path, interface_name,
                   method_name, parameters, invocation):
    if method_name == "Open":
        uris, _platform_data = parameters.unpack()
        open_uris(uris)
    elif method_name == "Activate":
        launch("")  # sin ruta -> arranque normal (restaura la sesión anterior)
    # ActivateAction: Omafiles no expone acciones de .desktop -> no-op.
    invocation.return_value(None)


def on_bus_acquired(connection, name):
    node_info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
    connection.register_object(OBJECT_PATH, node_info.interfaces[0],
                               on_method_call, None, None)


def on_name_lost(connection, name):
    loop.quit()


Gio.bus_own_name(
    Gio.BusType.SESSION,
    BUS_NAME,
    Gio.BusNameOwnerFlags.NONE,
    on_bus_acquired,
    None,
    on_name_lost,
)

loop.run()

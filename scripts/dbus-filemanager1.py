#!/usr/bin/env python3
# Backend de org.freedesktop.FileManager1 para Omafiles.
#
# Muchas apps (Firefox al terminar una descarga, "Show in file manager" de
# apps GTK/Qt, etc.) no usan xdg-mime/.desktop para "abrir la carpeta
# contenedora" -- llaman a este interfaz D-Bus, que tradicionalmente solo
# provee Nautilus (org.freedesktop.FileManager1.service en
# /usr/share/dbus-1/services/). Este servicio de usuario, activado por
# D-Bus a demanda (ver ../../../../.local/share/dbus-1/services/), le quita
# el puesto reenviando la petición a Omafiles vía `omarchy-shell shell
# summon`.

import sys
import urllib.parse
from pathlib import Path

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.FileManager1"
OBJECT_PATH = "/org/freedesktop/FileManager1"
PLUGIN_ID = "io.github.percius04.omafiles"

INTROSPECTION_XML = """
<node>
  <interface name="org.freedesktop.FileManager1">
    <method name="ShowFolders">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItems">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItemProperties">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
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


def summon(folder, select_name=""):
    payload = folder if not select_name else folder + "\n" + select_name
    try:
        Gio.Subprocess.new(
            ["omarchy-shell", "shell", "summon", PLUGIN_ID, payload],
            Gio.SubprocessFlags.NONE,
        )
    except GLib.Error as e:
        print("omafiles FileManager1: fallo al invocar omarchy-shell:", e, file=sys.stderr)


def handle_show(uris, select_item):
    for uri in uris:
        path = uri_to_path(uri)
        if not path:
            continue
        p = Path(path)
        if select_item:
            # ShowItems/ShowItemProperties siempre significan "muéstralo
            # dentro de su carpeta contenedora", sea fichero o carpeta.
            summon(str(p.parent), p.name)
        else:
            summon(str(p) if p.is_dir() else str(p.parent))


def on_method_call(connection, sender, object_path, interface_name, method_name, parameters, invocation):
    uris, _startup_id = parameters.unpack()
    if method_name in ("ShowItems", "ShowItemProperties"):
        handle_show(uris, select_item=True)
    elif method_name == "ShowFolders":
        handle_show(uris, select_item=False)
    invocation.return_value(None)


def on_bus_acquired(connection, name):
    node_info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
    connection.register_object(
        OBJECT_PATH,
        node_info.interfaces[0],
        on_method_call,
        None,
        None,
    )


def on_name_lost(connection, name):
    # Otro proceso ya tiene el nombre (o el bus lo ha retirado) -- no hay
    # nada que disputar, simplemente salimos.
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

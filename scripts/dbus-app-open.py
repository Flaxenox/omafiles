#!/usr/bin/python3
# Implements org.freedesktop.Application for Omafiles, so that it's a
# D-BUS-ACTIVATABLE file manager.
#
# Why it's needed: Firefox/Zen "open containing folder" doesn't use xdg-mime
# nor org.freedesktop.FileManager1 -- it activates the default .desktop of
# inode/directory via org.freedesktop.Application.Open, and it only works if that
# manager exposes this interface (Nautilus has it by being a GApplication; omafiles
# doesn't). Without it, Zen resolves the default (omafiles) but, being unable to activate it
# over D-Bus, falls back to the first DBusActivatable manager it finds (Nautilus).
#
# The bus name (io.github.percius04.omafiles) MUST match the basename
# of the DBusActivatable .desktop (io.github.percius04.omafiles.desktop) and the
# object path its form in /. It forwards to `omafiles <payload>` (single
# instance), with the same payload format as core/OmafilesContent.open():
# "folder" or "folder\nname1\x1fname2" (reveal/select).

import sys
import shutil
import urllib.parse
from pathlib import Path

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS_NAME = "io.github.percius04.omafiles"
OBJECT_PATH = "/io/github/percius04/omafiles"
OMAFILES_BIN = shutil.which("omafiles") or str(Path.home() / ".local" / "bin" / "omafiles")

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
        print("omafiles Application.Open: failed to launch omafiles:", e, file=sys.stderr)


def open_uris(uris):
    # Groups by containing folder: a file -> opens its folder and
    # selects it (reveal); a folder -> opens it. A single launch per folder.
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
        launch("")  # no path -> normal startup (restores the previous session)
    # ActivateAction: Omafiles exposes no .desktop actions -> no-op.
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

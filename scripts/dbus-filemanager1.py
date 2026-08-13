#!/usr/bin/python3
# org.freedesktop.FileManager1 backend for Omafiles.
#
# Many apps (Firefox when finishing a download, "Show in file manager" of
# GTK/Qt apps, etc.) don't use xdg-mime/.desktop to "open the containing
# folder" -- they call this D-Bus interface, which traditionally only
# Nautilus provides (org.freedesktop.FileManager1.service in
# /usr/share/dbus-1/services/). This user service, activated by
# D-Bus on demand, takes its place by forwarding the request to the
# Omafiles binary (single instance).

import sys
import urllib.parse
from pathlib import Path

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.FileManager1"
OBJECT_PATH = "/org/freedesktop/FileManager1"
# The standalone Qt6 binary (single instance) is launched from its stable path.
OMAFILES_BIN = str(Path.home() / ".local" / "bin" / "omafiles")

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
    # Same payload that core/OmafilesContent.open() understands: absolute folder,
    # optionally "\n" + names to select (several with \x1f). The binary
    # (single instance) navigates to that folder bringing the window to the front.
    payload = folder if not select_name else folder + "\n" + select_name
    try:
        Gio.Subprocess.new(
            [OMAFILES_BIN, payload],
            Gio.SubprocessFlags.NONE,
        )
    except GLib.Error as e:
        print("omafiles FileManager1: failed to launch omafiles:", e, file=sys.stderr)


def handle_show(uris, select_item):
    # Real bug (audit 2026-08-05): this called summon() once PER
    # URI. Since the plugin is keepLoaded, each summon after the first
    # falls into the "already loaded" branch of Omafiles.qml open(), which
    # ALWAYS opens a new tab -- so selecting several
    # files from the SAME folder in another app (e.g. several downloads in
    # Firefox, "Show in file manager") opened a duplicate
    # tab per file, with only the last one actually highlighted.
    # Now they are grouped by containing folder and a single
    # summon is sent per folder, with all the names of that folder in the
    # payload (separated by \x1f -- see Omafiles.qml open()).
    if select_item:
        # ShowItems/ShowItemProperties always mean "show it
        # inside its containing folder", whether file or folder.
        groups = {}
        order = []
        for uri in uris:
            path = uri_to_path(uri)
            if not path:
                continue
            p = Path(path)
            parent = str(p.parent)
            if parent not in groups:
                groups[parent] = []
                order.append(parent)
            groups[parent].append(p.name)
        for parent in order:
            summon(parent, "\x1f".join(groups[parent]))
    else:
        seen = []
        for uri in uris:
            path = uri_to_path(uri)
            if not path:
                continue
            p = Path(path)
            target = str(p) if p.is_dir() else str(p.parent)
            if target not in seen:
                seen.append(target)
                summon(target)


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
    # Another process already has the name (or the bus withdrew it) -- there's
    # nothing to dispute, we simply exit.
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

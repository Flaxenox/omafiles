import QtQuick
import "../state"
import "../services"
import "../Utils.js" as Utils

// Mount/eject drives (udisksctl) + connect/disconnect network drives
// (gio mount) -- twelfth component extracted from core, and the
// first to move Process + the functions that orchestrate them together out
// of the "Active panel" zone (same criterion as ConflictActions:
// related code that lived scattered; here it was already physically
// contiguous in the file except for the functions, which now truly live
// together). All external calls used `root.xxx(...)`, so they were
// updated to `mountActions.xxx(...)` at their call sites -- no loose
// wrappers remain in root.
Item {
  property Item root: null
  property Item navController: null

  property Item tabOps: null

  function refreshMounts() {
    mountsProc.start([Paths.resourceDir + "/list-mounts.sh"])
  }

  function refreshNetworkMounts() {
    // NATIVE enumeration of GVfs mounts (Phase 16): NetworkMounts.list()
    // replaces list-network-mounts.sh. Synchronous (readdir over gvfs).
    MountsState.networkMounts = NetworkMounts.list()
  }

  function disconnectNetworkMount(mount) {
    if (networkUnmountProc.busy) {
      Notifier.notify("Still disconnecting a network location — try again in a moment")
      return
    }
    networkUnmountProc.wasInside = NavState.currentPath === mount.path || NavState.currentPath.indexOf(mount.path + "/") === 0
    networkUnmountProc.tabIndex = TabsState.activeTabIndex
    networkUnmountProc.start(["gio", "mount", "-u", mount.path])
  }

  function startConnectToServer() {
    DialogsState.connectServerUri = ""
    DialogsState.connectServerError = ""
    DialogsState.connectServerOpen = true
  }

  function cancelConnectToServer() {
    DialogsState.connectServerOpen = false
  }

  // "setsid" + kill the whole group on cancel, same reason as
  // runAction()/cancelAction(): gio mount can get stuck waiting for
  // credentials that are never going to arrive (this app has no
  // user/password dialog -- see the long comment on connectServerOpen further
  // down in the file, next to the dialog), and without this Cancel wouldn't
  // actually manage to kill the process.
  function commitConnectToServer() {
    var uri = DialogsState.connectServerUri.trim()
    if (!uri) return
    DialogsState.connectServerError = ""
    DialogsState.networkConnecting = true
    networkMountProc.start(["gio", "mount", "--", uri], true)
  }

  function cancelNetworkConnect() {
    networkMountProc.cancel()
    DialogsState.networkConnecting = false
  }

  function ejectMount(mount) {
    // Without this guard, double-clicking "Eject" would reassign
    // ejectProc.command in the middle of the first call, restarting it --
    // same problem runAction() already avoided for file actions,
    // but this process didn't have it.
    // Explicit notice instead of a mute return -- without this, the second
    // click did nothing visible and it looked like the app had ignored the
    // press, same as used to happen to runAction() (see there).
    if (ejectProc.busy) {
      Notifier.notify("Still ejecting a drive — try again in a moment")
      return
    }
    var wasInside = NavState.currentPath === mount.path || NavState.currentPath.indexOf(mount.path + "/") === 0
    ejectProc.mountPath = mount.path
    ejectProc.wasInside = wasInside
    ejectProc.tabIndex = TabsState.activeTabIndex
    ejectProc.device = mount.device
    // Eject button spinner (Phase 21): cleared in ejectProc.onFinished.
    MountsState.ejectingDevice = mount.device
    ejectProc.start(["udisksctl", "unmount", "-b", mount.device])
  }

  // udisksctl prints "Mounted /dev/sdX at /run/media/user/Label." -- the
  // path is extracted from there instead of re-running list-mounts.sh and
  // guessing which is the newly mounted drive.
  function mountDevice(mount) {
    if (mountProc.busy) {
      Notifier.notify("Still mounting a drive — try again in a moment")
      return
    }
    // Captured here (not re-read in onFinished) -- if the mouse moves to
    // another panel while the mount takes a while, the result must navigate
    // the panel that requested it, not whichever happens to be active when it
    // finishes.
    mountProc.tabIndex = TabsState.activeTabIndex
    mountProc.start(["udisksctl", "mount", "-b", mount.device])
  }

  // Unlike isArchive() (enterArchive(), read-only navigation without
  // mounting anything for real), an .iso is mounted as a real loop
  // device -- so whatever is inside (an installer, for example) can be
  // run/copied just like in any normal folder, not just looked at. It
  // appears in the sidebar like any other removable drive as soon as it is
  // mounted (list-mounts.sh already distinguishes the icon by
  // fstype=iso9660) and is ejected the same way.
  function mountIso(entry) {
    if (mountIsoProc.busy) {
      Notifier.notify("Still mounting an ISO — try again in a moment")
      return
    }
    mountIsoProc.tabIndex = TabsState.activeTabIndex
    mountIsoProc.start(["bash", Paths.resourceDir + "/mount-iso.sh", Utils.joinPath(NavState.currentPath, entry.name)])
  }

  ProcessRunner {
    id: mountsProc
    onFinished: function (result) {
      MountsState.mounts = Utils.parseMounts(result.stdout)
      _ensureCurrentPathMounted()
    }
  }

  // Req 4 (Phase 20): if the removable/external drive you were browsing is
  // ejected (physically or from another app), UDisks2 triggers refreshMounts()
  // and here it is detected that currentPath hangs off a mount point that is no
  // longer mounted -> navigate to Home. It only looks at paths under /run/media
  // or /mnt (the ones managed by drives): a normal home path never triggers
  // this. A MANUAL eject already navigated with its own wasInside; this covers
  // the ejection NOT started by the app.
  function _ensureCurrentPathMounted() {
    var p = NavState.currentPath
    if (p.indexOf("/run/media/") !== 0 && p.indexOf("/mnt/") !== 0) return
    var covered = MountsState.mounts.some(function (m) {
      return m.mounted && (p === m.path || p.indexOf(m.path + "/") === 0)
    })
    if (!covered) tabOps.navigateTabTo(TabsState.activeTabIndex, Paths.homeDir)
  }

  ProcessRunner {
    id: ejectProc
    property string mountPath: ""
    property bool wasInside: false
    property int tabIndex: -1
    property string device: ""
    onFinished: function (result) {
      MountsState.ejectingDevice = ""
      if (result.exitCode === 0) {
        if (ejectProc.wasInside) tabOps.navigateTabTo(ejectProc.tabIndex, Paths.homeDir)
        // An .iso mounted with mountIso() leaves the /dev/loopN associated to
        // the file even after it is unmounted -- without this, the .iso stays
        // "in use" (can't be moved/deleted) and each one would use up a loop
        // device forever until reboot.
        if (ejectProc.device.indexOf("/dev/loop") === 0) {
          Detached.run(["udisksctl", "loop-delete", "-b", ejectProc.device])
        }
        refreshMounts()
      } else {
        Notifier.notify("Could not eject: " + (result.stderr || "device busy"))
      }
    }
  }

  ProcessRunner {
    id: mountProc
    property int tabIndex: -1
    onFinished: function (result) {
      refreshMounts()
      if (result.exitCode === 0) {
        var match = result.stdout.match(/ at (\/[^\s.]+)/)
        if (match) tabOps.navigateTabTo(mountProc.tabIndex, match[1])
      } else {
        Notifier.notify("Could not mount: " + (result.stderr || "unknown error"))
      }
    }
  }

  ProcessRunner {
    id: mountIsoProc
    property int tabIndex: -1
    onFinished: function (result) {
      refreshMounts()
      if (result.exitCode === 0) {
        var match = result.stdout.match(/ at (\/[^\s.]+)/)
        if (match) tabOps.navigateTabTo(mountIsoProc.tabIndex, match[1])
      } else {
        Notifier.notify("Could not mount ISO: " + (result.stderr || "unknown error"))
      }
    }
  }

  ProcessRunner {
    id: networkUnmountProc
    property bool wasInside: false
    property int tabIndex: -1
    onFinished: function (result) {
      if (result.exitCode === 0) {
        if (networkUnmountProc.wasInside) tabOps.navigateTabTo(networkUnmountProc.tabIndex, Paths.homeDir)
        refreshNetworkMounts()
      } else {
        Notifier.notify("Could not disconnect: " + (result.stderr || "unknown error"))
      }
    }
  }

  // Without -a/--anonymous nor any way to pass a password: if the server asks
  // for credentials, gio needs an interactive GMountOperation that this
  // app does not implement (it would be a sub-project in itself, like the
  // "Connect to server" dialog + keyring of Nautilus). It works fine for SFTP
  // with an SSH key already set up, or any server with credentials already
  // saved in the keyring from a previous connection (with Nautilus, for
  // example) -- if it gets stuck waiting for a password that never arrives,
  // the user has the dialog's Cancel button
  // (cancelNetworkConnect/setsid, same mechanism as cancelAction()).
  ProcessRunner {
    id: networkMountProc
    onFinished: function (result) {
      DialogsState.networkConnecting = false
      if (result.exitCode === 0) {
        DialogsState.connectServerOpen = false
        // gio does not print the local path the way udisksctl does -- it is
        // re-listed (native, synchronous) and we enter the mount that wasn't
        // there before (the one that just appeared) instead of parsing the
        // output of "gio mount".
        var before = MountsState.networkMounts.map(function (m) { return m.path })
        var parsed = NetworkMounts.list()
        MountsState.networkMounts = parsed
        var fresh = parsed.filter(function (m) { return before.indexOf(m.path) < 0 })
        if (fresh.length > 0) navController.navigateTo(fresh[0].path)
      } else {
        DialogsState.connectServerError = result.stderr.trim() || "Could not connect"
      }
    }
  }

}

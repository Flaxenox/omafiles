pragma Singleton
import QtQuick

// Local drives and network mounts listed in the sidebar --
// fifteenth singleton of the state/ layer, completes
// logic/MountActions.qml.
QtObject {
  property var mounts: []
  // Device (device path, e.g. /dev/sdb1) whose ejection is in progress --
  // triggers the spinner of the sidebar's eject button (Phase 21). It is
  // set in MountActions.ejectMount() and cleared on completion; the row
  // disappears on its own when UDisksWatcher refreshes the listing. No timers.
  property string ejectingDevice: ""
  // Network locations (SFTP/SMB/WebDAV/FTP) mounted via GVfs -- each
  // one is a real directory under $XDG_RUNTIME_DIR/gvfs/, list-dir.sh
  // navigates it just like any local folder unchanged.
  property var networkMounts: []
}

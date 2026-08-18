#pragma once

#include <QObject>
#include <QTimer>
#include <qqmlregistration.h>

// Reactive GVfs network-mount watcher (V1.1) -- same idea as
// UDisksWatcher, but for network locations (SFTP/FTP/WebDAV/SMB), which
// UDisks2 doesn't cover. Before this, GVfs mounts were only refreshed on
// internal app events (connect/disconnect server, navigate to a network
// path) and on window open -- a mount created or removed from ANOTHER app
// (Nautilus, gio mount, a file picker...) stayed invisible until one of
// those happened, a known, self-documented limitation
// (core/AppBindings.qml). GVfs's own daemon exposes exactly the signals
// needed for this on the SESSION bus, confirmed directly (2026-08-18,
// `busctl --user introspect org.gtk.vfs.Daemon /org/gtk/vfs/mounttracker`):
// org.gtk.vfs.MountTracker's Mounted/Unmounted.
//
// Deliberately does NOT parse the signal payload or build mount objects
// itself: like UDisksWatcher, the single source of truth stays
// Backend.NetworkMounts.list() (native GVfs directory enumeration) -- this
// only signals "something changed, list again". No polling.
class GvfsWatcher : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit GvfsWatcher(QObject *parent = nullptr);

  // true if it could connect to the session bus and register the
  // subscriptions. If not (e.g. headless CI without a session bus), the
  // watcher stays inert without failing: the app keeps refreshing on
  // internal events and on open, exactly like before this watcher existed.
  Q_INVOKABLE bool available() const;

signals:
  // Emitted (coalesced) on any GVfs mount/unmount, from any process.
  void mountsChanged();

private slots:
  void schedule();

private:
  bool m_available = false;
  QTimer m_coalesce;
};

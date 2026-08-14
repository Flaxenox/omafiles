#pragma once

#include <QObject>
#include <QTimer>
#include <qqmlregistration.h>

// Reactive UDisks2 watcher. Replaces the sidebar's 7 s
// polling with a D-Bus subscription to the signals of the SYSTEM bus of
// org.freedesktop.UDisks2. When UDisks2 notifies ANY block-device
// change -- plugging/ejecting a USB, mounting/unmounting an ISO,
// connecting/unmounting an external disk, a label or mount-state change --
// it emits devicesChanged(), COALESCED with a QTimer
// so a burst of signals triggers a single refresh.
//
// It deliberately does NOT enumerate devices or build mount objects:
// the single source of truth remains list-mounts.sh (findmnt+lsblk, a
// "system adapter" that BACKEND_DESIGN.md keeps on purpose). This watcher
// only signals "something changed, list again", so there is no second
// source that could desynchronize. No polling. No dependency on
// Quickshell (QML singleton, like the rest of backend/).
class UDisksWatcher : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit UDisksWatcher(QObject *parent = nullptr);

  // true if it could connect to the system bus and register the subscriptions.
  // If not (e.g. headless CI without a system bus), the watcher stays inert
  // without failing: the app keeps refreshing on internal events and on open.
  Q_INVOKABLE bool available() const;

signals:
  // Emitted (coalesced) on any block-device change in
  // UDisks2. The frontend responds by listing again (refreshMounts()).
  void devicesChanged();

private slots:
  // A single entry point for the three D-Bus signals: (re)starts the coalescer.
  void schedule();

private:
  bool m_available = false;
  QTimer m_coalesce;
};

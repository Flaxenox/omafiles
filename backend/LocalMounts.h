#pragma once

#include <QObject>
#include <QVariantList>
#include <qqmlregistration.h>

// Native enumeration of local drives for the sidebar (V1.2 code-quality
// pass, docs/audits/V1_2_GENERAL_PERFORMANCE_REPORT.md). Replacement for
// scripts/runtime/list-mounts.sh's actual LISTING (findmnt + lsblk, 3
// subprocess forks on every refreshMounts() call -- on app open, on every
// UDisksWatcher devicesChanged(), and after every mount/eject action).
// UDisksWatcher.cpp already holds this reasoning for keeping the script:
// "QStorageInfo only sees already-mounted filesystems, seeing unmounted
// removable devices too needs libblkid/libudev" -- true for QStorageInfo,
// but UDisks2 itself (already a running system service, already spoken to
// over D-Bus by UDisksWatcher for change notifications) exposes exactly
// that data without adding either dependency: org.freedesktop.UDisks2.Block
// (IdType/IdUsage/IdLabel/Device), .Filesystem (MountPoints, present only
// once actually mounted) and .Drive (Removable) cover both halves of what
// the script did with lsblk+findmnt.
//
// Synchronous (a handful of local D-Bus round-trips over the system bus,
// no process fork, no shell/text parsing) -- same "cheap enough to call
// straight from QML" contract NetworkMounts::list() already has for GVfs.
// Deliberately reproduces the SCRIPT'S EXACT mount-point filtering (only
// "/", "/mnt/*" and "/run/media/$USER/*" are shown as mounted; other real
// mount points -- e.g. btrfs subvolumes like /home, /srv sharing the root
// device -- are not) rather than introducing new UDisks2-specific
// filtering (HintSystem/HintIgnore) that could change real-world behavior
// in ways the old script never exercised.
class LocalMounts : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit LocalMounts(QObject *parent = nullptr);

  // Local drives right now: each element {label, path, device, removable,
  // mounted, fstype} -- same shape shared/Utils.js's parseMounts() used to
  // produce from the script's TSV, so MountsState.mounts can be assigned
  // this return value directly (see MountActions.qml).
  Q_INVOKABLE QVariantList list() const;
};

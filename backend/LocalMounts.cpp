#include "LocalMounts.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QFileInfo>
#include <QVariantMap>

#include <algorithm>

namespace {
const QString kService = QStringLiteral("org.freedesktop.UDisks2");
const QString kManagerPath = QStringLiteral("/org/freedesktop/UDisks2/Manager");
const QString kManagerIface = QStringLiteral("org.freedesktop.UDisks2.Manager");
const QString kPropsIface = QStringLiteral("org.freedesktop.DBus.Properties");
const QString kBlockIface = QStringLiteral("org.freedesktop.UDisks2.Block");
const QString kFsIface = QStringLiteral("org.freedesktop.UDisks2.Filesystem");
const QString kDriveIface = QStringLiteral("org.freedesktop.UDisks2.Drive");

// UDisks2 encodes filesystem paths (Device, each entry of MountPoints) as
// NUL-terminated byte arrays ('ay'), not D-Bus strings -- QByteArray is
// QtDBus's native mapping for 'ay', trimming at the NUL recovers the real
// path.
QString decodeDbusPath(const QByteArray &raw) {
  const int nul = raw.indexOf('\0');
  return QString::fromUtf8(nul >= 0 ? raw.left(nul) : raw);
}

// MountPoints is 'aay' (an array of byte-array paths, plural only for the
// rare bind-mount-in-several-places case) -- a nested/complex D-Bus type
// QtDBus does NOT auto-unwrap into QVariant the way it does simple 'ay',
// so it arrives as a QDBusArgument needing manual iteration.
QStringList decodeMountPoints(const QVariant &v) {
  QStringList out;
  QDBusArgument arg = v.value<QDBusArgument>();
  arg.beginArray();
  while (!arg.atEnd()) {
    QByteArray one;
    arg >> one;
    const QString path = decodeDbusPath(one);
    if (!path.isEmpty())
      out << path;
  }
  arg.endArray();
  return out;
}

QVariantMap getAllProps(const QDBusConnection &bus, const QString &objPath,
                        const QString &iface) {
  QDBusInterface props(kService, objPath, kPropsIface, bus);
  QDBusReply<QVariantMap> reply = props.call(QStringLiteral("GetAll"), iface);
  return reply.isValid() ? reply.value() : QVariantMap();
}

QVariantMap makeEntry(const QString &label, const QString &path,
                      const QString &device, bool removable, bool mounted,
                      const QString &fstype) {
  QVariantMap m;
  m[QStringLiteral("label")] = label;
  m[QStringLiteral("path")] = path;
  m[QStringLiteral("device")] = device;
  m[QStringLiteral("removable")] = removable;
  m[QStringLiteral("mounted")] = mounted;
  m[QStringLiteral("fstype")] = fstype;
  return m;
}

// GetBlockDevices() enumeration order is UDisks2's own internal object
// order (roughly udev/kernel discovery order) -- unrelated to mount time,
// so it does NOT reproduce list-mounts.sh's old, sensible-feeling order
// (findmnt's /proc/self/mountinfo order put "/" first since it's mounted
// at boot, then other fixed mounts, then removable ones mounted later;
// lsblk's not-yet-mounted removables were appended last). A removable USB
// plugged in mid-session could otherwise land ABOVE "System (/)" in the
// sidebar purely because UDisks2 happened to register its Block object
// earlier -- confirmed live (josema plugged in a Ventoy USB, it appeared
// above System (/) and Almacen). Explicit 4-tier sort restores that
// grouping: "/" first (the one entry every install has, the obvious
// reference point), then the rest of the fixed drives, then removable-
// but-mounted, then not-yet-mounted (the ones offered as "Mount") -- same
// relative order this app has always shown, now guaranteed rather than
// incidental to D-Bus object registration order.
int mountRank(const QVariantMap &m) {
  const bool removable = m.value(QStringLiteral("removable")).toBool();
  const bool mounted = m.value(QStringLiteral("mounted")).toBool();
  if (!removable) return m.value(QStringLiteral("path")).toString() == QLatin1String("/") ? 0 : 1;
  if (mounted) return 2;
  return 3;
}
} // namespace

LocalMounts::LocalMounts(QObject *parent) : QObject(parent) {}

QVariantList LocalMounts::list() const {
  QVariantList out;
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected())
    return out;

  QDBusInterface manager(kService, kManagerPath, kManagerIface, bus);
  if (!manager.isValid())
    return out;
  QDBusReply<QList<QDBusObjectPath>> blocks =
      manager.call(QStringLiteral("GetBlockDevices"), QVariantMap());
  if (!blocks.isValid())
    return out;

  for (const QDBusObjectPath &objPath : blocks.value()) {
    const QVariantMap bp = getAllProps(bus, objPath.path(), kBlockIface);
    if (bp.isEmpty())
      continue;

    // Only real, mountable filesystems -- matches lsblk's implicit "has a
    // fstype" check and skips partition-table containers, swap, LUKS, etc.
    const QString idUsage = bp.value(QStringLiteral("IdUsage")).toString();
    if (idUsage != QLatin1String("filesystem"))
      continue;

    const QString device = decodeDbusPath(bp.value(QStringLiteral("Device")).toByteArray());
    const QString idType = bp.value(QStringLiteral("IdType")).toString();
    const QString idLabel = bp.value(QStringLiteral("IdLabel")).toString();

    // Removable/ejectable comes from the associated Drive object (lsblk's
    // RM column equivalent) -- a loop device or some virtual block devices
    // have no Drive at all (empty/root object path), treated as fixed.
    bool removableDrive = false;
    const QString drivePath = bp.value(QStringLiteral("Drive")).value<QDBusObjectPath>().path();
    if (!drivePath.isEmpty() && drivePath != QLatin1String("/")) {
      const QVariantMap dp = getAllProps(bus, drivePath, kDriveIface);
      removableDrive = dp.value(QStringLiteral("Removable")).toBool();
    }

    const QVariantMap fp = getAllProps(bus, objPath.path(), kFsIface);
    const QStringList mountPoints = fp.isEmpty()
        ? QStringList()
        : decodeMountPoints(fp.value(QStringLiteral("MountPoints")));

    // Mounted half (list-mounts.sh's findmnt pass): only "/", "/mnt/*" and
    // "/run/media/$USER/*" are shown -- other real mount points (e.g.
    // btrfs subvolumes like /home, /srv sharing the SAME block device as
    // "/") are deliberately excluded, same as the script's own filter, so
    // as not to confuse "a drive" with "a subvolume of the drive already
    // shown as System (/)".
    for (const QString &target : mountPoints) {
      QString label;
      bool ejectable = false;
      if (target == QLatin1String("/")) {
        label = QStringLiteral("System (/)");
      } else if (target.startsWith(QLatin1String("/mnt/"))) {
        if (target == QLatin1String("/mnt"))
          continue;
        label = QFileInfo(target).fileName();
      } else if (target.startsWith(QLatin1String("/run/media/"))) {
        // Must be at least /run/media/<user>/<name> -- a bare
        // /run/media/<user> (no drive segment) doesn't match, mirroring
        // the script's /run/media/*/* glob.
        const QStringList parts = target.split(QLatin1Char('/'), Qt::SkipEmptyParts);
        if (parts.size() < 4)
          continue;
        label = QFileInfo(target).fileName();
        ejectable = true;
      } else {
        continue;
      }
      out.append(makeEntry(label, target, device, ejectable, true, idType));
    }

    // Unmounted half (list-mounts.sh's lsblk pass): removable, has a real
    // filesystem, not already mounted anywhere -- offered as "Mount" in
    // the UI. path stays empty (nothing to navigate to yet); the device
    // node is what receives `udisksctl mount -b`.
    if (mountPoints.isEmpty() && removableDrive && !idType.isEmpty()) {
      const QString label = idLabel.isEmpty() ? QFileInfo(device).fileName() : idLabel;
      out.append(makeEntry(label, QString(), device, true, false, idType));
    }
  }

  // Stable: within each tier, keeps GetBlockDevices()'s own relative order
  // (no claim to reproducing findmnt/lsblk's exact ordering there, just
  // the same coarse grouping the sidebar has always shown).
  std::stable_sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
    return mountRank(a.toMap()) < mountRank(b.toMap());
  });
  return out;
}

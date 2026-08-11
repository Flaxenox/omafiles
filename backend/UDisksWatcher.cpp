#include "UDisksWatcher.h"

#include <QDBusConnection>

namespace {
const QString kService = QStringLiteral("org.freedesktop.UDisks2");
const QString kObjPath = QStringLiteral("/org/freedesktop/UDisks2");
const QString kObjManager = QStringLiteral("org.freedesktop.DBus.ObjectManager");
const QString kProps = QStringLiteral("org.freedesktop.DBus.Properties");
} // namespace

UDisksWatcher::UDisksWatcher(QObject *parent) : QObject(parent) {
  // Coalescer: a burst of D-Bus signals (plugging a USB fires several
  // InterfacesAdded + PropertiesChanged almost at once) is grouped into a
  // single devicesChanged() -> a single refreshMounts(). Avoids relisting N
  // times.
  m_coalesce.setSingleShot(true);
  m_coalesce.setInterval(150);
  connect(&m_coalesce, &QTimer::timeout, this, &UDisksWatcher::devicesChanged);

  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected())
    return;

  bool ok = true;
  // Appearance/disappearance of objects (partitions, filesystems, drives...).
  ok &= bus.connect(kService, kObjPath, kObjManager,
                    QStringLiteral("InterfacesAdded"), this, SLOT(schedule()));
  ok &= bus.connect(kService, kObjPath, kObjManager,
                    QStringLiteral("InterfacesRemoved"), this, SLOT(schedule()));
  // Property changes of any object of the service (label, mount
  // point, mounted/unmounted state). empty path = all objects of
  // UDisks2; the `sender` filter (kService) narrows it to this service.
  ok &= bus.connect(kService, QString(), kProps,
                    QStringLiteral("PropertiesChanged"), this, SLOT(schedule()));
  m_available = ok;
}

bool UDisksWatcher::available() const { return m_available; }

void UDisksWatcher::schedule() { m_coalesce.start(); }

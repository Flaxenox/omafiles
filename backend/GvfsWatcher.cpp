#include "GvfsWatcher.h"

#include <QDBusConnection>

namespace {
const QString kService = QStringLiteral("org.gtk.vfs.Daemon");
const QString kObjPath = QStringLiteral("/org/gtk/vfs/mounttracker");
const QString kIface = QStringLiteral("org.gtk.vfs.MountTracker");
} // namespace

GvfsWatcher::GvfsWatcher(QObject *parent) : QObject(parent) {
  // Same coalescer rationale as UDisksWatcher: a single gio mount can fire
  // more than one signal in quick succession; group into one mountsChanged().
  m_coalesce.setSingleShot(true);
  m_coalesce.setInterval(150);
  connect(&m_coalesce, &QTimer::timeout, this, &GvfsWatcher::mountsChanged);

  QDBusConnection bus = QDBusConnection::sessionBus();
  if (!bus.isConnected())
    return;

  bool ok = true;
  ok &= bus.connect(kService, kObjPath, kIface, QStringLiteral("Mounted"),
                    this, SLOT(schedule()));
  ok &= bus.connect(kService, kObjPath, kIface, QStringLiteral("Unmounted"),
                    this, SLOT(schedule()));
  m_available = ok;
}

bool GvfsWatcher::available() const { return m_available; }

void GvfsWatcher::schedule() { m_coalesce.start(); }

#include "UDisksWatcher.h"

#include <QDBusConnection>

namespace {
const QString kService = QStringLiteral("org.freedesktop.UDisks2");
const QString kObjPath = QStringLiteral("/org/freedesktop/UDisks2");
const QString kObjManager = QStringLiteral("org.freedesktop.DBus.ObjectManager");
const QString kProps = QStringLiteral("org.freedesktop.DBus.Properties");
} // namespace

UDisksWatcher::UDisksWatcher(QObject *parent) : QObject(parent) {
  // Coalescedor: una ráfaga de señales D-Bus (conectar un USB dispara varias
  // InterfacesAdded + PropertiesChanged casi a la vez) se agrupa en un solo
  // devicesChanged() -> un solo refreshMounts(). Evita relistar N veces.
  m_coalesce.setSingleShot(true);
  m_coalesce.setInterval(150);
  connect(&m_coalesce, &QTimer::timeout, this, &UDisksWatcher::devicesChanged);

  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected())
    return;

  bool ok = true;
  // Aparición/desaparición de objetos (particiones, filesystems, drives...).
  ok &= bus.connect(kService, kObjPath, kObjManager,
                    QStringLiteral("InterfacesAdded"), this, SLOT(schedule()));
  ok &= bus.connect(kService, kObjPath, kObjManager,
                    QStringLiteral("InterfacesRemoved"), this, SLOT(schedule()));
  // Cambios de propiedades de cualquier objeto del servicio (label, punto de
  // montaje, estado montado/desmontado). path vacío = todos los objetos de
  // UDisks2; el filtro por `sender` (kService) lo acota a este servicio.
  ok &= bus.connect(kService, QString(), kProps,
                    QStringLiteral("PropertiesChanged"), this, SLOT(schedule()));
  m_available = ok;
}

bool UDisksWatcher::available() const { return m_available; }

void UDisksWatcher::schedule() { m_coalesce.start(); }

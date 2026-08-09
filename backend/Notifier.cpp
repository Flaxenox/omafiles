#include "Notifier.h"

#include <QProcess>
#include <QStringList>

Notifier::Notifier(QObject *parent) : QObject(parent) {}

void Notifier::notify(const QString &text) {
  // notify-send desatendido: mismo comando que montaba la version
  // Quickshell, con "Omafiles" como titulo centralizado aqui (antes se
  // repetia en cada uno de los 16+ sitios de llamada).
  QProcess::startDetached(QStringLiteral("notify-send"),
                          QStringList{QStringLiteral("Omafiles"), text});
}

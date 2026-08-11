#include "Notifier.h"

#include <QProcess>
#include <QStringList>

Notifier::Notifier(QObject *parent) : QObject(parent) {}

void Notifier::notify(const QString &text) {
  // Detached notify-send: same command the Quickshell version built, with
  // "Omafiles" as the title centralized here (previously it was repeated in
  // each of the 16+ call sites).
  QProcess::startDetached(QStringLiteral("notify-send"),
                          QStringList{QStringLiteral("Omafiles"), text});
}

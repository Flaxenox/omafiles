#include "Detached.h"

#include <QProcess>
#include <QString>
#include <QStringList>

Detached::Detached(QObject *parent) : QObject(parent) {}

void Detached::run(const QVariantList &args) {
  if (args.isEmpty())
    return;

  QStringList command;
  command.reserve(args.size());
  for (const QVariant &a : args)
    command << a.toString();

  const QString program = command.takeFirst();
  // startDetached: el proceso sobrevive a Omafiles y no deja zombie que
  // recoger -- exactamente la semantica de Quickshell.execDetached().
  QProcess::startDetached(program, command);
}

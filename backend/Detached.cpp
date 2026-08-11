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
  // startDetached: the process outlives Omafiles and leaves no zombie to
  // reap -- exactly the semantics of Quickshell.execDetached().
  QProcess::startDetached(program, command);
}

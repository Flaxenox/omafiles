#include "Env.h"

Env::Env(QObject *parent) : QObject(parent) {}

QString Env::get(const QString &name) const {
  // qEnvironmentVariable devuelve "" si la variable no esta definida, que
  // es justo lo que esperan los llamadores (homeDir, TabsState._initialHome).
  return qEnvironmentVariable(name.toLocal8Bit().constData());
}

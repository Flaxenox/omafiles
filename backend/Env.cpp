#include "Env.h"

Env::Env(QObject *parent) : QObject(parent) {}

QString Env::get(const QString &name) const {
  // qEnvironmentVariable returns "" if the variable is not defined, which is
  // exactly what the callers expect (homeDir, TabsState._initialHome).
  return qEnvironmentVariable(name.toLocal8Bit().constData());
}

void Env::set(const QString &name, const QString &value) {
  qputenv(name.toLocal8Bit().constData(), value.toLocal8Bit());
}

QString Env::version() const { return QStringLiteral(APP_VERSION); }

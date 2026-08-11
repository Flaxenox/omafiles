#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// C++ backend for services/Env.qml (Phase 5, josema). Gives REAL access to
// environment variables via qEnvironmentVariable -- QML does not expose them
// natively (that is why Quickshell.env() exists on the Quickshell side, and
// why Phase 4 had to inject HOME as a context property). This removes that
// trick: the standalone reads the environment directly.
//
// QML singleton (Omafiles.Backend.Env): stateless, a single instance is
// enough and it is consumed as Env.get("HOME").
class Env : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit Env(QObject *parent = nullptr);

  // Value of the variable `name`, or "" if it does not exist (same contract as
  // the Quickshell version over Quickshell.env()).
  Q_INVOKABLE QString get(const QString &name) const;
};

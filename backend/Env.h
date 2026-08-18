#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// Access to environment variables, plus the app's own version string.
// QML singleton (Omafiles.Backend.Env): consumed as Env.get("VAR").
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
  Q_INVOKABLE QString get(const QString &name) const;
  Q_INVOKABLE void set(const QString &name, const QString &value);

  // The application's version, from the single authoritative source
  // (CMakeLists.txt's project(... VERSION ...), threaded through as the
  // APP_VERSION compile definition) -- not a second, separately maintained
  // string. Reused here rather than adding a new singleton for one field
  // (V1_1_P1_PACKAGING).
  Q_INVOKABLE QString version() const;
};

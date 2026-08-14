#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// Access to environment variables.
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
};

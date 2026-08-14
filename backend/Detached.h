#pragma once

#include <QObject>
#include <QVariantList>
#include <qqmlregistration.h>

// "Fire and forget" execution of an external process -- no result tracking.
// QML singleton (Omafiles.Backend.Detached): stateless, consumed as Detached.run([...]).
//
// QML singleton (Omafiles.Backend.Detached): stateless, consumed as
// Detached.run([...]).
class Detached : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit Detached(QObject *parent = nullptr);

  // Launches `args` (program + arguments) detached and returns
  // immediately. No-op if the list is empty (same benign contract as
    Q_INVOKABLE void run(const QVariantList &args);
};

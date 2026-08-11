#pragma once

#include <QObject>
#include <QVariantList>
#include <qqmlregistration.h>

// C++ backend for services/Detached.qml (Phase 5.C, josema). "Fire and
// forget" execution of an external process -- no result tracking, no
// busy/cancel (for that, Omafiles.Backend.ProcessRunner). Backs with
// QProcess::startDetached the SAME API as the Quickshell implementation over
// Quickshell.execDetached() -- see services/Detached.qml for the contract.
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
  // Quickshell.execDetached with a program-less list).
  Q_INVOKABLE void run(const QVariantList &args);
};

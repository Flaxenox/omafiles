#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QString>
#include <qqmlregistration.h>

// C++ backend for services/ProcessWatcher.qml (Phase 5, josema). Backs with
// QProcess the SAME API as the Quickshell implementation over
// Quickshell.Io.Process + SplitParser -- see services/ProcessWatcher.qml
// for the contract. Unlike ProcessRunner, it watches a process that does
// NOT end on its own (inotifywait -m): it emits lineRead for each line of
// stdout instead of a final result. It is registered as the QML type
// Omafiles.Backend.ProcessWatcher and consumed by the adapter
// services/ProcessWatcher.qml.
class ProcessWatcher : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // true while the watched process is still alive.
  Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
  explicit ProcessWatcher(QObject *parent = nullptr);

  bool active() const;

  // Launches `args` (program + arguments) in monitor mode. If one was
  // already running it restarts it (same behaviour as the Quickshell version,
  // which set running=false before relaunching).
  Q_INVOKABLE void start(const QVariantList &args);

  // Stops the watched process. No-op if nothing is running.
  Q_INVOKABLE void stop();

signals:
  void activeChanged();
  // A line of output from the watched process (without the trailing
  // newline). The content usually does not matter -- it is enough to KNOW
  // that something changed.
  void lineRead(const QString &line);

private:
  void drainLines();

  QProcess *m_proc;
  QString m_buf; // leftover not terminated by a newline between reads
};

#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QString>
#include <qqmlregistration.h>

// Asynchronous line-by-line process output watcher backed by QProcess.
class ProcessWatcher : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // true while the watched process is still alive.
  Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
  explicit ProcessWatcher(QObject *parent = nullptr);

  bool active() const;

  // Launches `args` (program + arguments) in monitor mode. If one was
  // If already running, restarts the process.
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

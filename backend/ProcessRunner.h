#pragma once

#include <QObject>
#include <QProcess>
#include <QVariant>
#include <QVariantList>
#include <QString>
#include <qqmlregistration.h>

// C++ backend for services/ProcessRunner.qml (Phase 5, josema). Backs with a
// real QProcess the SAME API as the Quickshell implementation over
// Quickshell.Io.Process -- see services/ProcessRunner.qml for the contract
// and the reason for each method. It is registered as the QML type
// Omafiles.Backend.ProcessRunner and consumed by the adapter
// services/ProcessRunner.qml; the core (logic/) keeps
// writing `ProcessRunner { onFinished: ... }` without noticing.
//
// Not visual (QObject, not Item) on purpose: ProcessRunner was never a
// UI element, it was only instantiated inside an Item.
class ProcessRunner : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // true while a run is in progress -- for the pattern
  // "if already busy, warn and bail" repeated throughout the project.
  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
  explicit ProcessRunner(QObject *parent = nullptr);

  bool busy() const { return m_running; }

  // Launches `args` (program + arguments). group=true wraps the command
  // in its own process group (via setsid) so that cancel() also kills
  // the real children (cp/mv/zip under "bash -c"). Returns false
  // without doing anything if something is already running.
  Q_INVOKABLE bool start(const QVariantList &args, bool group = false);

  // Kills the running execution (its whole group if launched with group).
  // No-op if nothing is running. finished still fires (with
  // cancelled:true) when the process actually ends.
  Q_INVOKABLE void cancel();

signals:
  void busyChanged();
  // Always fires on completion (success, failure or cancelled) with the
  // full result: { exitCode, stdout, stderr, cancelled }.
  void finished(const QVariant &result);

private:
  void emitFinished(int exitCode);

  QProcess *m_proc;
  bool m_running = false;
  bool m_cancelled = false;
  bool m_group = false;
  QString m_stdout;
  QString m_stderr;
};

#include "ProcessRunner.h"

#include <csignal>
#include <sys/types.h>

ProcessRunner::ProcessRunner(QObject *parent)
    : QObject(parent), m_proc(new QProcess(this)) {
  // Accumulate as it arrives -- du/find/search can emit more than fits
  // in the internal buffer, it cannot all be deferred to the end.
  connect(m_proc, &QProcess::readyReadStandardOutput, this, [this]() {
    m_stdout += QString::fromUtf8(m_proc->readAllStandardOutput());
  });
  connect(m_proc, &QProcess::readyReadStandardError, this, [this]() {
    m_stderr += QString::fromUtf8(m_proc->readAllStandardError());
  });
  connect(m_proc, &QProcess::finished, this,
          [this](int exitCode, QProcess::ExitStatus) {
            // Flush whatever is left in the buffers before closing.
            m_stdout += QString::fromUtf8(m_proc->readAllStandardOutput());
            m_stderr += QString::fromUtf8(m_proc->readAllStandardError());
            emitFinished(exitCode);
          });
  connect(m_proc, &QProcess::errorOccurred, this,
          [this](QProcess::ProcessError err) {
            // FailedToStart does NOT fire finished() in QProcess -- the
            // cycle has to be closed by hand (nonexistent program, no
            // permissions). The rest of the errors happen with the process
            // already launched and do end in finished(), so they are ignored
            // here.
            if (err == QProcess::FailedToStart) {
              if (m_stderr.isEmpty())
                m_stderr = m_proc->errorString();
              emitFinished(127);
            }
          });
}

bool ProcessRunner::start(const QVariantList &args, bool group) {
  if (m_running || args.isEmpty())
    return false;

  m_cancelled = false;
  m_group = group;
  m_stdout.clear();
  m_stderr.clear();

  QStringList command;
  command.reserve(args.size() + 1);
  if (group)
    command << QStringLiteral("setsid");
  for (const QVariant &a : args)
    command << a.toString();

  const QString program = command.takeFirst();

  m_running = true;
  emit busyChanged();
  m_proc->start(program, command);
  return true;
}

void ProcessRunner::cancel() {
  if (!m_running)
    return;
  m_cancelled = true;

  if (m_group) {
    // Launched with setsid: the child leads its own group (pgid == pid),
    // so kill(-pid) also reaches its real descendants.
    const qint64 pid = m_proc->processId();
    if (pid > 0)
      ::kill(-static_cast<pid_t>(pid), SIGTERM);
  } else {
    // No group: only the immediate process, never touch our own pgid.
    m_proc->terminate();
  }
  // finished() will fire when the process actually dies, already with
  // cancelled:true (via m_cancelled).
}

void ProcessRunner::emitFinished(int exitCode) {
  if (!m_running)
    return; // guard against double emission (e.g. error + finished)
  m_running = false;

  const bool wasCancelled = m_cancelled;
  m_cancelled = false;

  QVariantMap result;
  result[QStringLiteral("exitCode")] = exitCode;
  result[QStringLiteral("stdout")] = m_stdout;
  result[QStringLiteral("stderr")] = m_stderr;
  result[QStringLiteral("cancelled")] = wasCancelled;

  emit busyChanged();
  emit finished(result);
}

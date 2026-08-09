#include "ProcessRunner.h"

#include <csignal>
#include <sys/types.h>

ProcessRunner::ProcessRunner(QObject *parent)
    : QObject(parent), m_proc(new QProcess(this)) {
  // Acumular a medida que llega -- du/find/search pueden emitir mas de lo
  // que cabe en el buffer interno, no se puede posponer todo al final.
  connect(m_proc, &QProcess::readyReadStandardOutput, this, [this]() {
    m_stdout += QString::fromUtf8(m_proc->readAllStandardOutput());
  });
  connect(m_proc, &QProcess::readyReadStandardError, this, [this]() {
    m_stderr += QString::fromUtf8(m_proc->readAllStandardError());
  });
  connect(m_proc, &QProcess::finished, this,
          [this](int exitCode, QProcess::ExitStatus) {
            // Vaciar lo que quede en los buffers antes de cerrar.
            m_stdout += QString::fromUtf8(m_proc->readAllStandardOutput());
            m_stderr += QString::fromUtf8(m_proc->readAllStandardError());
            emitFinished(exitCode);
          });
  connect(m_proc, &QProcess::errorOccurred, this,
          [this](QProcess::ProcessError err) {
            // FailedToStart NO dispara finished() en QProcess -- hay que
            // cerrar el ciclo a mano (programa inexistente, sin permisos).
            // El resto de errores ocurren con el proceso ya lanzado y si
            // acaban en finished(), asi que se ignoran aqui.
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
    // Lanzado con setsid: el hijo lidera su propio grupo (pgid == pid),
    // asi que kill(-pid) alcanza tambien a sus descendientes reales.
    const qint64 pid = m_proc->processId();
    if (pid > 0)
      ::kill(-static_cast<pid_t>(pid), SIGTERM);
  } else {
    // Sin grupo: solo el proceso inmediato, nunca tocar nuestro pgid.
    m_proc->terminate();
  }
  // finished() se disparara cuando el proceso muera de verdad, ya con
  // cancelled:true (via m_cancelled).
}

void ProcessRunner::emitFinished(int exitCode) {
  if (!m_running)
    return; // guarda contra doble emision (p.ej. error + finished)
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

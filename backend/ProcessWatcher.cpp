#include "ProcessWatcher.h"

ProcessWatcher::ProcessWatcher(QObject *parent)
    : QObject(parent), m_proc(new QProcess(this)) {
  connect(m_proc, &QProcess::readyReadStandardOutput, this,
          [this]() { drainLines(); });
  // active depends on the QProcess state -- notify on each transition.
  connect(m_proc, &QProcess::started, this,
          [this]() { emit activeChanged(); });
  connect(m_proc, &QProcess::finished, this,
          [this](int, QProcess::ExitStatus) { emit activeChanged(); });
}

bool ProcessWatcher::active() const {
  return m_proc->state() != QProcess::NotRunning;
}

void ProcessWatcher::start(const QVariantList &args) {
  if (args.isEmpty())
    return;

  // Restart: if there was a live watcher, kill it and wait for it to die
  // before relaunching (QProcess::start would complain if it is still
  // running). inotifywait -m responds to SIGTERM promptly.
  if (m_proc->state() != QProcess::NotRunning) {
    m_proc->terminate();
    if (!m_proc->waitForFinished(500))
      m_proc->kill();
  }

  m_buf.clear();

  QStringList command;
  command.reserve(args.size());
  for (const QVariant &a : args)
    command << a.toString();

  const QString program = command.takeFirst();
  m_proc->start(program, command);
}

void ProcessWatcher::stop() {
  if (m_proc->state() == QProcess::NotRunning)
    return;
  m_proc->terminate(); // finished() will emit activeChanged
}

void ProcessWatcher::drainLines() {
  m_buf += QString::fromUtf8(m_proc->readAllStandardOutput());

  int nl;
  while ((nl = m_buf.indexOf(QLatin1Char('\n'))) >= 0) {
    QString line = m_buf.left(nl);
    m_buf.remove(0, nl + 1);
    if (line.endsWith(QLatin1Char('\r')))
      line.chop(1);
    emit lineRead(line);
  }
}

#include "ProcessWatcher.h"

ProcessWatcher::ProcessWatcher(QObject *parent)
    : QObject(parent), m_proc(new QProcess(this)) {
  connect(m_proc, &QProcess::readyReadStandardOutput, this,
          [this]() { drainLines(); });
  // active depende del estado del QProcess -- avisar en cada transicion.
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

  // Reinicio: si habia un vigilante vivo, matarlo y esperar a que muera
  // antes de relanzar (QProcess::start se quejaria si sigue corriendo).
  // inotifywait -m responde a SIGTERM enseguida.
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
  m_proc->terminate(); // finished() emitira activeChanged
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

#include "ProcessWatcher.h"

#include <csignal>
#include <sys/types.h>

ProcessWatcher::ProcessWatcher(QObject *parent)
    : QObject(parent), m_proc(new QProcess(this)) {
  connect(m_proc, &QProcess::readyReadStandardOutput, this,
          [this]() { drainLines(); });
  connect(m_proc, &QProcess::readyReadStandardError, this, [this]() {
    m_stderr += QString::fromUtf8(m_proc->readAllStandardError());
  });
  // active depends on the QProcess state -- notify on each transition.
  connect(m_proc, &QProcess::started, this,
          [this]() { emit activeChanged(); });
  connect(m_proc, &QProcess::finished, this,
          [this](int exitCode, QProcess::ExitStatus) {
            // Flush whatever is left in the buffers before closing.
            drainLines();
            m_stderr += QString::fromUtf8(m_proc->readAllStandardError());
            const bool wasCancelled = m_cancelled;
            m_cancelled = false;
            emit activeChanged();
            emit finished(exitCode, wasCancelled, m_stdout, m_stderr);
          });
}

bool ProcessWatcher::active() const {
  return m_proc->state() != QProcess::NotRunning;
}

void ProcessWatcher::start(const QVariantList &args, bool group) {
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

  m_curLine.clear();
  m_curCol = 0;
  m_stdout.clear();
  m_stderr.clear();
  m_cancelled = false;
  m_group = group;

  QStringList command;
  command.reserve(args.size() + 1);
  if (group)
    command << QStringLiteral("setsid");
  for (const QVariant &a : args)
    command << a.toString();

  const QString program = command.takeFirst();
  m_proc->start(program, command);
}

void ProcessWatcher::stop() {
  if (m_proc->state() == QProcess::NotRunning)
    return;
  m_cancelled = true;
  if (m_group) {
    // Launched with setsid: the child leads its own group (pgid == pid),
    // so kill(-pid) also reaches its real descendants -- same convention
    // as ProcessRunner::cancel().
    const qint64 pid = m_proc->processId();
    if (pid > 0)
      ::kill(-static_cast<pid_t>(pid), SIGTERM);
  } else {
    m_proc->terminate();
  }
  // finished() will fire when the process actually dies, already with
  // cancelled:true.
}

void ProcessWatcher::drainLines() {
  const QString chunk = QString::fromUtf8(m_proc->readAllStandardOutput());
  m_stdout += chunk; // full record, see finished()'s doc comment
  if (chunk.isEmpty())
    return;

  // Minimal terminal cursor simulation (V1.1, archive extract/compress
  // progress) -- see the doc comment on the lineRead signal in the header
  // for why: 7z redraws its live "NN%" via \r, unrar via \b/backspace,
  // and a naive \n-only (or \r-only) split can't see either tool's
  // intermediate updates correctly, only ever the fully-settled final
  // line. \n commits the current line and starts a new one; \r returns
  // the cursor to column 0 (does NOT clear the line -- exactly how a real
  // terminal behaves, which also makes a plain \r\n line ending work
  // correctly here); \b moves the cursor back one column; anything else
  // overwrites at the cursor position (extending the line if the cursor
  // is at its end) and advances the cursor.
  for (const QChar &c : chunk) {
    if (c == QLatin1Char('\n')) {
      emit lineRead(m_curLine);
      m_curLine.clear();
      m_curCol = 0;
    } else if (c == QLatin1Char('\r')) {
      m_curCol = 0;
    } else if (c == QChar(0x08)) {
      if (m_curCol > 0)
        --m_curCol;
    } else {
      if (m_curCol < m_curLine.size())
        m_curLine[m_curCol] = c;
      else
        m_curLine.append(c);
      ++m_curCol;
    }
  }
  // The current (possibly still mid-redraw) line state too, not only
  // completed \n-terminated lines -- this is what actually makes a live
  // "NN%" visible before the item it belongs to is fully done.
  emit lineRead(m_curLine);
}

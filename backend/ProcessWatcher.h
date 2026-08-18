#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QString>
#include <qqmlregistration.h>

// Asynchronous line-by-line process output watcher backed by QProcess.
//
// Originally just a live directory-watch helper (line content didn't
// matter, only that something changed). Extended (V1.1, progress bars for
// archive extract/compress) with `group`, `stop()` cancellation, and a real
// `finished` signal, so it now also works as a progress-observing
// counterpart to ProcessRunner: ProcessRunner collects everything and
// reports once at the end; this streams each stdout line AS IT ARRIVES
// (e.g. one "extracting: <name>" per file from unzip/7z/tar/unrar) while
// still reporting the same completion info ProcessRunner does.
class ProcessWatcher : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // true while the watched process is still alive.
  Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
  explicit ProcessWatcher(QObject *parent = nullptr);

  bool active() const;

  // Launches `args` (program + arguments) in monitor mode. If one was
  // already running, it is stopped first and this one replaces it.
  // group=true wraps it in its own process group (via setsid), same
  // convention and reason as ProcessRunner::start() -- so stop() can reach
  // real children too (e.g. unzip/7z running under "bash -c").
  Q_INVOKABLE void start(const QVariantList &args, bool group = false);

  // Stops the watched process (its whole group if launched with
  // group=true). No-op if nothing is running. finished still fires (with
  // cancelled:true) when the process actually ends.
  Q_INVOKABLE void stop();

signals:
  void activeChanged();
  // The CURRENT rendered state of the process's active output line, as a
  // basic terminal would show it -- delivered again each time it changes,
  // not just once a real newline terminates it. Needed because in-place
  // progress redraws don't agree on one control character: 7z rewrites via
  // \r (return to column 0, overwrite); unrar erases via \b/backspace
  // (confirmed directly against a real archive, 2026-08-18: "...  0%\b\b\b\b
  // 1%", never a single \r). A naive \n/\r-only split saw neither tool's
  // live updates correctly -- \r-only caught 7z but not unrar, and a plain
  // \n-only split caught neither, only ever seeing the fully-settled line
  // once the item was completely done. This runs a minimal cursor
  // simulation (\n commits + clears, \r returns to column 0, \b moves the
  // cursor back one column, anything else overwrites at the cursor and
  // advances it) so lineRead reflects "what a terminal would show right
  // now" regardless of which control character a given tool prefers.
  void lineRead(const QString &line);
  // Fires once when the watched process actually exits (success, failure,
  // or cancelled via stop()). stdoutText is the FULL accumulated stdout
  // (same content already delivered piecemeal via lineRead) -- needed
  // because callers running under a fake PTY (see ActionEngine.qml's
  // runActionWithProgress()/_ptyArgs(), V1.1) get the child's stderr
  // merged into stdout instead (a real, PTY-emulation side effect
  // confirmed directly, 2026-08-18: a fake-tty-wrapped failure had a
  // real error message on stdout and an EMPTY stderr), so stderrText
  // alone can no longer be trusted as "the error text, if any".
  void finished(int exitCode, bool cancelled, const QString &stdoutText, const QString &stderrText);

private:
  void drainLines();

  QProcess *m_proc;
  QString m_curLine;  // current line's rendered content (terminal cursor simulation)
  int m_curCol = 0;    // cursor column within m_curLine
  QString m_stdout;
  QString m_stderr;
  bool m_group = false;
  bool m_cancelled = false;
};

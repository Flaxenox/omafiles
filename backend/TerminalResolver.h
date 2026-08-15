#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <qqmlregistration.h>

// High-speed native desktop workspace integration (Terminal, Clipboard).
class TerminalResolver : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit TerminalResolver(QObject *parent = nullptr);

  // Launches the user's preferred terminal emulator in `directory`.
  // Automatically detects modern Wayland/X11 terminals.
  Q_INVOKABLE void launchTerminal(const QString &directory);

  // Copies text directly to the system clipboard (Wayland/X11) natively,
  // without piping to `wl-copy`.
  Q_INVOKABLE void copyText(const QString &text);

  // Path copying helpers
  Q_INVOKABLE void copyPathsAbsolute(const QStringList &paths);
  Q_INVOKABLE void copyPathsRelative(const QStringList &paths, const QString &baseDir);
  Q_INVOKABLE void copyPathsUri(const QStringList &paths);
};

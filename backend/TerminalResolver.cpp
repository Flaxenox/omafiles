#include "TerminalResolver.h"

#include <QClipboard>
#include <QDir>
#include <QGuiApplication>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>

TerminalResolver::TerminalResolver(QObject *parent) : QObject(parent) {}

void TerminalResolver::launchTerminal(const QString &directory) {
  QStringList candidates;
  
  // 1. User's explicit choice
  QByteArray termEnv = qgetenv("TERMINAL");
  if (!termEnv.isEmpty()) {
    candidates << QString::fromLocal8Bit(termEnv);
  }

  // 2. Known terminal emulators (Hyprland / modern Wayland focused, then legacy)
  // No xdg-terminal-exec wrapper needed per DHH philosophy (direct implementation)
  candidates << QStringLiteral("kitty")
             << QStringLiteral("foot")
             << QStringLiteral("alacritty")
             << QStringLiteral("wezterm")
             << QStringLiteral("ghostty")
             << QStringLiteral("gnome-terminal")
             << QStringLiteral("konsole")
             << QStringLiteral("xfce4-terminal")
             << QStringLiteral("xterm");

  for (const QString &term : candidates) {
    QString exe = QStandardPaths::findExecutable(term);
    if (!exe.isEmpty()) {
      QProcess process;
      process.setProgram(exe);
      process.setWorkingDirectory(directory);
      
      if (term == QLatin1String("gnome-terminal")) {
        process.setArguments({QStringLiteral("--working-directory"), directory});
      }
      
      process.startDetached();
      return;
    }
  }
}

void TerminalResolver::copyText(const QString &text) {
  if (qgetenv("OMAFILES_SELFCHECK") == "1") return;
  if (QClipboard *clipboard = QGuiApplication::clipboard()) {
    clipboard->setText(text);
  }
}

// Shell-safe path quoting helper
static QString quoteShell(const QString &path) {
  QString escaped = path;
  escaped.replace(QLatin1Char('\''), QLatin1String("'\\''"));
  return QLatin1Char('\'') + escaped + QLatin1Char('\'');
}

void TerminalResolver::copyPathsAbsolute(const QStringList &paths) {
  QStringList quoted;
  for (const QString &p : paths) {
    quoted << quoteShell(p);
  }
  copyText(quoted.join(QLatin1Char(' ')));
}

void TerminalResolver::copyPathsRelative(const QStringList &paths, const QString &baseDir) {
  QDir dir(baseDir);
  QStringList relPaths;
  for (const QString &p : paths) {
    relPaths << dir.relativeFilePath(p);
  }
  copyText(relPaths.join(QLatin1Char('\n')));
}

#include <QMimeData>

void TerminalResolver::copyPathsUri(const QStringList &paths) {
  if (qgetenv("OMAFILES_SELFCHECK") == "1") return;
  QList<QUrl> urls;
  for (const QString &p : paths) {
    urls << QUrl::fromLocalFile(p);
  }
  
  if (QClipboard *clipboard = QGuiApplication::clipboard()) {
    QMimeData *mimeData = new QMimeData();
    mimeData->setUrls(urls);
    clipboard->setMimeData(mimeData);
  }
}

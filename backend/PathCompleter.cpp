#include "PathCompleter.h"

#include <QDir>
#include <QFileInfo>

PathCompleter::PathCompleter(QObject *parent) : QObject(parent) {}

QString PathCompleter::expandTilde(const QString &input) const {
  if (input == QLatin1String("~"))
    return QDir::homePath();
  if (input.startsWith(QLatin1String("~/")))
    return QDir::homePath() + input.mid(1);
  return input;
}

QStringList PathCompleter::complete(const QString &input, const QString &base,
                                    int limit) const {
  // 1) Resolve the directory part and the prefix to complete. It is split on
  //    the LAST "/": what comes before is the folder to list, what comes
  //    after is the prefix of the name the user is typing.
  const QString expanded = expandTilde(input);

  QString dirPart;
  QString prefix;
  const int slash = expanded.lastIndexOf(QLatin1Char('/'));
  if (slash < 0) {
    // No "/": relative to `base`, completing a bare name inside it.
    dirPart = base;
    prefix = expanded;
  } else {
    dirPart = expanded.left(slash + 1); // keeps the "/" -> absolute "/" ok
    prefix = expanded.mid(slash + 1);
  }

  // Resolve dirPart to a real absolute path. QDir resolves "." / ".." and the
  // relative part against `base` (cd to base first via composed path).
  QDir dir;
  if (dirPart.startsWith(QLatin1Char('/'))) {
    dir = QDir(dirPart);
  } else {
    dir = QDir(base);
    if (!dirPart.isEmpty())
      dir = QDir(dir.absoluteFilePath(dirPart));
  }
  if (!dir.exists())
    return {};

  // 2) List directories only. Hidden only if the prefix starts with
  //    ".", like a shell (do not clutter with dotfiles on a normal complete).
  QDir::Filters filters = QDir::Dirs | QDir::NoDotAndDotDot;
  if (prefix.startsWith(QLatin1Char('.')))
    filters |= QDir::Hidden;
  const QStringList names =
      dir.entryList(filters, QDir::Name | QDir::LocaleAware);

  // smart-case: case-sensitive only if the prefix has any uppercase.
  Qt::CaseSensitivity cs = Qt::CaseInsensitive;
  for (const QChar &c : prefix) {
    if (c.isUpper()) {
      cs = Qt::CaseSensitive;
      break;
    }
  }

  const QString dirAbs = dir.absolutePath();
  QStringList out;
  for (const QString &name : names) {
    if (!prefix.isEmpty() && !name.startsWith(prefix, cs))
      continue;
    // Absolute path + trailing "/": ready to navigate or keep typing.
    QString full = dirAbs;
    if (!full.endsWith(QLatin1Char('/')))
      full += QLatin1Char('/');
    full += name + QLatin1Char('/');
    out.append(full);
    if (out.size() >= limit)
      break;
  }
  return out;
}

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
  // 1) Resolver la parte de directorio y el prefijo a completar. Se parte por
  //    la ÚLTIMA "/": lo de antes es la carpeta que hay que listar, lo de
  //    después el prefijo del nombre que el usuario está tecleando.
  const QString expanded = expandTilde(input);

  QString dirPart;
  QString prefix;
  const int slash = expanded.lastIndexOf(QLatin1Char('/'));
  if (slash < 0) {
    // Sin "/": relativo a `base`, completando un nombre suelto dentro de él.
    dirPart = base;
    prefix = expanded;
  } else {
    dirPart = expanded.left(slash + 1); // conserva la "/" -> "/" absoluto ok
    prefix = expanded.mid(slash + 1);
  }

  // Resolver dirPart a una ruta absoluta real. QDir resuelve "." / ".." y lo
  // relativo contra `base` (cd a base primero vía ruta compuesta).
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

  // 2) Listar solo directorios. Ocultos únicamente si el prefijo empieza por
  //    ".", igual que una shell (no ensuciar con dotfiles al completar normal).
  QDir::Filters filters = QDir::Dirs | QDir::NoDotAndDotDot;
  if (prefix.startsWith(QLatin1Char('.')))
    filters |= QDir::Hidden;
  const QStringList names =
      dir.entryList(filters, QDir::Name | QDir::LocaleAware);

  // smart-case: sensible a mayúsculas solo si el prefijo trae alguna.
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
    // Ruta absoluta + "/" final: lista para navegar o seguir tecleando.
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

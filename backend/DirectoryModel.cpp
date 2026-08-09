#include "DirectoryModel.h"

#include <QFile>
#include <QRunnable>
#include <QThreadPool>

#include <algorithm>
#include <string>

#include <dirent.h>
#include <locale.h>
#include <sys/stat.h>
#include <unistd.h>
#include <wchar.h>
#include <wctype.h>

namespace {

// Ordena dos nombres como lo hace `sort -f` de list-dir.sh. Primario:
// plegando la caja y colacionando con la MISMA collation de glibc
// (LC_COLLATE del entorno) -- se pliega a minuscula con towlower_l; la
// direccion del plegado es indiferente porque la caja es un peso terciario
// que el plegado anula por igual en ambos operandos.
//
// Desempate: cuando el plegado los hace iguales (p.ej. "hyprland" y
// "Hyprland" en /usr/bin), `sort -f` cae a comparar los nombres SIN plegar
// con la collation del locale, que en glibc pone la minuscula antes que la
// mayuscula. Reproducirlo hace el orden deterministico (std::sort no
// garantiza nada en los empates) y exactamente igual al del script.
bool nameLess(const QString &a, const QString &b, locale_t loc) {
  std::wstring wa = a.toStdWString();
  std::wstring wb = b.toStdWString();
  std::wstring fa = wa, fb = wb;
  for (wchar_t &c : fa)
    c = towlower_l(c, loc);
  for (wchar_t &c : fb)
    c = towlower_l(c, loc);
  const int folded = wcscoll_l(fa.c_str(), fb.c_str(), loc);
  if (folded != 0)
    return folded < 0;
  return wcscoll_l(wa.c_str(), wb.c_str(), loc) < 0;
}

} // namespace

DirectoryModel::DirectoryModel(QObject *parent) : QAbstractListModel(parent) {}

DirectoryModel::Result DirectoryModel::scan(const QString &path,
                                            bool showHidden) {
  Result r;
  const QByteArray p = QFile::encodeName(path);

  // Codigos de error espejo de list-dir.sh (stat/-d/-r-x/opendir siguen
  // symlinks igual que los tests de bash [[ -e ]]/[[ -d ]]/[[ -r&&-x ]]).
  struct stat st;
  if (::stat(p.constData(), &st) != 0) {
    r.error = 3; // no existe (-e falso; incluye symlink colgante)
    return r;
  }
  if (!S_ISDIR(st.st_mode)) {
    r.error = 4; // no es carpeta (-d falso)
    return r;
  }
  if (::access(p.constData(), R_OK | X_OK) != 0) {
    r.error = 2; // sin permiso de lectura/ejecucion
    return r;
  }
  DIR *dir = ::opendir(p.constData());
  if (!dir) {
    r.error = 1; // otro (equivalente al cd que fallaba)
    return r;
  }

  // Collation propia de esta llamada (thread-safe, sin estado compartido).
  locale_t loc = ::newlocale(LC_COLLATE_MASK | LC_CTYPE_MASK, "", (locale_t)0);

  QVector<Entry> dirs;
  QVector<Entry> files;

  struct dirent *de;
  while ((de = ::readdir(dir)) != nullptr) {
    const char *n = de->d_name;
    // Saltar "." y ".." siempre.
    if (n[0] == '.' && (n[1] == '\0' || (n[1] == '.' && n[2] == '\0')))
      continue;
    // Dotfiles solo con showHidden (equivale a shopt dotglob del script).
    if (!showHidden && n[0] == '.')
      continue;

    QByteArray full = p;
    full += '/';
    full += n;

    struct stat s;
    struct stat ls;
    const bool lok = (::lstat(full.constData(), &ls) == 0);
    const bool isLink = lok && S_ISLNK(ls.st_mode);
    const bool followed = (::stat(full.constData(), &s) == 0);

    Entry e;
    e.name = QFile::decodeName(n);
    e.isSymlink = isLink;
    e.link = isLink ? (followed ? QStringLiteral("valid")
                                : QStringLiteral("broken"))
                    : QString();
    e.isDir = followed && S_ISDIR(s.st_mode);

    if (e.isDir) {
      e.type = QStringLiteral("dir");
      e.size = 0; // el script fuerza tamano 0 en carpetas
      e.mtime = static_cast<qint64>(s.st_mtime);
      dirs.push_back(std::move(e));
    } else {
      e.type = QStringLiteral("file");
      if (followed) {
        // Fichero normal o symlink que resuelve: datos del destino.
        e.size = static_cast<qint64>(s.st_size);
        e.mtime = static_cast<qint64>(s.st_mtime);
      } else if (lok) {
        // Symlink roto: fallback a lstat (tamano = longitud del target,
        // mtime = del propio enlace), igual que el `stat -c` sin -L.
        e.size = static_cast<qint64>(ls.st_size);
        e.mtime = static_cast<qint64>(ls.st_mtime);
      } else {
        e.size = 0;
        e.mtime = 0;
      }
      files.push_back(std::move(e));
    }
  }
  ::closedir(dir);

  const auto cmp = [loc](const Entry &a, const Entry &b) {
    return nameLess(a.name, b.name, loc);
  };
  std::sort(dirs.begin(), dirs.end(), cmp);
  std::sort(files.begin(), files.end(), cmp);

  if (loc)
    ::freelocale(loc);

  // Carpetas primero, luego ficheros.
  r.rows = std::move(dirs);
  r.rows += files;
  return r;
}

void DirectoryModel::list(const QString &path, bool showHidden) {
  m_path = path;
  const quint64 generation = ++m_generation;

  if (!m_loading) {
    m_loading = true;
    emit loadingChanged();
  }

  // El escaneo pesado (stat de cada entrada) va a un hilo del pool para no
  // bloquear la UI; el resultado se aplica de vuelta en el hilo de UI. Un
  // resultado de una generacion vieja (navegacion rapida) se descarta.
  QThreadPool::globalInstance()->start(QRunnable::create(
      [this, path, showHidden, generation]() {
        Result result = DirectoryModel::scan(path, showHidden);
        QMetaObject::invokeMethod(
            this,
            [this, result = std::move(result), generation]() mutable {
              apply(std::move(result), generation);
            },
            Qt::QueuedConnection);
      }));
}

void DirectoryModel::apply(Result result, quint64 generation) {
  // Descartar si ya se pidio otro listado despues de este.
  if (generation != m_generation)
    return;

  beginResetModel();
  m_rows = std::move(result.rows);
  endResetModel();

  if (m_error != result.error) {
    m_error = result.error;
    emit errorChanged();
  }
  if (m_loading) {
    m_loading = false;
    emit loadingChanged();
  }
  emit countChanged();
  emit listed();
}

int DirectoryModel::rowCount(const QModelIndex &parent) const {
  if (parent.isValid())
    return 0;
  return static_cast<int>(m_rows.size());
}

QVariant DirectoryModel::data(const QModelIndex &index, int role) const {
  if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
    return QVariant();

  const Entry &e = m_rows.at(index.row());
  switch (role) {
  case NameRole:
    return e.name;
  case PathRole:
    return m_path.isEmpty() ? e.name : (m_path + QLatin1Char('/') + e.name);
  case TypeRole:
    return e.type;
  case IsDirRole:
    return e.isDir;
  case IsSymlinkRole:
    return e.isSymlink;
  case LinkRole:
    return e.link;
  case SizeRole:
    return e.size;
  case MtimeRole:
    return e.mtime;
  default:
    return QVariant();
  }
}

QHash<int, QByteArray> DirectoryModel::roleNames() const {
  return {
      {NameRole, "name"},         {PathRole, "path"},
      {TypeRole, "type"},         {IsDirRole, "isDir"},
      {IsSymlinkRole, "isSymlink"}, {LinkRole, "link"},
      {SizeRole, "size"},         {MtimeRole, "mtime"},
  };
}

QVariantList DirectoryModel::entries() const {
  QVariantList out;
  out.reserve(m_rows.size());
  for (const Entry &e : m_rows) {
    // Mismas cinco claves que producia Utils.parseEntries(list-dir.sh),
    // para comparar y, luego, sustituir sin que cambie el consumidor.
    QVariantMap m;
    m[QStringLiteral("type")] = e.type;
    m[QStringLiteral("name")] = e.name;
    m[QStringLiteral("size")] = e.size;
    m[QStringLiteral("mtime")] = e.mtime;
    m[QStringLiteral("link")] = e.link;
    out.push_back(m);
  }
  return out;
}

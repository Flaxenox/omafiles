#include "DirectoryModel.h"

#include <QFile>
#include <QFileSystemWatcher>
#include <QRunnable>
#include <QThreadPool>

#include <algorithm>

#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

inline bool asciiDigit(QChar c) {
  return c.unicode() >= u'0' && c.unicode() <= u'9';
}

// Compara nombres como Utils.naturalCompare(a.toLowerCase(), b.toLowerCase())
// del lado QML: number-aware (los dígitos ASCII se comparan por VALOR, no
// carácter a carácter) y case-insensitive. Fase 10.A: este es el orden
// VISIBLE. Antes se ordenaba aquí por collation de glibc (paridad byte a byte
// con list-dir.sh) y luego SortOps re-ordenaba SIEMPRE en JS con este mismo
// naturalCompare, tirando el trabajo de C++; ahora se hace una sola vez aquí
// y SortOps ya no re-ordena el caso por defecto (name/asc). Devuelve <0, 0,
// >0.
//
// Fase 27 (PERF_AUDIT_RC1): ESPERA los dos nombres YA en minúsculas. std::sort
// hace O(n log n) comparaciones, así que hacer `.toLower()` aquí dentro
// asignaba ~2·n·log n QString por listado (tormenta de asignaciones medida en
// el benchmark). El toLower se hace ahora UNA vez por entrada en sortInto
// (transformada de Schwartz) y esta función opera sobre las claves ya bajadas.
int naturalCompareLowered(const QString &a, const QString &b) {
  int i = 0, j = 0;
  const int na = a.size(), nb = b.size();
  while (i < na && j < nb) {
    const bool da = asciiDigit(a[i]);
    const bool db = asciiDigit(b[j]);
    if (da && db) {
      // Runs de dígitos: comparar como enteros (sin ceros a la izquierda;
      // más largo = mayor; igual longitud -> lexicográfico).
      int i2 = i, j2 = j;
      while (i2 < na && asciiDigit(a[i2]))
        i2++;
      while (j2 < nb && asciiDigit(b[j2]))
        j2++;
      int sa = i, sb = j;
      while (sa < i2 - 1 && a[sa] == u'0')
        sa++;
      while (sb < j2 - 1 && b[sb] == u'0')
        sb++;
      const int la = i2 - sa, lb = j2 - sb;
      if (la != lb)
        return la - lb;
      const int c = QStringView(a).mid(sa, la).compare(QStringView(b).mid(sb, lb));
      if (c != 0)
        return c;
      i = i2;
      j = j2;
    } else if (da != db) {
      // Dígito antes que no-dígito (en JS: numero - Infinity < 0).
      return da ? -1 : 1;
    } else {
      // Runs de no-dígitos: comparar con la collation del locale (como el
      // .localeCompare() de JS).
      int i2 = i, j2 = j;
      while (i2 < na && !asciiDigit(a[i2]))
        i2++;
      while (j2 < nb && !asciiDigit(b[j2]))
        j2++;
      const int c =
          QString::localeAwareCompare(a.mid(i, i2 - i), b.mid(j, j2 - j));
      if (c != 0)
        return c;
      i = i2;
      j = j2;
    }
  }
  return (na - i) - (nb - j);
}

// Escanea UN directorio y APPEND-ea sus entradas a dirs/files (sin
// ordenar; el llamador ordena una vez al final). Devuelve el codigo de
// error espejo de list-dir.sh: 0 ok, 2 sin permiso, 3 no existe, 4 no es
// carpeta, 1 otro. En listado agregado (papelera) el llamador ignora el
// codigo y simplemente se salta las carpetas que fallan.
int gatherOne(const QByteArray &p, bool showHidden,
              QVector<DirectoryModel::Entry> &dirs,
              QVector<DirectoryModel::Entry> &files) {
  // stat/-d/-r-x siguen symlinks igual que los tests de bash del script.
  struct stat st;
  if (::stat(p.constData(), &st) != 0)
    return 3; // no existe (-e falso; incluye symlink colgante)
  if (!S_ISDIR(st.st_mode))
    return 4; // no es carpeta (-d falso)
  if (::access(p.constData(), R_OK | X_OK) != 0)
    return 2; // sin permiso de lectura/ejecucion
  DIR *dir = ::opendir(p.constData());
  if (!dir)
    return 1; // otro (equivalente al cd que fallaba)

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

    // Fase 27 (PERF_AUDIT_RC1): una sola syscall en el caso común. Antes se
    // hacían SIEMPRE lstat + stat (2 syscalls/entrada -> 200k a 100k ficheros).
    // Para un NO-symlink stat==lstat, así que el segundo era redundante: se
    // hace lstat primero y solo se sigue con stat cuando de verdad hay un
    // enlace que resolver. Comportamiento idéntico (un path que stat resuelve
    // pero lstat no es imposible: lstat no deja de resolver el path, solo no
    // deref-a el último componente).
    struct stat ls;
    const bool lok = (::lstat(full.constData(), &ls) == 0);
    const bool isLink = lok && S_ISLNK(ls.st_mode);
    struct stat s;
    bool followed;
    if (isLink) {
      followed = (::stat(full.constData(), &s) == 0); // seguir el enlace
    } else {
      s = ls; // no-symlink: lstat ya es el stat, sin segunda syscall
      followed = lok;
    }

    DirectoryModel::Entry e;
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
  return 0;
}

// Ordena UN grupo por nombre (case-insensitive, number-aware) con una
// transformada de Schwartz: baja cada nombre a minúsculas UNA sola vez, ordena
// un vector de índices sobre esas claves precomputadas, y reordena el grupo con
// un único barrido de moves al final. Antes (Fase 10.A) el toLower vivía dentro
// del comparador, que std::sort llama O(n log n) veces -> a 100k eran ~1,7M
// comparaciones × 2 toLower = tormenta de asignaciones (Fase 27, medido).
void sortGroup(QVector<DirectoryModel::Entry> &v) {
  const int n = v.size();
  if (n < 2)
    return;
  QVector<QString> keys(n);
  for (int i = 0; i < n; ++i)
    keys[i] = v[i].name.toLower();
  QVector<int> idx(n);
  for (int i = 0; i < n; ++i)
    idx[i] = i;
  std::sort(idx.begin(), idx.end(), [&keys](int a, int b) {
    return naturalCompareLowered(keys[a], keys[b]) < 0;
  });
  QVector<DirectoryModel::Entry> out;
  out.reserve(n);
  for (int i : idx)
    out.push_back(std::move(v[i]));
  v = std::move(out);
}

// Ordena dirs y files por nombre (carpetas primero al concatenar) con la
// collation de glibc, y los deja en rows.
void sortInto(QVector<DirectoryModel::Entry> &dirs,
              QVector<DirectoryModel::Entry> &files,
              QVector<DirectoryModel::Entry> &rows) {
  sortGroup(dirs);
  sortGroup(files);
  rows = std::move(dirs); // carpetas primero, luego ficheros
  rows += files;
}

} // namespace

DirectoryModel::DirectoryModel(QObject *parent) : QObject(parent) {}

DirectoryModel::~DirectoryModel() {
  // Cortar la entrega de cualquier worker en vuelo: bajo el lock, marcar
  // muerto. Un worker que aun no haya entregado vera alive=false y no hara
  // invokeMethod(this); uno que ya lo tenga cogido nos bloquea aqui hasta
  // que suelte (entrega instantanea, solo postea un evento).
  std::lock_guard<std::mutex> lk(m_life->mtx);
  m_life->alive = false;
}

DirectoryModel::Result DirectoryModel::scan(const QString &path,
                                            bool showHidden) {
  Result r;
  QVector<Entry> dirs, files;
  r.error = gatherOne(QFile::encodeName(path), showHidden, dirs, files);
  if (r.error == 0)
    sortInto(dirs, files, r.rows);
  return r;
}

DirectoryModel::Result DirectoryModel::scanMany(const QStringList &paths,
                                                bool showHidden) {
  // Papelera: fusiona el contenido de varias raices. Las que fallan (no
  // existen / sin permiso) se saltan en silencio, igual que el
  // `[[ -d "$root/files" ]] &&` de list-trash.sh. error siempre 0.
  Result r;
  QVector<Entry> dirs, files;
  for (const QString &path : paths)
    gatherOne(QFile::encodeName(path), showHidden, dirs, files);
  sortInto(dirs, files, r.rows);
  return r;
}

void DirectoryModel::startScan(std::function<Result()> job) {
  const quint64 generation = ++m_generation;
  // El escaneo pesado (stat de cada entrada) va a un hilo del pool para no
  // bloquear la UI; el resultado se aplica de vuelta en el hilo de UI. Un
  // resultado de una generacion vieja (navegacion rapida) se descarta.
  auto life = m_life; // copia del control block, sobrevive al modelo
  QThreadPool::globalInstance()->start(QRunnable::create(
      [this, life, job = std::move(job), generation]() {
        Result result = job();
        // Entrega segura: solo invocar sobre `this` si sigue vivo. El
        // destructor toma este mismo lock, asi que o vemos alive=false (y no
        // tocamos el objeto muerto), o lo tenemos cogido y el destructor
        // espera a que soltemos.
        std::lock_guard<std::mutex> lk(life->mtx);
        if (!life->alive)
          return;
        QMetaObject::invokeMethod(
            this,
            [this, result = std::move(result), generation]() mutable {
              apply(std::move(result), generation);
            },
            Qt::QueuedConnection);
      }));
}

void DirectoryModel::list(const QString &path, bool showHidden) {
  startScan([path, showHidden]() { return scan(path, showHidden); });
}

void DirectoryModel::listMany(const QStringList &paths, bool showHidden) {
  // Agregado de varias raices (papelera). Los consumidores usan el array
  // `entries` (name/type/size/mtime/link) + trashInfo.
  startScan([paths, showHidden]() { return scanMany(paths, showHidden); });
}

bool DirectoryModel::watch(const QString &path) {
  if (!m_watcher) {
    m_watcher = new QFileSystemWatcher(this);
    // QFileSystemWatcher usa inotify del kernel directamente (sin forkear
    // inotifywait). Reemite un directoryChanged() plano; el debounce y el
    // refresco -- con su guarda de no-refrescar-a-mitad-de-renombrado --
    // siguen en NavigationController.
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this,
            [this](const QString &changed) {
              // Token de cancelacion: solo propagar el evento si es de la
              // carpeta que se vigila AHORA. Un evento tardio de un watcher
              // viejo (ruta distinta) se descarta -> no repuebla la carpeta
              // a la que el usuario ya ha navegado.
              if (changed == m_watchedPath)
                emit directoryChanged();
            });
  }
  // Vigilar solo un directorio a la vez: quitar el anterior.
  const QStringList prev = m_watcher->directories();
  if (!prev.isEmpty())
    m_watcher->removePaths(prev);
  m_watchedPath = path;
  return m_watcher->addPath(path); // false si no se pudo (limite/ruta)
}

void DirectoryModel::unwatch() {
  // Invalidar el token: cualquier evento en vuelo de un watcher previo se
  // descartara al no coincidir con m_watchedPath (vacio).
  m_watchedPath.clear();
  if (!m_watcher)
    return;
  const QStringList prev = m_watcher->directories();
  if (!prev.isEmpty())
    m_watcher->removePaths(prev);
}

void DirectoryModel::apply(Result result, quint64 generation) {
  // Descartar si ya se pidio otro listado despues de este.
  if (generation != m_generation)
    return;

  m_rows = std::move(result.rows);

  if (m_error != result.error) {
    m_error = result.error;
    emit errorChanged();
  }
  emit listed();
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

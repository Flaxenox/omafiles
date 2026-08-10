#include "FileOperations.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRunnable>
#include <QStorageInfo>
#include <QThreadPool>
#include <QUrl>
#include <QVariantMap>

#include <cerrno>
#include <cstdio>
#include <unistd.h>

namespace {

constexpr qint64 kChunk = 1 << 20; // 1 MiB

// ¿Existe una ENTRADA de directorio en `path`? (lstat, no stat.) A diferencia
// de QFileInfo::exists() -- que sigue los symlinks y por tanto es ciega a un
// symlink roto -- esto cuenta como existente cualquier cosa que ocupe el
// nombre, incluido un symlink cuyo destino no existe. Es el criterio ÚNICO de
// "conflicto de destino" que comparten existingPaths() (la comprobación de la
// UI) y los guards sin-overwrite de copy()/move(): antes divergían del `test
// -e` del shell justo en el caso del symlink roto (BUG-01, Hardening-1). Mismo
// idioma que ya usaban removeTree/trash/restore más abajo.
inline bool entryExists(const QString &path) {
  const QFileInfo fi(path);
  return fi.exists() || fi.isSymLink();
}

// Tamano total (recursivo) de una ruta, para el porcentaje de progreso.
qint64 treeSize(const QString &path) {
  QFileInfo fi(path);
  if (fi.isSymLink())
    return 0;
  if (fi.isDir()) {
    qint64 total = 0;
    QDirIterator it(path, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden |
                              QDir::System,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
      it.next();
      const QFileInfo e = it.fileInfo();
      if (e.isFile() && !e.isSymLink())
        total += e.size();
    }
    return total;
  }
  return fi.size();
}

// Copia un fichero por trozos, informando de bytes copiados via cb.
// `cancelled` se comprueba entre trozos: si se activa, aborta con err.
bool copyFile(const QString &src, const QString &dst, qint64 &copied,
              const std::function<void(qint64)> &cb,
              const std::atomic<bool> &cancelled, QString &err) {
  QFile in(src);
  if (!in.open(QIODevice::ReadOnly)) {
    err = QStringLiteral("cannot read %1").arg(src);
    return false;
  }
  QFile out(dst);
  if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
    err = QStringLiteral("cannot write %1").arg(dst);
    return false;
  }
  QByteArray buf;
  buf.resize(kChunk);
  qint64 n;
  while ((n = in.read(buf.data(), kChunk)) > 0) {
    if (cancelled.load()) {
      err = QStringLiteral("cancelled");
      return false;
    }
    if (out.write(buf.constData(), n) != n) {
      err = QStringLiteral("write failed on %1").arg(dst);
      return false;
    }
    copied += n;
    cb(copied);
  }
  out.close();
  in.close();
  out.setPermissions(in.permissions()); // preservar modo
  return true;
}

// Copia recursiva (ficheros, carpetas y symlinks como symlinks).
bool copyTree(const QString &src, const QString &dst, qint64 &copied,
              const std::function<void(qint64)> &cb,
              const std::atomic<bool> &cancelled, QString &err) {
  if (cancelled.load()) {
    err = QStringLiteral("cancelled");
    return false;
  }
  QFileInfo si(src);
  if (si.isSymLink()) {
    // Recrear el enlace, no seguirlo.
    return QFile::link(si.symLinkTarget(), dst);
  }
  if (si.isDir()) {
    if (!QDir().mkpath(dst)) {
      err = QStringLiteral("cannot create %1").arg(dst);
      return false;
    }
    const QFileInfoList entries =
        QDir(src).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot |
                                QDir::Hidden | QDir::System);
    for (const QFileInfo &e : entries) {
      if (!copyTree(e.absoluteFilePath(), dst + QLatin1Char('/') + e.fileName(),
                    copied, cb, cancelled, err))
        return false;
    }
    return true;
  }
  return copyFile(src, dst, copied, cb, cancelled, err);
}

// Borrado recursivo, cancelable. Recursión manual (en vez de
// QDir::removeRecursively) para poder comprobar `cancelled` entre entradas.
// Un symlink a carpeta se borra como enlace (QFile::remove), no se entra.
bool removeTree(const QString &path, const std::atomic<bool> &cancelled,
                QString &err) {
  if (cancelled.load()) {
    err = QStringLiteral("cancelled");
    return false;
  }
  QFileInfo fi(path);
  if (fi.isDir() && !fi.isSymLink()) {
    const QFileInfoList entries =
        QDir(path).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot |
                                 QDir::Hidden | QDir::System);
    for (const QFileInfo &e : entries) {
      if (!removeTree(e.absoluteFilePath(), cancelled, err))
        return false;
    }
    if (!QDir().rmdir(path)) {
      err = QStringLiteral("cannot remove %1").arg(path);
      return false;
    }
    return true;
  }
  if (!QFile::remove(path)) {
    err = QStringLiteral("cannot remove %1").arg(path);
    return false;
  }
  return true;
}

// Borrado "a la fuerza" para la limpieza de cancelación: NO comprueba el flag
// de cancelación (que está activo justo cuando lo llamamos) y no reporta
// errores -- es best-effort para quitar una copia parcial. Fase 13.G.
void forceRemove(const QString &path) {
  QFileInfo fi(path);
  if (!fi.exists() && !fi.isSymLink())
    return;
  if (fi.isDir() && !fi.isSymLink())
    QDir(path).removeRecursively();
  else
    QFile::remove(path);
}

// Raíces de papelera XDG activas: la de casa ($XDG_DATA_HOME/Trash o
// ~/.local/share/Trash) primero, más la .Trash-$uid de cada punto de montaje
// que no sea el de $HOME (spec XDG Trash: borrar desde otro disco va a la
// papelera de ESE disco). Réplica de trash-roots.sh sin shell.
QStringList discoverTrashRoots() {
  QStringList roots;
  const QString home = QDir::homePath();
  const QString dataHome =
      qEnvironmentVariable("XDG_DATA_HOME", home + QStringLiteral("/.local/share"));
  const QString homeTrash = dataHome + QStringLiteral("/Trash");
  if (QFileInfo(homeTrash).isDir())
    roots << homeTrash;

  const QString uid = QString::number(::getuid());
  for (const QStorageInfo &v : QStorageInfo::mountedVolumes()) {
    const QString mp = v.rootPath();
    if (mp.isEmpty() || mp == QLatin1String("/"))
      continue;
    if (home.startsWith(mp)) // mismo disco que casa, ya cubierto arriba
      continue;
    const QString cand = mp + QStringLiteral("/.Trash-") + uid;
    if (QFileInfo(cand).isDir())
      roots << cand;
  }
  return roots;
}

// Parsea un fichero .trashinfo: rellena name/origPath/epoch. `root` es la
// raíz física de la papelera (para resolver Path= relativo en papeleras de
// disco). Mismo decode que restoreByOrigPath (percent-decoding correcto).
// Devuelve false si el fichero no tiene Path= (corrupto/incompleto).
bool parseTrashInfo(const QFileInfo &infoFile, const QString &root,
                    QString &name, QString &origPath, qint64 &epoch) {
  QFile f(infoFile.absoluteFilePath());
  if (!f.open(QIODevice::ReadOnly))
    return false;
  QString enc, dateStr;
  while (!f.atEnd()) {
    const QByteArray line = f.readLine();
    if (line.startsWith("Path="))
      enc = QString::fromUtf8(line.mid(5)).trimmed();
    else if (line.startsWith("DeletionDate="))
      dateStr = QString::fromUtf8(line.mid(13)).trimmed();
  }
  f.close();
  if (enc.isEmpty())
    return false;

  QString decoded = QUrl::fromPercentEncoding(enc.toUtf8());
  if (!decoded.startsWith(QLatin1Char('/')))
    decoded = QFileInfo(root).absolutePath() + QLatin1Char('/') + decoded;

  // name = stem del .trashinfo (mismo que el fichero en files/).
  name = infoFile.fileName();
  name.chop(QStringLiteral(".trashinfo").size());
  origPath = decoded;
  const QDateTime dt = QDateTime::fromString(dateStr, Qt::ISODate);
  epoch = dt.isValid() ? dt.toSecsSinceEpoch() : 0;
  return true;
}

} // namespace

FileOperations::FileOperations(QObject *parent) : QObject(parent) {}

FileOperations::~FileOperations() {
  // Marca el objeto como muerto bajo el lock: un worker que aún no haya
  // entregado verá alive=false y no tocará este objeto ya destruido.
  std::lock_guard<std::mutex> lk(m_life->mtx);
  m_life->alive = false;
}

void FileOperations::emitProgress(const QString &op, const QString &path,
                                  qint64 done, qint64 total) {
  // Llamado desde el worker: entrega segura solo si el singleton sigue vivo.
  auto life = m_life;
  std::lock_guard<std::mutex> lk(life->mtx);
  if (!life->alive)
    return;
  QMetaObject::invokeMethod(
      this,
      [this, op, path, done, total]() { emit progress(op, path, done, total); },
      Qt::QueuedConnection);
}

void FileOperations::run(const QString &op, const QString &path,
                         std::function<Result()> job) {
  auto life = m_life; // copia del control block, sobrevive al singleton
  QThreadPool::globalInstance()->start(QRunnable::create(
      [this, life, op, path, job = std::move(job)]() {
        Result r = job();
        // Entrega segura: el destructor toma este mismo lock, así que o
        // vemos alive=false (y no tocamos el objeto muerto) o lo tenemos
        // cogido y el destructor espera a que soltemos.
        std::lock_guard<std::mutex> lk(life->mtx);
        if (!life->alive)
          return;
        QMetaObject::invokeMethod(
            this,
            [this, op, path, r]() {
              if (r.ok)
                emit finished(op, path);
              else
                emit error(op, path, r.message);
            },
            Qt::QueuedConnection);
      }));
}

void FileOperations::copy(const QString &source, const QString &destination,
                          bool overwrite) {
  m_cancelled.store(false);
  run(QStringLiteral("copy"), source,
      [this, source, destination, overwrite]() -> Result {
        if (!QFileInfo::exists(source))
          return {false, QStringLiteral("source does not exist")};
        if (entryExists(destination)) {
          if (!overwrite)
            return {false, QStringLiteral("destination already exists")};
          // Semántica de "overwrite": reemplazo total (borra el destino y
          // copia encima), coherente con lo que promete el diálogo de
          // conflicto. Antes lo hacía `cp -f`.
          QString rmErr;
          if (!removeTree(destination, m_cancelled, rmErr))
            return {false, rmErr};
        }
        const qint64 realTotal = treeSize(source);
        const qint64 pctTotal = qMax<qint64>(1, realTotal);
        qint64 copied = 0;
        double lastPct = -1;
        const auto cb = [&](qint64 done) {
          const double pct = qMin(100.0, done * 100.0 / pctTotal);
          if (pct - lastPct >= 1.0) { // no inundar de senales (~cada 1%)
            lastPct = pct;
            emitProgress(QStringLiteral("copy"), source, done, realTotal);
          }
        };
        QString err;
        if (!copyTree(source, destination, copied, cb, m_cancelled, err)) {
          if (err == QLatin1String("cancelled"))
            forceRemove(destination); // limpia la copia parcial (13.G)
          return {false, err};
        }
        emitProgress(QStringLiteral("copy"), source, realTotal, realTotal);
        return {true, QString()};
      });
}

void FileOperations::cancel() { m_cancelled.store(true); }

QStringList FileOperations::existingPaths(const QStringList &paths) const {
  QStringList out;
  for (const QString &p : paths) {
    // Criterio lstat compartido con copy()/move(): un symlink cuenta como
    // conflicto tenga o no destino válido (ver entryExists / BUG-01).
    if (entryExists(p))
      out << p;
  }
  return out;
}

qint64 FileOperations::totalSize(const QStringList &paths) const {
  qint64 total = 0;
  for (const QString &p : paths)
    total += treeSize(p);
  return total;
}

void FileOperations::move(const QString &source, const QString &destination,
                          bool overwrite) {
  m_cancelled.store(false);
  run(QStringLiteral("move"), source,
      [this, source, destination, overwrite]() -> Result {
    if (!QFileInfo::exists(source))
      return {false, QStringLiteral("source does not exist")};
    if (entryExists(destination)) {
      if (!overwrite)
        return {false, QStringLiteral("destination already exists")};
      // "overwrite" (= mv -f): borra el destino y sigue. Así el rename
      // atómico de abajo no falla por ENOTEMPTY (carpeta) ni deja mezcla.
      QString rmErr;
      if (!removeTree(destination, m_cancelled, rmErr))
        return {false, rmErr};
    }
    // Intento atomico (mismo sistema de ficheros): un solo rename(2), vale
    // tanto para ficheros como para carpetas.
    if (::rename(QFile::encodeName(source).constData(),
                 QFile::encodeName(destination).constData()) == 0)
      return {true, QString()};
    if (errno != EXDEV)
      return {false, QString::fromLocal8Bit(strerror(errno))};
    // Cruza de disco: copiar + borrar el origen, con progreso.
    const qint64 realTotal = treeSize(source);
    const qint64 pctTotal = qMax<qint64>(1, realTotal);
    qint64 copied = 0;
    double lastPct = -1;
    const auto cb = [&](qint64 done) {
      const double pct = qMin(100.0, done * 100.0 / pctTotal);
      if (pct - lastPct >= 1.0) {
        lastPct = pct;
        emitProgress(QStringLiteral("move"), source, done, realTotal);
      }
    };
    QString err;
    if (!copyTree(source, destination, copied, cb, m_cancelled, err)) {
      // Cancelado a mitad del copiado cross-fs: limpia la copia parcial del
      // destino. El origen queda intacto (removeTree solo corre tras copiar).
      if (err == QLatin1String("cancelled"))
        forceRemove(destination);
      return {false, err};
    }
    if (!removeTree(source, m_cancelled, err))
      return {false, err};
    emitProgress(QStringLiteral("move"), source, realTotal, realTotal);
    return {true, QString()};
  });
}

void FileOperations::rename(const QString &path, const QString &newName) {
  const QString dst = QFileInfo(path).absolutePath() + QLatin1Char('/') + newName;
  run(QStringLiteral("rename"), path, [path, dst]() -> Result {
    if (!QFileInfo::exists(path))
      return {false, QStringLiteral("source does not exist")};
    if (QFileInfo::exists(dst))
      return {false, QStringLiteral("destination already exists")};
    if (::rename(QFile::encodeName(path).constData(),
                 QFile::encodeName(dst).constData()) != 0)
      return {false, QString::fromLocal8Bit(strerror(errno))};
    return {true, QString()};
  });
}

void FileOperations::remove(const QString &path, bool ignoreMissing) {
  m_cancelled.store(false);
  run(QStringLiteral("remove"), path, [this, path, ignoreMissing]() -> Result {
    if (!QFileInfo(path).exists() && !QFileInfo(path).isSymLink()) {
      // ignoreMissing (= `rm -f`): que no exista no es error.
      if (ignoreMissing)
        return {true, QString()};
      return {false, QStringLiteral("path does not exist")};
    }
    QString err;
    if (!removeTree(path, m_cancelled, err))
      return {false, err};
    return {true, QString()};
  });
}

void FileOperations::mkdir(const QString &path) {
  run(QStringLiteral("mkdir"), path, [path]() -> Result {
    if (!QDir().mkpath(path))
      return {false, QStringLiteral("cannot create %1").arg(path)};
    return {true, QString()};
  });
}

void FileOperations::trash(const QString &path) {
  run(QStringLiteral("trash"), path, [path]() -> Result {
    if (!QFileInfo(path).exists() && !QFileInfo(path).isSymLink())
      return {false, QStringLiteral("path does not exist")};
    QString trashPath;
    if (!QFile::moveToTrash(path, &trashPath))
      return {false, QStringLiteral("could not move to trash")};
    return {true, QString()};
  });
}

void FileOperations::restore(const QString &path) {
  run(QStringLiteral("restore"), path, [path]() -> Result {
    const QFileInfo fi(path);
    const QString name = fi.fileName();
    const QString filesDir = fi.absolutePath();       // <raiz>/files
    const QString root = QFileInfo(filesDir).absolutePath(); // <raiz>
    const QString infoPath =
        root + QStringLiteral("/info/") + name + QStringLiteral(".trashinfo");

    QFile info(infoPath);
    if (!info.open(QIODevice::ReadOnly))
      return {false, QStringLiteral("no .trashinfo for %1").arg(name)};
    QString encoded;
    while (!info.atEnd()) {
      const QByteArray line = info.readLine();
      if (line.startsWith("Path=")) {
        encoded = QString::fromUtf8(line.mid(5)).trimmed();
        break;
      }
    }
    info.close();
    if (encoded.isEmpty())
      return {false, QStringLiteral("no Path= in .trashinfo")};

    QString orig = QUrl::fromPercentEncoding(encoded.toUtf8());
    // En papeleras de disco (.Trash-$uid) Path puede ser relativo al punto
    // de montaje (= el padre de <raiz>); en la de casa es absoluto.
    if (!orig.startsWith(QLatin1Char('/')))
      orig = QFileInfo(root).absolutePath() + QLatin1Char('/') + orig;

    if (QFileInfo::exists(orig))
      return {false, QStringLiteral("target already exists: %1").arg(orig)};
    QDir().mkpath(QFileInfo(orig).absolutePath());
    if (::rename(QFile::encodeName(path).constData(),
                 QFile::encodeName(orig).constData()) != 0)
      return {false, QString::fromLocal8Bit(strerror(errno))};
    QFile::remove(infoPath);
    return {true, QString()};
  });
}

void FileOperations::restoreByOrigPath(const QString &origPath) {
  m_cancelled.store(false);
  run(QStringLiteral("restore"), origPath, [this, origPath]() -> Result {
    // Buscar en TODAS las raíces XDG el .trashinfo cuyo Path= == origPath,
    // quedándose con el más reciente (mismo fichero borrado varias veces).
    QString bestInfo;
    qint64 bestMtime = -1;
    QString bestRoot;
    for (const QString &root : discoverTrashRoots()) {
      QDir infoDir(root + QStringLiteral("/info"));
      if (!infoDir.exists())
        continue;
      const QFileInfoList infos = infoDir.entryInfoList(
          {QStringLiteral("*.trashinfo")}, QDir::Files);
      for (const QFileInfo &fi : infos) {
        QFile f(fi.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly))
          continue;
        QString enc;
        while (!f.atEnd()) {
          const QByteArray line = f.readLine();
          if (line.startsWith("Path=")) {
            enc = QString::fromUtf8(line.mid(5)).trimmed();
            break;
          }
        }
        f.close();
        if (enc.isEmpty())
          continue;
        // Decodificación XDG correcta (percent-decoding; sin el `+`->espacio
        // que hacía el script, que corrompía nombres con `+` literal).
        QString decoded = QUrl::fromPercentEncoding(enc.toUtf8());
        if (!decoded.startsWith(QLatin1Char('/')))
          decoded = QFileInfo(root).absolutePath() + QLatin1Char('/') + decoded;
        if (decoded != origPath)
          continue;
        const qint64 m = fi.lastModified().toSecsSinceEpoch();
        if (m > bestMtime) {
          bestMtime = m;
          bestInfo = fi.absoluteFilePath();
          bestRoot = root;
        }
      }
    }
    if (bestInfo.isEmpty())
      return {false,
              QStringLiteral("no matching trashed item for %1").arg(origPath)};

    // <root>/files/<name> (name = basename del .trashinfo sin la extensión).
    QString name = QFileInfo(bestInfo).fileName();
    name.chop(QStringLiteral(".trashinfo").size());
    const QString src = bestRoot + QStringLiteral("/files/") + name;
    if (!QFileInfo::exists(src) && !QFileInfo(src).isSymLink())
      return {false, QStringLiteral("trash file missing: %1").arg(src)};
    if (QFileInfo::exists(origPath) || QFileInfo(origPath).isSymLink())
      return {false,
              QStringLiteral("destination already exists: %1").arg(origPath)};

    QDir().mkpath(QFileInfo(origPath).absolutePath());
    if (::rename(QFile::encodeName(src).constData(),
                 QFile::encodeName(origPath).constData()) != 0) {
      if (errno != EXDEV)
        return {false, QString::fromLocal8Bit(strerror(errno))};
      // Cruza de disco (raro en XDG: la papelera está en el mismo disco que
      // el original): copiar + borrar, como haría `mv`.
      qint64 copied = 0;
      QString e;
      const auto noop = [](qint64) {};
      if (!copyTree(src, origPath, copied, noop, m_cancelled, e))
        return {false, e};
      if (!removeTree(src, m_cancelled, e))
        return {false, e};
    }
    QFile::remove(bestInfo);
    return {true, QString()};
  });
}

QStringList FileOperations::trashRoots() const { return discoverTrashRoots(); }

QVariantList FileOperations::trashInfo() const {
  QVariantList out;
  for (const QString &root : discoverTrashRoots()) {
    QDir infoDir(root + QStringLiteral("/info"));
    if (!infoDir.exists())
      continue;
    const QFileInfoList infos =
        infoDir.entryInfoList({QStringLiteral("*.trashinfo")}, QDir::Files);
    for (const QFileInfo &fi : infos) {
      QString name, origPath;
      qint64 epoch = 0;
      if (!parseTrashInfo(fi, root, name, origPath, epoch))
        continue;
      QVariantMap e;
      e[QStringLiteral("name")] = name;
      e[QStringLiteral("origPath")] = origPath;
      e[QStringLiteral("epoch")] = epoch;
      e[QStringLiteral("trashRoot")] = root;
      out.append(e);
    }
  }
  return out;
}

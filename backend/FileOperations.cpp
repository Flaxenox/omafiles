#include "FileOperations.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRunnable>
#include <QThreadPool>
#include <QUrl>

#include <cerrno>
#include <cstdio>

namespace {

constexpr qint64 kChunk = 1 << 20; // 1 MiB

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
bool copyFile(const QString &src, const QString &dst, qint64 &copied,
              const std::function<void(qint64)> &cb, QString &err) {
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
              const std::function<void(qint64)> &cb, QString &err) {
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
                    copied, cb, err))
        return false;
    }
    return true;
  }
  return copyFile(src, dst, copied, cb, err);
}

bool removeTree(const QString &path, QString &err) {
  QFileInfo fi(path);
  if (fi.isDir() && !fi.isSymLink()) {
    if (!QDir(path).removeRecursively()) {
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

} // namespace

FileOperations::FileOperations(QObject *parent) : QObject(parent) {}

void FileOperations::emitProgress(const QString &op, const QString &path,
                                  double pct) {
  QMetaObject::invokeMethod(
      this, [this, op, path, pct]() { emit progress(op, path, pct); },
      Qt::QueuedConnection);
}

void FileOperations::run(const QString &op, const QString &path,
                         std::function<Result()> job) {
  QThreadPool::globalInstance()->start(QRunnable::create(
      [this, op, path, job = std::move(job)]() {
        Result r = job();
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

void FileOperations::copy(const QString &source, const QString &destination) {
  run(QStringLiteral("copy"), source, [this, source, destination]() -> Result {
    if (!QFileInfo::exists(source))
      return {false, QStringLiteral("source does not exist")};
    if (QFileInfo::exists(destination))
      return {false, QStringLiteral("destination already exists")};
    const qint64 total = qMax<qint64>(1, treeSize(source));
    qint64 copied = 0;
    double lastPct = -1;
    const auto cb = [&](qint64 done) {
      const double pct = qMin(100.0, done * 100.0 / total);
      if (pct - lastPct >= 1.0) { // no inundar de senales
        lastPct = pct;
        emitProgress(QStringLiteral("copy"), source, pct);
      }
    };
    QString err;
    if (!copyTree(source, destination, copied, cb, err))
      return {false, err};
    emitProgress(QStringLiteral("copy"), source, 100.0);
    return {true, QString()};
  });
}

void FileOperations::move(const QString &source, const QString &destination) {
  run(QStringLiteral("move"), source, [this, source, destination]() -> Result {
    if (!QFileInfo::exists(source))
      return {false, QStringLiteral("source does not exist")};
    if (QFileInfo::exists(destination))
      return {false, QStringLiteral("destination already exists")};
    // Intento atomico (mismo sistema de ficheros): un solo rename(2), vale
    // tanto para ficheros como para carpetas.
    if (::rename(QFile::encodeName(source).constData(),
                 QFile::encodeName(destination).constData()) == 0)
      return {true, QString()};
    if (errno != EXDEV)
      return {false, QString::fromLocal8Bit(strerror(errno))};
    // Cruza de disco: copiar + borrar el origen, con progreso.
    const qint64 total = qMax<qint64>(1, treeSize(source));
    qint64 copied = 0;
    double lastPct = -1;
    const auto cb = [&](qint64 done) {
      const double pct = qMin(100.0, done * 100.0 / total);
      if (pct - lastPct >= 1.0) {
        lastPct = pct;
        emitProgress(QStringLiteral("move"), source, pct);
      }
    };
    QString err;
    if (!copyTree(source, destination, copied, cb, err))
      return {false, err};
    if (!removeTree(source, err))
      return {false, err};
    emitProgress(QStringLiteral("move"), source, 100.0);
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

void FileOperations::remove(const QString &path) {
  run(QStringLiteral("remove"), path, [path]() -> Result {
    if (!QFileInfo(path).exists() && !QFileInfo(path).isSymLink())
      return {false, QStringLiteral("path does not exist")};
    QString err;
    if (!removeTree(path, err))
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

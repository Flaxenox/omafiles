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
#include <sys/stat.h>
#include <unistd.h>

namespace {

constexpr qint64 kChunk = 1 << 20; // 1 MiB

// Does a directory ENTRY exist at `path`? (lstat, not stat.) Unlike
// QFileInfo::exists() -- which follows symlinks and is therefore blind to a
// broken symlink -- this counts as existing anything that occupies the
// name, including a symlink whose target does not exist. It is the SINGLE
// "destination conflict" criterion shared by existingPaths() (the UI
// check) and the no-overwrite guards of copy()/move(): they previously diverged
// from the shell's `test -e` precisely in the broken-symlink case (BUG-01,
// Hardening-1). Same idiom that removeTree/trash/restore already used below.
inline bool entryExists(const QString &path) {
  const QFileInfo fi(path);
  return fi.exists() || fi.isSymLink();
}

// Total size (recursive) of a path, for the progress percentage.
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

// Copies a file in chunks, reporting bytes copied via cb.
// `cancelled` is checked between chunks: if it is set, it aborts with err.
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
  out.setPermissions(in.permissions()); // preserve mode
  return true;
}

// Recursive copy (files, folders and symlinks as symlinks).
bool copyTree(const QString &src, const QString &dst, qint64 &copied,
              const std::function<void(qint64)> &cb,
              const std::atomic<bool> &cancelled, QString &err) {
  if (cancelled.load()) {
    err = QStringLiteral("cancelled");
    return false;
  }
  QFileInfo si(src);
  if (si.isSymLink()) {
    // Recreate the link, do not follow it.
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

// Recursive delete, cancelable. Manual recursion (instead of
// QDir::removeRecursively) to be able to check `cancelled` between entries.
// A symlink to a folder is deleted as a link (QFile::remove), it is not entered.
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

// "Forced" delete for the cancellation cleanup: it does NOT check the
// cancellation flag (which is set precisely when we call it) and does not report
// errors -- it is best-effort to remove a partial copy. Phase 13.G.
void forceRemove(const QString &path) {
  QFileInfo fi(path);
  if (!fi.exists() && !fi.isSymLink())
    return;
  if (fi.isDir() && !fi.isSymLink())
    QDir(path).removeRecursively();
  else
    QFile::remove(path);
}

// Active XDG trash roots: the home one ($XDG_DATA_HOME/Trash or
// ~/.local/share/Trash) first, plus the .Trash-$uid of each mount point
// that is not $HOME's (XDG Trash spec: deleting from another disk goes to
// THAT disk's trash). Replica of trash-roots.sh without shell.
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
    if (home.startsWith(mp)) // same disk as home, already covered above
      continue;
    const QString cand = mp + QStringLiteral("/.Trash-") + uid;
    if (QFileInfo(cand).isDir())
      roots << cand;
  }
  return roots;
}

// Parses a .trashinfo file: fills name/origPath/epoch. `root` is the
// physical root of the trash (to resolve a relative Path= in disk
// trashes). Same decode as restoreByOrigPath (correct percent-decoding).
// Returns false if the file has no Path= (corrupt/incomplete).
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

  // name = stem of the .trashinfo (same as the file in files/).
  name = infoFile.fileName();
  name.chop(QStringLiteral(".trashinfo").size());
  origPath = decoded;
  const QDateTime dt = QDateTime::fromString(dateStr, Qt::ISODate);
  epoch = dt.isValid() ? dt.toSecsSinceEpoch() : 0;
  return true;
}

// Resolves a path to its canonical form, handling non-existent target files by
// resolving their existing parent directory symlinks (e.g. ~/Descargas -> /mnt/Almacen/Descargas).
QString canonicalPathForFile(const QString &path) {
  const QFileInfo fi(path);
  const QString canonical = fi.canonicalFilePath();
  if (!canonical.isEmpty())
    return canonical;
  const QDir parentDir(fi.absolutePath());
  const QString parentCanonical = parentDir.canonicalPath();
  if (!parentCanonical.isEmpty())
    return parentCanonical + QLatin1Char('/') + fi.fileName();
  return QDir::cleanPath(path);
}

} // namespace

FileOperations::FileOperations(QObject *parent) : QObject(parent) {}

FileOperations::~FileOperations() {
  // Marks the object as dead under the lock: a worker that has not yet
  // delivered will see alive=false and will not touch this already-destroyed object.
  std::lock_guard<std::mutex> lk(m_life->mtx);
  m_life->alive = false;
}

void FileOperations::emitProgress(const QString &op, const QString &path,
                                  qint64 done, qint64 total) {
  // Called from the worker: safe delivery only if the singleton is still alive.
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
  auto life = m_life; // copy of the control block, outlives the singleton
  QThreadPool::globalInstance()->start(QRunnable::create(
      [this, life, op, path, job = std::move(job)]() {
        Result r = job();
        // Safe delivery: the destructor takes this same lock, so either we
        // see alive=false (and do not touch the dead object) or we hold
        // it and the destructor waits for us to release.
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
          // "overwrite" semantics: total replacement (deletes the destination and
          // copies over), consistent with what the conflict dialog
          // promises. It used to be done by `cp -f`.
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
          if (pct - lastPct >= 1.0) { // do not flood with signals (~every 1%)
            lastPct = pct;
            emitProgress(QStringLiteral("copy"), source, done, realTotal);
          }
        };
        QString err;
        if (!copyTree(source, destination, copied, cb, m_cancelled, err)) {
          if (err == QLatin1String("cancelled"))
            forceRemove(destination); // clean up the partial copy (13.G)
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
    // lstat criterion shared with copy()/move(): a symlink counts as a
    // conflict whether or not it has a valid target (see entryExists / BUG-01).
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

QStringList FileOperations::octalModes(const QStringList &paths) const {
  QStringList out;
  out.reserve(paths.size());
  for (const QString &p : paths) {
    struct stat st;
    // stat() (follows symlinks), like `stat -c%a` -- %a is mode & 07777 in
    // octal without a leading zero (e.g. "755", "4755"). "" if it could not.
    if (::stat(QFile::encodeName(p).constData(), &st) == 0)
      out << QString::number(st.st_mode & 07777, 8);
    else
      out << QString();
  }
  return out;
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
      // "overwrite" (= mv -f): deletes the destination and continues. This way the
      // atomic rename below does not fail with ENOTEMPTY (folder) nor leave a mix.
      QString rmErr;
      if (!removeTree(destination, m_cancelled, rmErr))
        return {false, rmErr};
    }
    // Atomic attempt (same filesystem): a single rename(2), works
    // for both files and folders.
    if (::rename(QFile::encodeName(source).constData(),
                 QFile::encodeName(destination).constData()) == 0)
      return {true, QString()};
    if (errno != EXDEV)
      return {false, QString::fromLocal8Bit(strerror(errno))};
    // Crosses disks: copy + delete the source, with progress.
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
      // Cancelled mid cross-fs copy: clean up the partial copy at the
      // destination. The source stays intact (removeTree only runs after copying).
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
      // ignoreMissing (= `rm -f`): it not existing is not an error.
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

void FileOperations::emptyTrash() {
  m_cancelled.store(false);
  run(QStringLiteral("emptyTrash"), QString(), [this]() -> Result {
    QString err;
    const QStringList roots = discoverTrashRoots();
    for (const QString &root : roots) {
      if (m_cancelled.load())
        return {false, QStringLiteral("cancelled")};

      const QString filesDir = root + QStringLiteral("/files");
      const QString infoDir = root + QStringLiteral("/info");

      if (QFileInfo(filesDir).isDir()) {
        const QFileInfoList files = QDir(filesDir).entryInfoList(
            QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden |
            QDir::System);
        for (const QFileInfo &fi : files) {
          if (m_cancelled.load())
            return {false, QStringLiteral("cancelled")};
          removeTree(fi.absoluteFilePath(), m_cancelled, err);
        }
      }

      if (QFileInfo(infoDir).isDir()) {
        const QFileInfoList infos = QDir(infoDir).entryInfoList(
            {QStringLiteral("*.trashinfo")}, QDir::Files | QDir::Hidden);
        for (const QFileInfo &fi : infos) {
          if (m_cancelled.load())
            return {false, QStringLiteral("cancelled")};
          QFile::remove(fi.absoluteFilePath());
        }
      }
    }
    return {true, QString()};
  });
}

void FileOperations::restore(const QString &path) {
  run(QStringLiteral("restore"), path, [path]() -> Result {
    const QFileInfo fi(path);
    const QString name = fi.fileName();
    const QString filesDir = fi.absolutePath();       // <root>/files
    const QString root = QFileInfo(filesDir).absolutePath(); // <root>
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
    // In disk trashes (.Trash-$uid) Path may be relative to the mount
    // point (= the parent of <root>); in the home one it is absolute.
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
    // Search in ALL the XDG roots for the .trashinfo whose Path= matches origPath,
    // matching exact, canonical (symlink-resolved), or clean paths,
    // and keeping the most recent one (same file deleted several times).
    QString bestInfo;
    qint64 bestMtime = -1;
    QString bestRoot;
    const QString origCanonical = canonicalPathForFile(origPath);
    const QString origClean = QDir::cleanPath(origPath);

    for (const QString &root : discoverTrashRoots()) {
      QDir infoDir(root + QStringLiteral("/info"));
      if (!infoDir.exists())
        continue;
      const QFileInfoList infos = infoDir.entryInfoList(
          {QStringLiteral("*.trashinfo")}, QDir::Files);
      for (const QFileInfo &fi : infos) {
        QString name, decoded;
        qint64 epoch = 0;
        if (!parseTrashInfo(fi, root, name, decoded, epoch))
          continue;

        const bool matches = (decoded == origPath) ||
                             (QDir::cleanPath(decoded) == origClean) ||
                             (canonicalPathForFile(decoded) == origCanonical);
        if (!matches)
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

    // <root>/files/<name> (name = basename of the .trashinfo without the extension).
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
      // Crosses disks (rare in XDG: the trash is on the same disk as
      // the original): copy + delete, as `mv` would.
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

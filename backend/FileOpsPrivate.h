#pragma once
#include "FileOperations.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRunnable>
#include <QStorageInfo>
#include <QThread>
#include <QThreadPool>
#include <QUrl>
#include <QVariantMap>

#include <cerrno>
#include <cstdio>
#include <sys/stat.h>
#include <unistd.h>

namespace FileOpsPrivate {

inline constexpr qint64 kChunk = 1 << 20; // 1 MiB

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
inline qint64 treeSize(const QString &path) {
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
inline bool copyFile(const QString &src, const QString &dst, qint64 &copied,
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
  // QFile::read() returns 0 on clean EOF and -1 on a real I/O error -- the
  // loop condition `> 0` exits identically for both, so without this check a
  // mid-copy read failure (dropped network share, failing disk sector) was
  // reported as a successful copy with a silently truncated destination
  // (P0-2, forensic audit 2026-08-16).
  if (n < 0) {
    err = QStringLiteral("read failed on %1: %2").arg(src, in.errorString());
    return false;
  }
  out.close();
  in.close();
  out.setPermissions(in.permissions()); // preserve mode
  return true;
}

// Recursive copy (files, folders and symlinks as symlinks).
inline bool copyTree(const QString &src, const QString &dst, qint64 &copied,
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
inline bool removeTree(const QString &path, const std::atomic<bool> &cancelled,
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
inline void forceRemove(const QString &path) {
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
inline QStringList discoverTrashRoots() {
  // Selfcheck-only hook (V1_1_P0_TRASH_FREEZE regression test): simulates a
  // slow/stalled mount stat() -- e.g. a spun-down mechanical disk or a
  // stalled network/FUSE mount (sshfs/NFS/rclone/gvfs) -- which is what
  // actually froze the UI before this function's callers were made async
  // (see FileOperations::requestTrashRoots()/requestTrashInfo()). A real
  // slow mount isn't available in CI/dev environments, so the regression
  // test opts into this instead, the same env-var-gated pattern as
  // OMAFILES_SELFCHECK elsewhere in this codebase. Always off in production
  // (the var is never set outside the selfcheck harness).
  bool msOk = false;
  const int slowMs = qEnvironmentVariableIntValue(
      "OMAFILES_SELFCHECK_SLOW_TRASH_MOUNT_MS", &msOk);
  if (msOk && slowMs > 0)
    QThread::msleep(static_cast<unsigned long>(slowMs));

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
inline bool parseTrashInfo(const QFileInfo &infoFile, const QString &root,
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
inline QString canonicalPathForFile(const QString &path) {
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

} // namespace FileOpsPrivate

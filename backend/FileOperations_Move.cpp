#include "FileOperations.h"
#include "FileOpsPrivate.h"
#include <QThreadPool>
#include <QRunnable>
using namespace FileOpsPrivate;
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


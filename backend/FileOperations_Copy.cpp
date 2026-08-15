#include "FileOperations.h"
#include "FileOpsPrivate.h"
#include <QThreadPool>
#include <QRunnable>
using namespace FileOpsPrivate;
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


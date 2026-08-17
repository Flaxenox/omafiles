#include "FileOperations.h"
#include "FileOpsPrivate.h"
#include <QThreadPool>
#include <QRunnable>
using namespace FileOpsPrivate;
void FileOperations::copy(const QString &source, const QString &destination,
                          bool overwrite) {
  // `cancelled` is a fresh, operation-local shared_ptr copy captured by
  // value below, not `this` and not shared with any other operation -- see
  // beginCancelToken()'s doc comment in FileOperations.h (P1-4) and the
  // ProgressFn comment on run() (P0) for why both matter.
  auto cancelled = beginCancelToken();
  run(QStringLiteral("copy"), source,
      [source, destination, overwrite, cancelled](const auto &progressFn) -> Result {
        if (!QFileInfo::exists(source))
          return {false, QStringLiteral("source does not exist")};
        if (entryExists(destination)) {
          if (!overwrite)
            return {false, QStringLiteral("destination already exists")};
          // "overwrite" semantics: total replacement (deletes the destination and
          // copies over), consistent with what the conflict dialog
          // promises. It used to be done by `cp -f`.
          QString rmErr;
          if (!removeTree(destination, *cancelled, rmErr))
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
            progressFn(done, realTotal);
          }
        };
        QString err;
        if (!copyTree(source, destination, copied, cb, *cancelled, err)) {
          // Clean up the partial copy on ANY failure (P0-2, forensic audit
          // 2026-08-16), not just cancellation -- a disk-full/permission/
          // read error mid-tree must not leave a truncated destination that
          // looks like a real file.
          forceRemove(destination);
          return {false, err};
        }
        progressFn(realTotal, realTotal);
        return {true, QString()};
      });
}


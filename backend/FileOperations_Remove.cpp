#include "FileOperations.h"
#include "FileOpsPrivate.h"
#include <QThreadPool>
#include <QRunnable>
using namespace FileOpsPrivate;
void FileOperations::remove(const QString &path, bool ignoreMissing) {
  auto cancelled = beginCancelToken(); // fresh, operation-local token (P1-4); job lambda is `this`-free (P0)
  run(QStringLiteral("remove"), path, [path, ignoreMissing, cancelled](const auto &) -> Result {
    if (!QFileInfo(path).exists() && !QFileInfo(path).isSymLink()) {
      // ignoreMissing (= `rm -f`): it not existing is not an error.
      if (ignoreMissing)
        return {true, QString()};
      return {false, QStringLiteral("path does not exist")};
    }
    QString err;
    if (!removeTree(path, *cancelled, err))
      return {false, err};
    return {true, QString()};
  });
}


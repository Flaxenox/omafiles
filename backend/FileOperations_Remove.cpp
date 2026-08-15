#include "FileOperations.h"
#include "FileOpsPrivate.h"
#include <QThreadPool>
#include <QRunnable>
using namespace FileOpsPrivate;
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


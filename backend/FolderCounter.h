#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// Counts the direct entries of a folder for the file list subtitle
// ("42 items", Phase 23, josema). It does NOT touch DirectoryModel (which lists
// the CURRENT folder): it counts the content of the visible SUBfolders, on
// demand (one per folder-row) and ASYNCHRONOUSLY (QThreadPool) so as not to
// block the UI even on huge folders (node_modules). QDirIterator walks the
// directory without a stat per entry. The result arrives via the counted(path,
// n) signal; the cache (with invalidation) is handled by state/FolderCountState
// in QML. QML singleton, no dependency on Quickshell.
class FolderCounter : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit FolderCounter(QObject *parent = nullptr);

  // Launches the async count of `path`. includeHidden mirrors
  // NavState.showHidden so the number matches what would be seen inside. Emits
  // counted(path,n) on completion (n = -1 if it cannot be opened: permissions,
  // does not exist, is not a dir).
  Q_INVOKABLE void request(const QString &path, bool includeHidden);

signals:
  void counted(const QString &path, int n);
};

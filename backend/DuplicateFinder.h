#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <atomic>
#include <memory>
#include <mutex>
#include <qqmlregistration.h>

// Native recursive duplicate-file finder. Walks `root`, groups files by
// exact size, then by content hash (two-stage: a cheap 64KB "quick hash"
// prune before a full-file hash on survivors) -- standard fdupes-style
// pruning so large trees stay fast. Symlinks are not followed (no false
// "duplicate" against their own target) and zero-byte files are excluded
// (not a useful dedup signal). Async (QThreadPool) and cancelable via the
// same generation-counter pattern as SearchWorker.h (the closest
// structural match already in this codebase: a long-running recursive
// tree walk that must stop cleanly mid-flight, checked on every iterated
// entry -- see that file's header comment for the full rationale).
//
// Instantiable (QML_ELEMENT, like SearchWorker/ProcessRunner): owned by
// exactly one caller (logic/ActionEngine.qml), not a shared singleton.
// No dependency on Quickshell.
class DuplicateFinder : public QObject {
  Q_OBJECT
  QML_ELEMENT

public:
  explicit DuplicateFinder(QObject *parent = nullptr);
  ~DuplicateFinder() override;

  // Launches a recursive duplicate scan under `root`.
  Q_INVOKABLE void scan(const QString &root, bool includeHidden);

  // Cancels the scan in progress (invalidates its generation): no
  // further progress/finished signal is emitted. Idempotent.
  Q_INVOKABLE void cancel();

signals:
  // Periodic progress while walking the tree (throttled, ~150ms) --
  // v1 simplification: no progress is reported during the hashing pass
  // that follows the walk (usually the smaller share of total time,
  // since most size-groups are singletons and get skipped immediately).
  void progress(int filesScanned);
  // Final result: each group is {size: qint64, paths: QStringList},
  // only groups with 2+ confirmed byte-identical files.
  void finished(const QVariantList &groups);

private:
  // Heap-allocated and shared (not a plain member) -- same reasoning as
  // SearchWorker.h's m_gen: the worker lambda captures its own shared_ptr
  // copy and checks it without ever needing `this`, so cancellation stays
  // correct even if this object is destroyed mid-scan.
  std::shared_ptr<std::atomic<quint64>> m_gen =
      std::make_shared<std::atomic<quint64>>(0);

  // Life guard against the dangling `this` on delivery (same pattern as
  // SearchWorker/ThumbnailProvider/FileOperations).
  struct Life {
    std::mutex mtx;
    bool alive = true;
  };
  std::shared_ptr<Life> m_life = std::make_shared<Life>();
};

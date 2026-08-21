#include "DuplicateFinder.h"

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QRunnable>
#include <QThreadPool>
#include <QVariantMap>

#include <algorithm>

namespace {

constexpr qint64 kQuickHashBytes = 64 * 1024;

// Sha256 of the first `maxBytes` of `path` (or the whole file if
// maxBytes < 0). "" on any I/O failure -- callers skip files that hash
// empty rather than treating them as a false match.
QString hashFile(const QString &path, qint64 maxBytes) {
  QFile f(path);
  if (!f.open(QIODevice::ReadOnly))
    return QString();
  QCryptographicHash h(QCryptographicHash::Sha256);
  if (maxBytes < 0) {
    if (!h.addData(&f))
      return QString();
  } else {
    h.addData(f.read(maxBytes));
  }
  return QString::fromLatin1(h.result().toHex());
}

} // namespace

DuplicateFinder::DuplicateFinder(QObject *parent) : QObject(parent) {}

DuplicateFinder::~DuplicateFinder() {
  std::lock_guard<std::mutex> lk(m_life->mtx);
  m_life->alive = false;
}

void DuplicateFinder::cancel() { m_gen->fetch_add(1); }

void DuplicateFinder::scan(const QString &root, bool includeHidden) {
  const quint64 gen = m_gen->fetch_add(1) + 1;
  if (root.isEmpty())
    return;

  auto life = m_life;
  auto genPtr = m_gen;
  const QString rootPath = root;

  QThreadPool::globalInstance()->start(QRunnable::create([this, life, genPtr,
                                                           gen, rootPath,
                                                           includeHidden]() {
    auto cancelled = [&]() { return genPtr->load() != gen; };

    // Pass 1: walk the tree, group survivors by exact size. Skip
    // symlinks (no follow, no false "duplicate" against their own
    // target) and zero-byte files (excluded -- not a useful signal).
    QDir::Filters filters = QDir::Files | QDir::NoDotAndDotDot;
    if (includeHidden)
      filters |= QDir::Hidden;

    QHash<qint64, QStringList> bySize;
    int scanned = 0;
    QElapsedTimer progressTimer;
    progressTimer.start();

    QDirIterator it(rootPath, filters, QDirIterator::Subdirectories);
    while (it.hasNext()) {
      if (cancelled())
        return;
      it.next();
      const QFileInfo fi = it.fileInfo();
      if (fi.isSymLink() || fi.size() == 0)
        continue;
      bySize[fi.size()].append(fi.absoluteFilePath());
      ++scanned;
      if (progressTimer.elapsed() >= 150) {
        progressTimer.restart();
        std::lock_guard<std::mutex> lk(life->mtx);
        if (!life->alive || cancelled())
          return;
        const int n = scanned;
        QMetaObject::invokeMethod(
            this, [this, n]() { emit progress(n); }, Qt::QueuedConnection);
      }
    }

    // Pass 2+3: for each size-group with >=2 files, a cheap 64KB
    // "quick hash" prunes non-matches before a full-file hash confirms
    // the survivors -- standard fdupes-style two-stage pruning so large
    // trees stay fast (most groups never reach the expensive full hash).
    QVariantList resultGroups;
    for (auto sizeIt = bySize.constBegin(); sizeIt != bySize.constEnd();
         ++sizeIt) {
      if (cancelled())
        return;
      const QStringList &candidates = sizeIt.value();
      if (candidates.size() < 2)
        continue;

      QHash<QString, QStringList> byQuickHash;
      for (const QString &path : candidates) {
        if (cancelled())
          return;
        const QString qh = hashFile(path, kQuickHashBytes);
        if (!qh.isEmpty())
          byQuickHash[qh].append(path);
      }

      for (auto qhIt = byQuickHash.constBegin(); qhIt != byQuickHash.constEnd();
           ++qhIt) {
        if (cancelled())
          return;
        const QStringList &survivors = qhIt.value();
        if (survivors.size() < 2)
          continue;

        QHash<QString, QStringList> byFullHash;
        for (const QString &path : survivors) {
          if (cancelled())
            return;
          const QString fh = hashFile(path, -1);
          if (!fh.isEmpty())
            byFullHash[fh].append(path);
        }

        for (auto fhIt = byFullHash.constBegin(); fhIt != byFullHash.constEnd();
             ++fhIt) {
          if (fhIt.value().size() < 2)
            continue;
          // Oldest first -- so "keep the first, trash the rest" (the
          // dialog's one-click convenience) means "keep the oldest copy",
          // not an arbitrary hash-iteration order.
          QStringList paths = fhIt.value();
          std::sort(paths.begin(), paths.end(),
                    [](const QString &a, const QString &b) {
                      return QFileInfo(a).lastModified() <
                             QFileInfo(b).lastModified();
                    });
          QVariantMap group;
          group[QStringLiteral("size")] = sizeIt.key();
          group[QStringLiteral("paths")] = paths;
          resultGroups.append(group);
        }
      }
    }

    // Safe delivery -- same pattern as SearchWorker::search().
    std::lock_guard<std::mutex> lk(life->mtx);
    if (!life->alive)
      return;
    if (cancelled())
      return;
    QMetaObject::invokeMethod(
        this, [this, resultGroups]() { emit finished(resultGroups); },
        Qt::QueuedConnection);
  }));
}

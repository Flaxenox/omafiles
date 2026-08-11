#include "SearchWorker.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QRunnable>
#include <QThreadPool>
#include <QVariantMap>

SearchWorker::SearchWorker(QObject *parent) : QObject(parent) {}

SearchWorker::~SearchWorker() {
  std::lock_guard<std::mutex> lk(m_life->mtx);
  m_life->alive = false;
}

void SearchWorker::cancel() { m_gen.fetch_add(1); }

void SearchWorker::search(const QString &root, const QString &query,
                          bool showHidden) {
  // Invalidates any previous search and opens this one's generation.
  const quint64 gen = m_gen.fetch_add(1) + 1;
  if (query.isEmpty())
    return;

  auto life = m_life;
  const QString rootPath = root;
  // Phase 27 (PERF_AUDIT_RC1): the query is NOT lowercased to then do
  // fileName().toLower().contains(q) -> that allocated a new QString
  // per scanned file (100k allocations on a large tree). It is
  // compared with Qt::CaseInsensitive, which does the case-folding without
  // materializing the lowercased name.
  const QString q = query;

  QThreadPool::globalInstance()->start(QRunnable::create([this, life, gen,
                                                          rootPath, q,
                                                          showHidden]() {
    // Without QDir::Hidden in the filter, QDirIterator does NOT emit hidden
    // entries NOR recurse into hidden folders -- equivalent to the
    // `-not -path './.*' -not -path '*/.*'` of the script.
    QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
    if (showHidden)
      filters |= QDir::Hidden;

    const QDir base(rootPath);
    QDirIterator it(rootPath, filters, QDirIterator::Subdirectories);
    QVariantList out;
    while (it.hasNext()) {
      // Cancelled or superseded by another search -> abort without emitting.
      if (m_gen.load() != gen)
        return;
      it.next();
      const QFileInfo fi = it.fileInfo();
      if (!fi.fileName().contains(q, Qt::CaseInsensitive))
        continue;
      const bool isDir = fi.isDir();
      QVariantMap e;
      e[QStringLiteral("type")] =
          isDir ? QStringLiteral("dir") : QStringLiteral("file");
      // Path relative to root (same "name" that the script produced).
      e[QStringLiteral("name")] =
          base.relativeFilePath(fi.absoluteFilePath());
      e[QStringLiteral("size")] =
          isDir ? qint64(0) : static_cast<qint64>(fi.size());
      e[QStringLiteral("mtime")] =
          static_cast<qint64>(fi.lastModified().toSecsSinceEpoch());
      e[QStringLiteral("link")] = QString();
      out.append(e);
      // Cap of 201: the 201st only serves to know there were more than 200.
      if (out.size() >= 201)
        break;
    }
    const bool truncated = out.size() > 200;
    if (truncated)
      out.erase(out.begin() + 200, out.end());

    QMetaObject::invokeMethod(
        this,
        [this, life, gen, out, truncated]() {
          std::lock_guard<std::mutex> lk(life->mtx);
          if (!life->alive)
            return;
          if (m_gen.load() != gen)
            return; // superseded while delivering
          emit results(out, truncated);
        },
        Qt::QueuedConnection);
  }));
}

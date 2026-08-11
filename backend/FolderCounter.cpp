#include "FolderCounter.h"

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QPointer>
#include <QRunnable>
#include <QThreadPool>

FolderCounter::FolderCounter(QObject *parent) : QObject(parent) {}

void FolderCounter::request(const QString &path, bool includeHidden) {
  QPointer<FolderCounter> self(this);
  const QString p = path;
  QThreadPool::globalInstance()->start(QRunnable::create([self, p, includeHidden]() {
    int n = -1;
    const QFileInfo fi(p);
    if (!p.isEmpty() && fi.isDir()) {
      // AllEntries + NoDotAndDotDot = files + folders + links, without
      // "."/".." -- the same that would be seen on entering. Hidden only if the
      // user shows hidden files, so the number matches.
      QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
      if (includeHidden)
        filters |= QDir::Hidden;
      QDirIterator it(p, filters, QDirIterator::NoIteratorFlags);
      n = 0;
      while (it.hasNext()) {
        it.next();
        ++n;
      }
    }
    // Emit on the object's thread (queued) to touch QML safely.
    if (self)
      QMetaObject::invokeMethod(self, "counted", Qt::QueuedConnection,
                                Q_ARG(QString, p), Q_ARG(int, n));
  }));
}

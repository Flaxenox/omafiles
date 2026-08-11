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
  // Invalida cualquier búsqueda anterior y abre la generación de esta.
  const quint64 gen = m_gen.fetch_add(1) + 1;
  if (query.isEmpty())
    return;

  auto life = m_life;
  const QString rootPath = root;
  // Fase 27 (PERF_AUDIT_RC1): NO se baja la query a minúsculas para luego
  // hacer fileName().toLower().contains(q) -> eso asignaba una QString nueva
  // por cada fichero escaneado (100k asignaciones en un árbol grande). Se
  // compara con Qt::CaseInsensitive, que hace el case-folding sin materializar
  // el nombre en minúsculas.
  const QString q = query;

  QThreadPool::globalInstance()->start(QRunnable::create([this, life, gen,
                                                          rootPath, q,
                                                          showHidden]() {
    // Sin QDir::Hidden en el filtro, QDirIterator NO emite entradas ocultas
    // NI recurre dentro de carpetas ocultas -- equivale a los
    // `-not -path './.*' -not -path '*/.*'` del script.
    QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
    if (showHidden)
      filters |= QDir::Hidden;

    const QDir base(rootPath);
    QDirIterator it(rootPath, filters, QDirIterator::Subdirectories);
    QVariantList out;
    while (it.hasNext()) {
      // Cancelada o superada por otra búsqueda -> abortar sin emitir.
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
      // Ruta relativa a root (mismo "nombre" que producía el script).
      e[QStringLiteral("name")] =
          base.relativeFilePath(fi.absoluteFilePath());
      e[QStringLiteral("size")] =
          isDir ? qint64(0) : static_cast<qint64>(fi.size());
      e[QStringLiteral("mtime")] =
          static_cast<qint64>(fi.lastModified().toSecsSinceEpoch());
      e[QStringLiteral("link")] = QString();
      out.append(e);
      // Tope de 201: el 201 solo sirve para saber que hubo más de 200.
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
            return; // superada mientras se entregaba
          emit results(out, truncated);
        },
        Qt::QueuedConnection);
  }));
}

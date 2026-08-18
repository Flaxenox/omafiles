#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <memory>
#include <mutex>
#include <qqmlregistration.h>

// C++ backend for thumbnails. Generates thumbnails of images
// (PNG/JPEG/WebP/GIF/SVG) and PDF (first page) with QImageReader, caches
// them on disk and serves them by file PATH -- just as the project
// already did with the PDF/video thumbnails (Image { source: <path> }), which
// (which we do not control). See BACKEND_DESIGN.md.
//
// Persistent cache in ~/.cache/omafiles/thumbnails/. The key is a hash
// (SHA-1) of path+max-size+file-size+mtime: if the image
// changes (different mtime/size) the key changes and it regenerates on its
// own (invalidation by path+size+mtime, as the requirement asks).
//
// Asynchronous: request() returns immediately. If the thumbnail is already in
// the cache it returns its path; if not, it returns "" and generates it on a
// thread of the QThreadPool, emitting ready(path, thumbPath) on completion. For
// unsupported types it returns "" and does not generate (the UI keeps its icon
// glyph).
//
// QML singleton (Omafiles.Backend.ThumbnailProvider). No dependency on
// Quickshell: only public Qt.
class ThumbnailProvider : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit ThumbnailProvider(QObject *parent = nullptr);
  ~ThumbnailProvider() override;

  // Path of the thumbnail of `path` (max side `size` px) if it is already in
  // the cache; if not, "" and it generates it async -> ready(path, thumbPath).
  // Returns "" without generating if the type is not supported.
  Q_INVOKABLE QString request(const QString &path, int size = 256);

  // Canonical on-disk cache-key hash (SHA-1 hex of `input`). IT IS THE
  // ONLY cache hash scheme of Omafiles: it is used internally by
  // request() for the image/PDF thumbnails and consumed from QML by the
  // paths that previously used Utils.simpleHash (video thumbnails in
  // logic/VideoThumbnails.qml, extraction cache in logic/ArchiveActions.
  // qml). Deterministic and stable: same `input` -> same file name.
  Q_INVOKABLE QString cacheKey(const QString &input) const;

  // Maintenance prune of the on-disk cache. The ONLY production
  // entry point: it deletes (1) the orphans of the old base36 scheme
  // -without a consumer after B1-, (2) the thumbnails older than the age
  // policy and (3), if the total exceeds the size policy, the oldest ones
  // until it drops below. It fires on its own once when the singleton is built
  // on a thread of the QThreadPool (without blocking startup); skipped under
  // --selfcheck. Safe: it is not recursive and only acts on files with
  // Omafiles' name pattern inside the cache directory.
  Q_INVOKABLE void pruneCache();

  // SYNCHRONOUS prune primitive over `dir` with explicit thresholds; returns
  // the number of deleted files. Used by pruneCache() (with the default
  // policies) and the --selfcheck harness (with test thresholds over a temporary
  // directory, without touching the real cache). Same safety guarantee.
  Q_INVOKABLE int pruneCacheDir(const QString &dir, qint64 maxAgeSecs,
                                qint64 maxBytes) const;

signals:
  void ready(const QString &path, const QString &thumbPath);

private:
  // Implementation of the canonical hash (see cacheKey()). Static so it can
  // be used from the generation worker without touching the object.
  static QString hashKey(const QString &input);
  // Is the extension of a type we know how to thumbnail? (cheap, avoids
  // opening text/binary files). QImageReader does the real check
  // on generating.
  static bool supported(const QString &path);
  // Runs on the worker: generates the thumbnail of `path` to `outPath`. Static
  // (does not touch the object), safe even if the singleton dies during the
  // thread.
  static bool generate(const QString &path, int size, const QString &outPath);

  QString m_cacheDir;
  QSet<QString> m_inflight; // keys being generated right now (dedup)

  // Life guard against the dangling `this` (same pattern as DirectoryModel/
  // FileOperations/SearchWorker). P0 concurrency audit (forensic audit
  // 2026-08-16): request()'s pool worker used to call
  // QMetaObject::invokeMethod(this, ...) completely unguarded -- there was
  // no destructor, no life tracking at all, so closing the app (destroying
  // this QML singleton) while a thumbnail was still being generated was a
  // confirmed use-after-free/segfault (reproduced with AddressSanitizer:
  // Qt's own event delivery crashed trying to dispatch to the freed
  // object). generate() itself stays static/`this`-free, as documented
  // above; only the delivery step needs the guard.
  struct Life {
    std::mutex mtx;
    bool alive = true;
  };
  std::shared_ptr<Life> m_life = std::make_shared<Life>();
};

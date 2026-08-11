#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <qqmlregistration.h>

// C++ backend for previews (Phase 9, josema). Replaces the preview panel's
// shell processes: the text READING (previously `head -c 4000`)
// and the METADATA. The scaled image and the PDF are still provided by
// ThumbnailProvider (Phase 8) at a preview size -- "cache reusing
// ThumbnailProvider when possible", without duplicating render/cache. The
// highlighting (Pygments), the video thumbnail (ffmpegthumbnailer) and the
// audio metadata (ffprobe) stay in shell for now.
//
// No dependency on Quickshell: only public Qt. QML singleton
// (Omafiles.Backend.PreviewProvider).
class PreviewProvider : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit PreviewProvider(QObject *parent = nullptr);

  // File metadata (QFileInfo + QMimeDatabase). Cheap and synchronous:
  // { name, path, size, mtime, mime, permissions ("rwxr-x---"...),
  //   readable, writable, executable }.
  Q_INVOKABLE QVariantMap info(const QString &path);

  // Reads the text of `path` (up to `maxBytes`, 256 KB by default) on a pool
  // thread and delivers it via textReady(). Cancellation by generation: if the
  // user changes selection (another call), the previous result is
  // discarded and does not repopulate the panel. It never blocks the UI thread.
  Q_INVOKABLE void requestText(const QString &path, int maxBytes = 262144);

signals:
  // content = read text; encoding = "utf-8" | "latin1"; bytes = read;
  // lines = approximate number of lines; truncated = whether the file was
  // larger than maxBytes.
  void textReady(const QString &path, const QString &content,
                 const QString &encoding, qint64 bytes, int lines,
                 bool truncated);

private:
  quint64 m_gen = 0; // generation of the last text request (cancellation)
};

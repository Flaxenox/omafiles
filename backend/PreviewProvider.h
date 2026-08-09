#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <qqmlregistration.h>

// Backend C++ de previsualización (Fase 9, josema). Sustituye a los procesos
// de shell del panel de preview: la LECTURA de texto (antes `head -c 4000`)
// y los METADATOS. La imagen escalada y el PDF los sigue dando
// ThumbnailProvider (Fase 8) a un tamaño de preview -- "caché reutilizando
// ThumbnailProvider cuando sea posible", sin duplicar render/caché. El
// resaltado (Pygments), la miniatura de vídeo (ffmpegthumbnailer) y los
// metadatos de audio (ffprobe) se quedan por ahora en shell.
//
// Sin dependencia de Quickshell: solo Qt público. Singleton QML
// (Omafiles.Backend.PreviewProvider).
class PreviewProvider : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit PreviewProvider(QObject *parent = nullptr);

  // Metadatos del fichero (QFileInfo + QMimeDatabase). Barato y síncrono:
  // { name, path, size, mtime, mime, permissions ("rwxr-x---"...),
  //   readable, writable, executable }.
  Q_INVOKABLE QVariantMap info(const QString &path);

  // Lee el texto de `path` (hasta `maxBytes`, 256 KB por defecto) en un hilo
  // del pool y lo entrega por textReady(). Cancelación por generación: si el
  // usuario cambia de selección (otra llamada), el resultado anterior se
  // descarta y no repuebla el panel. Nunca bloquea el hilo de UI.
  Q_INVOKABLE void requestText(const QString &path, int maxBytes = 262144);

signals:
  // content = texto leído; encoding = "utf-8" | "latin1"; bytes = leídos;
  // lines = nº aproximado de líneas; truncated = si el fichero era mayor que
  // maxBytes.
  void textReady(const QString &path, const QString &content,
                 const QString &encoding, qint64 bytes, int lines,
                 bool truncated);

private:
  quint64 m_gen = 0; // generación de la última petición de texto (cancelación)
};

#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <qqmlregistration.h>

// Backend C++ de miniaturas (Fase 8, josema). Genera thumbnails de imágenes
// (PNG/JPEG/WebP/GIF/SVG) y PDF (primera página) con QImageReader, los
// cachea en disco y los sirve por RUTA de fichero -- igual que el proyecto
// ya hacía con las miniaturas de PDF/vídeo (Image { source: <ruta> }), lo
// que evita registrar un QQuickImageProvider en el engine de Quickshell
// (que no controlamos). Ver BACKEND_DESIGN.md 5.3.
//
// Caché persistente en ~/.cache/omafiles/thumbnails/. La clave es un hash
// (SHA-1) de ruta+tamaño-máximo+tamaño-de-fichero+mtime: si la imagen
// cambia (mtime/tamaño distintos) la clave cambia y se regenera sola
// (invalidación por ruta+tamaño+mtime, como pide el requisito).
//
// Asíncrono: request() vuelve al instante. Si el thumbnail ya está en
// caché devuelve su ruta; si no, devuelve "" y lo genera en un hilo del
// QThreadPool, emitiendo ready(path, thumbPath) al terminar. Para tipos no
// soportados devuelve "" y no genera (la UI deja su glyph de icono).
//
// Singleton QML (Omafiles.Backend.ThumbnailProvider). Sin dependencia de
// Quickshell: solo Qt público.
class ThumbnailProvider : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit ThumbnailProvider(QObject *parent = nullptr);

  // Ruta del thumbnail de `path` (lado máximo `size` px) si ya está en
  // caché; si no, "" y lo genera async -> ready(path, thumbPath). Devuelve
  // "" sin generar si el tipo no se soporta.
  Q_INVOKABLE QString request(const QString &path, int size = 256);

  // Hash canónico de clave de caché en disco (SHA-1 hex de `input`). ES EL
  // ÚNICO esquema de hash de caché de Omafiles (Fase B1): lo usa internamente
  // request() para las miniaturas de imagen/PDF y lo consumen desde QML las
  // rutas que antes usaban Utils.simpleHash (miniaturas de vídeo en
  // logic/VideoThumbnails.qml, caché de extracción en logic/ArchiveActions.
  // qml). Determinista y estable: mismo `input` -> mismo nombre de fichero.
  Q_INVOKABLE QString cacheKey(const QString &input) const;

signals:
  void ready(const QString &path, const QString &thumbPath);

private:
  // Implementación del hash canónico (ver cacheKey()). Estático para poder
  // usarlo desde el worker de generación sin tocar el objeto.
  static QString hashKey(const QString &input);
  // ¿La extensión es de un tipo que sabemos miniaturizar? (barato, evita
  // abrir ficheros de texto/binarios). QImageReader hace la comprobación
  // real al generar.
  static bool supported(const QString &path);
  // Corre en el worker: genera el thumbnail de `path` a `outPath`. Estático
  // (no toca el objeto), seguro aunque el singleton muera durante el hilo.
  static bool generate(const QString &path, int size, const QString &outPath);

  QString m_cacheDir;
  QSet<QString> m_inflight; // claves generándose ahora mismo (dedup)
};

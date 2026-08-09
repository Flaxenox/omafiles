#include "ThumbnailProvider.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QPdfDocument>
#include <QRunnable>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThreadPool>

namespace {

// Extensiones que intentamos miniaturizar. QImageReader hace la
// comprobación real (según los plugins instalados: qwebp, qsvg, qpdf...);
// esta lista solo evita abrir ficheros que seguro no son imágenes.
const QSet<QString> kThumbExts = {
    QStringLiteral("png"),  QStringLiteral("jpg"),  QStringLiteral("jpeg"),
    QStringLiteral("webp"), QStringLiteral("gif"),  QStringLiteral("svg"),
    QStringLiteral("bmp"),  QStringLiteral("ico"),  QStringLiteral("tif"),
    QStringLiteral("tiff"), QStringLiteral("pdf"),
};

} // namespace

ThumbnailProvider::ThumbnailProvider(QObject *parent) : QObject(parent) {
  const QString base =
      QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
  m_cacheDir = base + QStringLiteral("/omafiles/thumbnails");
  QDir().mkpath(m_cacheDir);
}

bool ThumbnailProvider::supported(const QString &path) {
  const QString ext = QFileInfo(path).suffix().toLower();
  return kThumbExts.contains(ext);
}

bool ThumbnailProvider::generate(const QString &path, int size,
                                 const QString &outPath) {
  QImage img;

  if (QFileInfo(path).suffix().toLower() == QLatin1String("pdf")) {
    // PDF: primera página con QPdfDocument (el plugin qpdf de QImageReader
    // no la renderiza de forma fiable). Renderizado a la resolución del
    // thumbnail, no la nativa -> nítido y ligero.
    QPdfDocument doc;
    if (doc.load(path) != QPdfDocument::Error::None || doc.pageCount() < 1)
      return false;
    QSizeF pts = doc.pagePointSize(0);
    if (pts.isEmpty())
      pts = QSizeF(size, size);
    QSize target(size, size);
    if (pts.width() >= pts.height())
      target.setHeight(qMax(1, qRound(size * pts.height() / pts.width())));
    else
      target.setWidth(qMax(1, qRound(size * pts.width() / pts.height())));
    img = doc.render(0, target);
  } else {
    QImageReader reader(path);
    reader.setAutoTransform(true); // respeta la orientación EXIF
    if (!reader.canRead())
      return false;
    // Escalar para caber en un cuadrado de `size`, solo hacia abajo (una
    // imagen ya pequeña se guarda a su tamaño real). Para SVG, vectorial,
    // setScaledSize renderiza directamente a ese tamaño.
    const QSize orig = reader.size();
    if (orig.isValid() && (orig.width() > size || orig.height() > size)) {
      QSize t = orig;
      t.scale(size, size, Qt::KeepAspectRatio);
      reader.setScaledSize(t);
    } else if (!orig.isValid()) {
      reader.setScaledSize(QSize(size, size));
    }
    img = reader.read();
  }

  if (img.isNull())
    return false;

  // Escritura atómica: fichero temporal + rename en commit(), para que la
  // UI nunca cargue un PNG a medio escribir.
  QSaveFile file(outPath);
  if (!file.open(QIODevice::WriteOnly))
    return false;
  if (!img.save(&file, "PNG")) {
    file.cancelWriting();
    return false;
  }
  return file.commit();
}

QString ThumbnailProvider::request(const QString &path, int size) {
  if (!supported(path))
    return QString();

  const QFileInfo fi(path);
  if (!fi.exists() || !fi.isFile())
    return QString();

  // Clave = hash(ruta|tamaño|bytes|mtime): si el fichero cambia, cambia la
  // clave y se regenera (invalidación por ruta+tamaño+mtime).
  const QString raw = path + QLatin1Char('|') + QString::number(size) +
                      QLatin1Char('|') + QString::number(fi.size()) +
                      QLatin1Char('|') +
                      QString::number(fi.lastModified().toSecsSinceEpoch());
  const QString key = QString::fromLatin1(
      QCryptographicHash::hash(raw.toUtf8(), QCryptographicHash::Sha1)
          .toHex());
  const QString outPath =
      m_cacheDir + QLatin1Char('/') + key + QStringLiteral(".png");

  if (QFileInfo::exists(outPath))
    return outPath; // cache hit

  if (m_inflight.contains(key))
    return QString(); // ya se está generando
  m_inflight.insert(key);

  QThreadPool::globalInstance()->start(QRunnable::create(
      [this, path, size, outPath, key]() {
        const bool ok = generate(path, size, outPath);
        QMetaObject::invokeMethod(
            this,
            [this, path, outPath, key, ok]() {
              m_inflight.remove(key);
              if (ok)
                emit ready(path, outPath);
            },
            Qt::QueuedConnection);
      }));
  return QString();
}

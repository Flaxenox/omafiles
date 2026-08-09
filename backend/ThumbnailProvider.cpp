#include "ThumbnailProvider.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QPdfDocument>
#include <QRegularExpression>
#include <QRunnable>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThreadPool>

#include <algorithm>

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

// --- Política de mantenimiento de la caché (Fase O1) -----------------------
// Se cambian aquí, en un único sitio. Una política de edad + una de tamaño.
constexpr qint64 kThumbMaxAgeSecs = 30LL * 24 * 3600;   // 30 días
constexpr qint64 kThumbMaxBytes = 512LL * 1024 * 1024;  // 512 MB

// ¿El nombre es una miniatura del esquema ACTUAL (SHA-1 hex de 40)? Es el
// único patrón que escribe request()/cacheKey desde la Fase B1.
bool isCurrentThumb(const QString &stem) {
  static const QRegularExpression re(QStringLiteral("^[0-9a-f]{40}$"));
  return re.match(stem).hasMatch();
}

// ¿Es un huérfano del esquema base36 ANTIGUO (Utils.simpleHash, <=8 chars)?
// Solo .jpg: las miniaturas de imagen/PDF SIEMPRE fueron SHA-1 .png, así que
// un .png no-hex nunca lo generamos nosotros y no se toca (seguridad).
bool isLegacyOrphan(const QString &stem, const QString &ext) {
  static const QRegularExpression re(QStringLiteral("^[0-9a-z]{1,8}$"));
  return ext == QLatin1String("jpg") && !isCurrentThumb(stem) &&
         re.match(stem).hasMatch();
}

// Poda self-contained de `dir` (NO recursiva: entryInfoList solo lista los
// ficheros directos, nunca sale de la carpeta). Devuelve nº borrados. Solo
// actúa sobre ficheros con el patrón de nombre de Omafiles; cualquier otra
// cosa se deja intacta.
int pruneThumbnailDir(const QString &dir, qint64 maxAgeSecs, qint64 maxBytes) {
  QDir d(dir);
  if (!d.exists())
    return 0;
  const qint64 now = QDateTime::currentSecsSinceEpoch();
  struct Kept {
    QString path;
    qint64 mtime;
    qint64 size;
  };
  QList<Kept> kept;
  int removed = 0;
  const auto infos = d.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
  for (const QFileInfo &fi : infos) {
    const QString ext = fi.suffix().toLower();
    const QString stem = fi.completeBaseName();
    // (1) Huérfano legacy base36 -> borrar sin más (sin consumidor tras B1).
    if (isLegacyOrphan(stem, ext)) {
      if (QFile::remove(fi.absoluteFilePath()))
        ++removed;
      continue;
    }
    // Solo se gestionan miniaturas del esquema actual; lo demás NO se toca.
    if ((ext != QLatin1String("png") && ext != QLatin1String("jpg")) ||
        !isCurrentThumb(stem))
      continue;
    // (2) Política de edad.
    if (now - fi.lastModified().toSecsSinceEpoch() >= maxAgeSecs) {
      if (QFile::remove(fi.absoluteFilePath()))
        ++removed;
      continue;
    }
    kept.append({fi.absoluteFilePath(),
                 fi.lastModified().toSecsSinceEpoch(), fi.size()});
  }
  // (3) Política de tamaño: si el total supera el límite, borra las más
  // antiguas primero hasta volver por debajo.
  qint64 total = 0;
  for (const auto &k : kept)
    total += k.size;
  if (total > maxBytes) {
    std::sort(kept.begin(), kept.end(),
              [](const Kept &a, const Kept &b) { return a.mtime < b.mtime; });
    for (const auto &k : kept) {
      if (total <= maxBytes)
        break;
      if (QFile::remove(k.path)) {
        total -= k.size;
        ++removed;
      }
    }
  }
  return removed;
}

} // namespace

ThumbnailProvider::ThumbnailProvider(QObject *parent) : QObject(parent) {
  const QString base =
      QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
  m_cacheDir = base + QStringLiteral("/omafiles/thumbnails");
  QDir().mkpath(m_cacheDir);
  // Poda de mantenimiento una vez por sesión, en segundo plano (Fase O1).
  // Saltada bajo --selfcheck para no tocar la caché real del usuario durante
  // las pruebas (el arnés valida la política sobre un dir temporal aparte).
  if (!qEnvironmentVariableIsSet("OMAFILES_SELFCHECK"))
    pruneCache();
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
  // clave y se regenera (invalidación por ruta+tamaño+mtime). hashKey() es el
  // esquema canónico compartido con las rutas de QML (ver cacheKey()).
  const QString raw = path + QLatin1Char('|') + QString::number(size) +
                      QLatin1Char('|') + QString::number(fi.size()) +
                      QLatin1Char('|') +
                      QString::number(fi.lastModified().toSecsSinceEpoch());
  const QString key = hashKey(raw);
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

QString ThumbnailProvider::hashKey(const QString &input) {
  return QString::fromLatin1(
      QCryptographicHash::hash(input.toUtf8(), QCryptographicHash::Sha1)
          .toHex());
}

QString ThumbnailProvider::cacheKey(const QString &input) const {
  return hashKey(input);
}

void ThumbnailProvider::pruneCache() {
  // Captura m_cacheDir por valor y usa la función libre (no `this`): seguro
  // aunque el singleton muera mientras el hilo de poda sigue vivo.
  const QString dir = m_cacheDir;
  QThreadPool::globalInstance()->start(QRunnable::create(
      [dir]() { pruneThumbnailDir(dir, kThumbMaxAgeSecs, kThumbMaxBytes); }));
}

int ThumbnailProvider::pruneCacheDir(const QString &dir, qint64 maxAgeSecs,
                                     qint64 maxBytes) const {
  return pruneThumbnailDir(dir, maxAgeSecs, maxBytes);
}

#include "PreviewProvider.h"

#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QRunnable>
#include <QStringConverter>
#include <QThreadPool>

PreviewProvider::PreviewProvider(QObject *parent) : QObject(parent) {}

QVariantMap PreviewProvider::info(const QString &path) {
  const QFileInfo fi(path);
  QVariantMap m;
  m[QStringLiteral("name")] = fi.fileName();
  m[QStringLiteral("path")] = fi.absoluteFilePath();
  m[QStringLiteral("size")] = static_cast<qint64>(fi.size());
  m[QStringLiteral("mtime")] =
      static_cast<qint64>(fi.lastModified().toSecsSinceEpoch());

  // MIME por contenido + extensión (abre y lee una cabecera pequeña; barato
  // para un solo fichero seleccionado).
  static QMimeDatabase db;
  m[QStringLiteral("mime")] = db.mimeTypeForFile(fi).name();

  // Permisos básicos del propietario como cadena "rwx".
  const QFileDevice::Permissions p = fi.permissions();
  QString perms;
  perms += (p & QFileDevice::ReadOwner) ? QLatin1Char('r') : QLatin1Char('-');
  perms += (p & QFileDevice::WriteOwner) ? QLatin1Char('w') : QLatin1Char('-');
  perms += (p & QFileDevice::ExeOwner) ? QLatin1Char('x') : QLatin1Char('-');
  m[QStringLiteral("permissions")] = perms;
  m[QStringLiteral("readable")] = fi.isReadable();
  m[QStringLiteral("writable")] = fi.isWritable();
  m[QStringLiteral("executable")] = fi.isExecutable();
  return m;
}

void PreviewProvider::requestText(const QString &path, int maxBytes) {
  const quint64 gen = ++m_gen;
  QThreadPool::globalInstance()->start(QRunnable::create(
      [this, path, maxBytes, gen]() {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
          return; // ilegible: no emite (el panel deja el estado anterior/vacío)

        const qint64 total = file.size();
        const QByteArray raw = file.read(maxBytes);
        file.close();
        const bool truncated = total > maxBytes;

        // Detección de codificación: intenta UTF-8; si es inválido, Latin-1.
        QStringDecoder dec(QStringConverter::Utf8,
                           QStringConverter::Flag::Stateless);
        QString content = dec.decode(raw);
        QString encoding;
        if (dec.hasError()) {
          content = QString::fromLatin1(raw);
          encoding = QStringLiteral("latin1");
        } else {
          encoding = QStringLiteral("utf-8");
        }

        const int lines = static_cast<int>(content.count(QLatin1Char('\n'))) + 1;
        const qint64 bytes = raw.size();

        QMetaObject::invokeMethod(
            this,
            [this, path, content, encoding, bytes, lines, truncated, gen]() {
              // Cancelación: descartar si ya se pidió otra preview después.
              if (gen != m_gen)
                return;
              emit textReady(path, content, encoding, bytes, lines, truncated);
            },
            Qt::QueuedConnection);
      }));
}

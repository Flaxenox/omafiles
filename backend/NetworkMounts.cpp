#include "NetworkMounts.h"

#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <QVariantMap>

#include <unistd.h>

NetworkMounts::NetworkMounts(QObject *parent) : QObject(parent) {}

QVariantList NetworkMounts::list() const {
  QVariantList out;
  const QString runtime = qEnvironmentVariable(
      "XDG_RUNTIME_DIR",
      QStringLiteral("/run/user/%1").arg(::getuid()));
  QDir gvfs(runtime + QStringLiteral("/gvfs"));
  if (!gvfs.exists())
    return out;

  const auto dirs = gvfs.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
  for (const QFileInfo &fi : dirs) {
    // Nombre interno del mount: "esquema:clave=valor,clave=valor,...".
    const QString name = fi.fileName();
    const int colon = name.indexOf(QLatin1Char(':'));
    const QString scheme = colon >= 0 ? name.left(colon) : name;
    const QString rest = colon >= 0 ? name.mid(colon + 1) : QString();

    // Los valores del nombre de mount de gvfs vienen percent-encoded (un
    // recurso "My Share" es share=My%20Share). Se decodifican de forma nativa
    // con QUrl::fromPercentEncoding (UTF-8-aware) para que la etiqueta de la
    // barra lateral salga legible (Fase 20, josema).
    QString host, share, user;
    const auto pairs = rest.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString &pair : pairs) {
      if (pair.startsWith(QLatin1String("host=")))
        host = QUrl::fromPercentEncoding(pair.mid(5).toUtf8());
      else if (pair.startsWith(QLatin1String("server=")))
        host = QUrl::fromPercentEncoding(pair.mid(7).toUtf8());
      else if (pair.startsWith(QLatin1String("share=")))
        share = QUrl::fromPercentEncoding(pair.mid(6).toUtf8());
      else if (pair.startsWith(QLatin1String("user=")))
        user = QUrl::fromPercentEncoding(pair.mid(5).toUtf8());
    }

    QString proto;
    if (scheme == QLatin1String("sftp"))
      proto = QStringLiteral("SFTP");
    else if (scheme == QLatin1String("ftp") || scheme == QLatin1String("ftps"))
      proto = QStringLiteral("FTP");
    else if (scheme == QLatin1String("dav") || scheme == QLatin1String("davs"))
      proto = QStringLiteral("WebDAV");
    else if (scheme == QLatin1String("smb-share") ||
             scheme == QLatin1String("smb"))
      proto = QStringLiteral("SMB");
    else
      proto = scheme;

    QString label = proto + QStringLiteral(": ") + (host.isEmpty() ? name : host);
    if (!share.isEmpty())
      label += QLatin1Char('/') + share;
    if (!user.isEmpty())
      label += QStringLiteral(" (") + user + QLatin1Char(')');

    QVariantMap m;
    m[QStringLiteral("label")] = label;
    m[QStringLiteral("path")] = fi.absoluteFilePath();
    m[QStringLiteral("scheme")] = scheme;
    out.append(m);
  }
  return out;
}
